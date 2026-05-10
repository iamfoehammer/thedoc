#!/usr/bin/env python3
"""End-to-end smoke test for thedoc setup.sh.

Spawns setup.sh under a real PTY (so the tty-only behaviors - async
space-to-skip, prompt_choice's flush_input, [Console]::ReadKey-equivalent
read -rsn1 - exercise the same code path a real user would hit), waits
for each known prompt by regex, sends scripted input, and asserts that
the script reaches `Ready to launch.` cleanly.

Uses THEDOC_NO_LAUNCH=1 to avoid spawning a real Claude Code session.

Run:
    python3 tests/smoke_test.py

Exit code 0 on success, 1 on failure. Prints a colorized summary plus
the path to the captured log for postmortem.
"""
from __future__ import annotations

import os
import pty
import re
import select
import shutil
import signal
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETUP_SH  = os.path.join(REPO_ROOT, 'setup.sh')

ANSI_RE = re.compile(rb'\x1b\[[0-9;]*[A-Za-z]')

# (regex, bytes_to_send, label) — driver waits for the regex to appear in
# the cumulative cleaned output, then sends. None regex sends after a
# short delay regardless.
HAPPY_PATH_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n', 'Voyager: n (skip image)'),
    (re.compile(r'Press any key to begin the scan'),        b' ', 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1', 'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ', 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1', 'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1', 'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                           b'1', 'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n', 'Default instance name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n', 'Open existing if any'),
]

# Picks an unsupported engine (OpenClaw stub) and confirms the fallback
# prompt fires. Verifies the gate from commit 5fb0980 catches stub
# engines BEFORE the instance directory + DOCTOR.md get created.
ENGINE_FALLBACK_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                    b'n',  'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),         b' ',  'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),     b'1',  'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),       b' ',  'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),               b'1',  'Doctor type: 1 (Claude Code)'),
    (re.compile(r'Which LLM engine'),                        b'2',  'Engine: 2 (OpenClaw stub)'),
    (re.compile(r'Run with Claude Code instead\? \[Y/n\]'),  b'\n', 'Accept Claude Code fallback'),
    (re.compile(r'Setup mode\?'),                            b'1',  'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),    b'\n', 'Default instance name'),
    (re.compile(r'already exists.*\[Y/n\]'),                 b'\n', 'Open existing if any'),
]

# Picks the default instance name when an instance already exists at that
# path. Confirms the "Open existing instance? [Y/n]" prompt fires and the
# yes-path reaches Ready to launch (no instance recreation, just relaunch).
OPEN_EXISTING_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                  b'n',  'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),       b' ',  'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),   b'1',  'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),     b' ',  'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),             b'1',  'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                      b'1',  'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                          b'1',  'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),  b'\n', 'Default name (matches existing)'),
    (re.compile(r'Open existing instance\? \[Y/n\]'),      b'\n', 'Yes - open existing'),
]


def pre_create_instance(project_dir, slug='claude-code'):
    """Pre-populate a fake doctor instance so the open-existing path fires."""
    instance = os.path.join(project_dir, f'{slug}-doctor')
    os.makedirs(instance, exist_ok=True)
    with open(os.path.join(instance, 'DOCTOR.md'), 'w') as f:
        f.write('# Pretend Doctor for testing\n')
    with open(os.path.join(instance, 'CLAUDE.md'), 'w') as f:
        f.write('# Pretend CLAUDE.md for testing\n')


# Drives the wizard through a deliberately bad instance name first, then
# a valid one. Confirms the validation loop in setup.sh actually re-prompts.
NEGATIVE_NAME_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n',                   'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ',                   'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1',                   'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ',                   'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1',                   'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1',                   'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                           b'1',                   'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),   b'foo/bar\n',           'Bad name: foo/bar (slash)'),
    (re.compile(r"Name can't contain '/'"),                 b'.hidden\n',           'Bad name: .hidden (leading dot)'),
    (re.compile(r"Name can't start with '\.'"),             b'good-instance\n',    'Good name'),
]


def green(s):  return f'\x1b[32m{s}\x1b[0m'
def red(s):    return f'\x1b[31m{s}\x1b[0m'
def yellow(s): return f'\x1b[33m{s}\x1b[0m'


def run(steps=HAPPY_PATH_STEPS, timeout=20.0, columns=80, label='happy-path',
        pre_setup=None):
    state_dir = tempfile.mkdtemp(prefix='thedoc-state-')
    log_path  = tempfile.mktemp(prefix='thedoc-smoke-', suffix='.log')

    # Fake HOME with a real ~/GitHub/ that contains one dummy subdir, so
    # detect_projects_dirs lists ~/GitHub/ as candidate #1 of the menu.
    # `find -type d` in the bash code does NOT follow symlinks, so a real
    # directory is required - a symlink to project_dir would silently hide.
    fake_home    = tempfile.mkdtemp(prefix='thedoc-home-')
    fake_github  = os.path.join(fake_home, 'GitHub')
    os.makedirs(fake_github)
    os.makedirs(os.path.join(fake_github, 'placeholder-project'))
    project_dir  = fake_github

    # Optional fixture hook for scenario-specific pre-state (e.g. an
    # already-existing doctor instance to trigger the open-existing path).
    if pre_setup:
        pre_setup(project_dir)

    env = os.environ.copy()
    env.update({
        'XDG_STATE_HOME':    state_dir,
        'COLUMNS':           str(columns),
        'LINES':             '40',
        'TERM':              'xterm-256color',
        'THEDOC_NO_LAUNCH':  '1',
        'HOME':              fake_home,
    })
    # Suppress WSL drive scanning during the test - it'd drag /mnt/ paths
    # into the candidate list and confuse the menu shortcut. The bash
    # detect_platform reads /proc/version for the WSL signal; pointing it
    # at something innocuous via /etc keeps it host-shape only.
    env['WSL_DISTRO_NAME'] = ''  # won't disable detection, but documents intent

    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe('/bin/bash', ['/bin/bash', SETUP_SH], env)

    out = bytearray()
    log = open(log_path, 'wb')
    deadline  = time.time() + timeout
    step_idx  = 0
    last_send = 0.0
    sent      = []

    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(fd, 4096)
                if not chunk:
                    break
                out.extend(chunk)
                log.write(chunk)
                log.flush()
            except OSError:
                break

        if step_idx < len(steps):
            pattern, data, step_label = steps[step_idx]
            cleaned = ANSI_RE.sub(b'', bytes(out)).decode('utf-8', 'replace')
            if pattern.search(cleaned):
                if time.time() - last_send > 0.4:
                    time.sleep(0.4)
                    os.write(fd, data)
                    sent.append(step_label)
                    step_idx += 1
                    last_send = time.time()
                    time.sleep(0.3)

    try:
        os.kill(pid, signal.SIGTERM)
        time.sleep(0.2)
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass
    os.close(fd)
    log.close()

    cleaned = ANSI_RE.sub(b'', bytes(out)).decode('utf-8', 'replace')

    # ── Assertions ────────────────────────────────────────────────────
    failures = []

    if 'Ready to launch' not in cleaned:
        failures.append("Did not reach 'Ready to launch.'")

    if 'THEDOC_NO_LAUNCH' not in cleaned:
        failures.append("Did not reach the THEDOC_NO_LAUNCH gate")

    error_patterns = [
        ('unbound variable',        'set -u tripped'),
        ('invalid option',          'GNU-only option used somewhere'),
        ('command not found',       'missing dependency'),
        (r'\bpro jects\b',          'mid-word wrap regression'),
        (r'\bfold er\b',            'mid-word wrap regression'),
    ]
    for pat, msg in error_patterns:
        if re.search(pat, cleaned):
            failures.append(f'{msg}  (matched {pat!r})')

    # Cleanup
    for d in (state_dir, fake_home):
        shutil.rmtree(d, ignore_errors=True)
    # Leave project_dir for inspection if the test failed; otherwise nuke it
    if not failures:
        shutil.rmtree(project_dir, ignore_errors=True)

    print()
    print(f'  [{label}]')
    print(f'  steps sent:   {len(sent)}/{len(steps)}')
    print(f'  output bytes: {len(out)}')
    print(f'  log:          {log_path}')
    if failures:
        print(f'  result:       {red("FAIL")}')
        for f in failures:
            print(f'    - {red(f)}')
        return 1
    print(f'  result:       {green("PASS")}')
    return 0


def _full_mode_steps():
    """Quick-mode steps with the Setup-mode answer flipped to '2' (Full)."""
    full = []
    for pat, data, lbl in HAPPY_PATH_STEPS:
        if lbl == 'Mode: 1 (Quick)':
            full.append((pat, b'2', 'Mode: 2 (Full)'))
        else:
            full.append((pat, data, lbl))
    return full


def main():
    failures = 0
    print('=' * 60)
    failures += run(steps=HAPPY_PATH_STEPS,      label='happy-path')
    failures += run(steps=NEGATIVE_NAME_STEPS,   label='negative-name')
    failures += run(steps=ENGINE_FALLBACK_STEPS, label='engine-fallback')
    failures += run(steps=OPEN_EXISTING_STEPS,   label='open-existing',
                    pre_setup=pre_create_instance)
    failures += run(steps=_full_mode_steps(),    label='full-mode')
    print('=' * 60)
    print(f'  overall: {green("PASS") if failures == 0 else red(f"{failures} FAILED")}')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
