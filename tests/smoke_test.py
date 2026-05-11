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

import atexit
import glob
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


def _cleanup_typed_path_fixtures():
    """Remove the typed-path fixtures regardless of how the suite ends:
    normal completion, Ctrl+C, or unhandled exception. Without this, an
    interrupted run leaks /tmp/thedoc-smoke-typed-projects-<pid>/ dirs."""
    shutil.rmtree(TYPED_PATH_FIXTURE, ignore_errors=True)
    shutil.rmtree(TYPED_PATH_CREATE,  ignore_errors=True)


def _cleanup_bootstrap_fixtures():
    """Defensive cleanup for /tmp/thedoc-smoke-bootstrap-* fixtures from
    pre_bootstrap / pre_bootstrap_reinstall / pre_bootstrap_rerun_* etc.
    In the happy path setup.sh's bootstrap branch already moves/rm's
    them, but a Ctrl+C between pre_setup and the move would leak. Glob
    by PID so we don't nuke parallel runs."""
    for p in glob.glob(f'/tmp/thedoc-smoke-bootstrap-*-{os.getpid()}'):
        shutil.rmtree(p, ignore_errors=True)
    # Also the PID-suffixed but not -prefixed variant (pre_bootstrap uses
    # just /tmp/thedoc-smoke-bootstrap-<pid>):
    shutil.rmtree(f'/tmp/thedoc-smoke-bootstrap-{os.getpid()}', ignore_errors=True)


atexit.register(_cleanup_typed_path_fixtures)
atexit.register(_cleanup_bootstrap_fixtures)


# Paths the typed-path scenarios feed to setup.sh. Living outside any
# per-run fake_home fixture so the "Type a path" branch sees an absolute
# path a user might plausibly enter. PID-suffixed so concurrent test runs
# (e.g. local + CI) don't race over the same paths. Cleanup hooks below
# remove them on suite completion AND on Ctrl+C / unhandled exception.
TYPED_PATH_FIXTURE = f'/tmp/thedoc-smoke-typed-projects-{os.getpid()}'
TYPED_PATH_CREATE  = f'/tmp/thedoc-smoke-typed-projects-to-create-{os.getpid()}'

ANSI_RE = re.compile(rb'\x1b\[[0-9;]*[A-Za-z]')


# (regex, bytes_to_send, label) — driver waits for the regex to appear in
# the cumulative cleaned output (starting from the previous match's end),
# then sends. Most scenarios share the same first 7 steps - greeting flow,
# scan, projects-folder pick (option 1), explainer, doctor-type pick,
# engine pick, mode pick - so they live in COMMON_FIRSTRUN_STEPS for
# scenarios to extend with their distinctive trailing steps.
COMMON_FIRSTRUN_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n', 'Voyager: n (skip image)'),
    (re.compile(r'Press any key to begin the scan'),        b' ', 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1', 'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ', 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1', 'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1', 'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                           b'1', 'Mode: 1 (Quick)'),
]

HAPPY_PATH_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),   b'\n', 'Default instance name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n', 'Open existing if any'),
]


# Voyager Y branch: user answers 'y' so the EMH ASCII art + "Press any
# key to continue..." prompt fires before the scan. Every other scenario
# sends 'n' so this code path went 100+ iterations untested. The ASCII
# art is in thedoc.txt at the framework root - if a future refactor
# breaks the file path or content, this scenario catches it.
VOYAGER_YES_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'y', 'Voyager: y'),
    (re.compile(r'Press any key to continue\.\.\.'),        b' ', 'Continue from EMH reveal'),
    (re.compile(r'Press any key to begin the scan'),        b' ', 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1', 'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ', 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1', 'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1', 'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                           b'1', 'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n', 'Default name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n', 'Open existing if any'),
]


# Picks OpenClaw as the doctor type (slot 2, has a real DOCTOR.md) with
# Claude Code as the engine. Exercises a doctor_slug other than
# "claude-code" through the cp/symlink/CLAUDE.md generation path - which
# happy-path never does. Catches regressions where the wizard accidentally
# hard-codes "claude-code" in template generation or path expansion.
OPENCLAW_DOCTOR_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n', 'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ', 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1', 'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ', 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'2', 'Doctor type: 2 (OpenClaw)'),
    (re.compile(r'Which LLM engine'),                       b'1', 'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                           b'1', 'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n', 'Default name (openclaw-doctor)'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n', 'Open existing if any'),
]

# Picks an unsupported engine (OpenClaw stub) and confirms the fallback
# prompt fires. Verifies the gate from commit 5fb0980 catches stub
# engines BEFORE the instance directory + DOCTOR.md get created.
# Engine-fallback diverges at step 6 (engine pick) - sends '2' for the
# OpenClaw stub instead of '1', then handles the fallback prompt - so it
# can't extend COMMON_FIRSTRUN_STEPS unchanged. Built explicitly.
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


# Same setup as ENGINE_FALLBACK_STEPS, but the user DECLINES "Run with
# Claude Code instead?". Setup should print "Check back later..." and exit
# without creating an instance. Catches regressions in the exit-0 branch
# (e.g. if someone accidentally swaps the conditional).
ENGINE_FALLBACK_DECLINE_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                    b'n',  'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),         b' ',  'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),     b'1',  'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),       b' ',  'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),               b'1',  'Doctor type: 1 (Claude Code)'),
    (re.compile(r'Which LLM engine'),                        b'2',  'Engine: 2 (OpenClaw stub)'),
    (re.compile(r'Run with Claude Code instead\? \[Y/n\]'),  b'n\n', 'Decline fallback'),
]

# Picks the default instance name when an instance already exists at that
# path. Confirms the "Open existing instance? [Y/n]" prompt fires and the
# yes-path reaches Ready to launch (no instance recreation, just relaunch).
OPEN_EXISTING_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),  b'\n', 'Default name (matches existing)'),
    (re.compile(r'Open existing instance\? \[Y/n\]'),      b'\n', 'Yes - open existing'),
]


# Picks an existing instance name, DECLINES "Open existing? [Y/n]", expects
# to be re-prompted for the name (not kicked back to a re-run of the whole
# wizard). Then types a fresh name and reaches Ready to launch.
# Pre-iter-61 the no-path called exit 0 with "Re-run and pick a different
# name" - this test guards the new in-wizard re-prompt loop.
OPEN_EXISTING_DECLINE_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),  b'\n',                'Default name (collides)'),
    (re.compile(r'Open existing instance\? \[Y/n\]'),      b'n\n',               'No - I want a new one'),
    (re.compile(r'pick a different name'),                 b'fresh-instance\n',  'Type fresh name'),
]


def pre_create_instance(project_dir, state_dir, slug='claude-code'):
    """Pre-populate a fake doctor instance so the open-existing path fires."""
    instance = os.path.join(project_dir, f'{slug}-doctor')
    os.makedirs(instance, exist_ok=True)
    with open(os.path.join(instance, 'DOCTOR.md'), 'w') as f:
        f.write('# Pretend Doctor for testing\n')
    with open(os.path.join(instance, 'CLAUDE.md'), 'w') as f:
        f.write('# Pretend CLAUDE.md for testing\n')


def pre_create_non_thedoc_folder(project_dir, state_dir, slug='claude-code'):
    """Pre-populate a directory at the default name but WITHOUT a DOCTOR.md.
    Mirrors the case where someone has an unrelated project sharing the
    name thedoc would pick - setup must refuse to use it."""
    other = os.path.join(project_dir, f'{slug}-doctor')
    os.makedirs(other, exist_ok=True)
    with open(os.path.join(other, 'README.md'), 'w') as f:
        f.write("# Some other project, not a thedoc instance\n")
    with open(os.path.join(other, 'main.py'), 'w') as f:
        f.write("print('not thedoc')\n")


def pre_typed_path(project_dir, state_dir):
    """Pre-create TYPED_PATH_FIXTURE with one subdir so the 'Type a path'
    branch finds a valid existing directory and skips the create prompt."""
    shutil.rmtree(TYPED_PATH_FIXTURE, ignore_errors=True)
    os.makedirs(os.path.join(TYPED_PATH_FIXTURE, 'sub-project'))


def pre_typed_path_create(project_dir, state_dir):
    """Ensure TYPED_PATH_CREATE does NOT exist so setup.sh hits the
    'doesn't exist. Create it? [Y/n]' branch and exercises mkdir."""
    shutil.rmtree(TYPED_PATH_CREATE, ignore_errors=True)


def pre_bootstrap(project_dir, state_dir):
    """Mimic what bootstrap.sh does: clone the framework to a temp dir and
    set THEDOC_BOOTSTRAP_DIR for setup.sh. The bootstrap branch in setup.sh
    moves that temp dir into PROJECTS_DIR/thedoc and rewrites SCRIPT_DIR,
    so the bootstrap source needs the full framework tree (DOCTOR.md +
    engines/ + updates/ etc.). Copies in the repo minus .git/.

    Returns env-extras for the run() so the driver passes
    THEDOC_BOOTSTRAP_DIR to setup.sh."""
    bootstrap_dir = f'/tmp/thedoc-smoke-bootstrap-{os.getpid()}'
    shutil.rmtree(bootstrap_dir, ignore_errors=True)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shutil.copytree(
        repo_root, bootstrap_dir,
        symlinks=False,
        ignore=shutil.ignore_patterns('.git', '__pycache__', '*.pyc'),
    )
    return {'THEDOC_BOOTSTRAP_DIR': bootstrap_dir}


def pre_bootstrap_rerun_with_state(project_dir, state_dir):
    """Re-bootstrap scenario: state already exists, bootstrap dir is set.
    Pre-iter-100 this combination silently skipped the move (the bootstrap
    branch was gated on is_first_run); iter 100 added an explicit
    re-bootstrap branch that updates the installed framework in place
    and exits BEFORE Show-Greeting / the wizard.

    Pre-state setup:
      - state file pointing at project_dir
      - project_dir/thedoc/ exists with a 'marker.txt' to verify the
        bootstrap overlay copied successfully
      - THEDOC_BOOTSTRAP_DIR points at a fresh clone of the framework
    """
    # Pre-existing state file (returning user)
    thedoc_dir = os.path.join(state_dir, 'thedoc')
    os.makedirs(thedoc_dir, exist_ok=True)
    with open(os.path.join(thedoc_dir, 'state'), 'w') as f:
        f.write('first_run=2026-05-10T00:00:00Z\n')
        f.write(f'projects_dir={project_dir}\n')
        f.write('platform=linux\n')

    # Pre-existing installed framework with a stub file
    installed = os.path.join(project_dir, 'thedoc')
    os.makedirs(installed, exist_ok=True)
    with open(os.path.join(installed, 'marker.txt'), 'w') as f:
        f.write('pre-rerun marker - should survive\n')

    # Fresh clone temp dir with a different marker
    bootstrap_dir = f'/tmp/thedoc-smoke-bootstrap-rerun-{os.getpid()}'
    shutil.rmtree(bootstrap_dir, ignore_errors=True)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shutil.copytree(
        repo_root, bootstrap_dir,
        symlinks=False,
        ignore=shutil.ignore_patterns('.git', '__pycache__', '*.pyc'),
    )
    # Add an only-in-bootstrap file so we can verify it got copied over
    with open(os.path.join(bootstrap_dir, 'rerun-canary.txt'), 'w') as f:
        f.write('only in the new clone\n')
    return {'THEDOC_BOOTSTRAP_DIR': bootstrap_dir}


def stale_state_assertions(cleaned, ctx=None):
    """Stale-state scenario: verify the iter 104 warning appears at the
    start of the returning-user wizard. We don't drive past the first
    prompt because the fallback projects_dir on a test machine is
    unpredictable - the warning itself is the load-bearing assertion."""
    failures = []
    if "state's projects_dir" not in cleaned:
        failures.append("Warning missing: \"state's projects_dir\"")
    if 'is missing' not in cleaned:
        failures.append("Warning missing: 'is missing'")
    return failures


def pre_write_stale_state(project_dir, state_dir):
    """Pre-write a state file whose projects_dir points at a NEVER-existed
    path. Returning-user flow triggers, but the saved projects_dir fails
    the [ -d ] check and setup falls back to dirname-of-script. Iter 104
    added a warning on that fallback - this scenario verifies it appears
    and ALSO that the wizard continues to Ready to launch (the warning
    is informational, not a hard stop)."""
    thedoc_dir = os.path.join(state_dir, 'thedoc')
    os.makedirs(thedoc_dir, exist_ok=True)
    with open(os.path.join(thedoc_dir, 'state'), 'w') as f:
        f.write('first_run=2026-05-09T12:00:00+00:00\n')
        f.write(f'projects_dir=/nonexistent/stale-{os.getpid()}\n')
        f.write('platform=linux\n')


def pre_bootstrap_rerun_no_install(project_dir, state_dir):
    """Same as pre_bootstrap_rerun_with_state but with NO installed framework
    at project_dir/thedoc. Simulates: user deleted ~/GitHub/thedoc but the
    state file still points at ~/GitHub. Iter 101 added the re-install
    branch for this sub-case so the new clone gets moved over instead of
    orphaned in TMP."""
    # Pre-existing state file (returning user)
    thedoc_dir = os.path.join(state_dir, 'thedoc')
    os.makedirs(thedoc_dir, exist_ok=True)
    with open(os.path.join(thedoc_dir, 'state'), 'w') as f:
        f.write('first_run=2026-05-10T00:00:00Z\n')
        f.write(f'projects_dir={project_dir}\n')
        f.write('platform=linux\n')

    # Deliberately DO NOT create project_dir/thedoc - that's the bug surface

    # Fresh clone temp dir
    bootstrap_dir = f'/tmp/thedoc-smoke-bootstrap-reinstall-{os.getpid()}'
    shutil.rmtree(bootstrap_dir, ignore_errors=True)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    shutil.copytree(
        repo_root, bootstrap_dir,
        symlinks=False,
        ignore=shutil.ignore_patterns('.git', '__pycache__', '*.pyc'),
    )
    with open(os.path.join(bootstrap_dir, 'reinstall-canary.txt'), 'w') as f:
        f.write('proves the move/cp happened\n')
    return {'THEDOC_BOOTSTRAP_DIR': bootstrap_dir}


def bootstrap_reinstall_branch_assertions(cleaned, ctx):
    """Re-bootstrap when framework is missing: setup.sh should print
    'Re-installing thedoc at <path>' and 'Installed thedoc.' then exit.
    Canary file from the clone must land in the (now-created) framework
    dir."""
    failures = []
    if 'Re-installing thedoc at' not in cleaned:
        failures.append("Re-install branch did not run ('Re-installing thedoc at' missing)")
    if 'Installed thedoc' not in cleaned:
        failures.append("Did not print final 'Installed thedoc'")
    if 'Ready to launch' in cleaned:
        failures.append("Reached 'Ready to launch' - should have exited at install")
    if 'Hologram activated' in cleaned:
        failures.append("Greeting fired - should have exited before Show-Greeting")
    canary = os.path.join(ctx['project_dir'], 'thedoc', 'reinstall-canary.txt')
    if not os.path.exists(canary):
        failures.append(f"Re-install did not move clone: {canary} missing")
    return failures


def bootstrap_rerun_assertions(cleaned, ctx):
    """Re-bootstrap on existing install: setup.sh should print 'Updating
    thedoc at <path>' and exit before reaching Show-Greeting / Ready to
    launch. Filesystem assert: the rerun-canary file from the new clone
    must now be in the installed framework dir (proves the overlay
    copied)."""
    failures = []
    if 'Updating thedoc at' not in cleaned:
        failures.append("Re-bootstrap branch did not run ('Updating thedoc at' missing)")
    if 'Updated thedoc' not in cleaned:
        failures.append("Re-bootstrap did not print final 'Updated thedoc'")
    if 'Ready to launch' in cleaned:
        failures.append("Reached 'Ready to launch' - re-bootstrap should exit before the wizard")
    # Greeting must NOT have fired - re-bootstrap exits before Show-Greeting.
    if 'Hologram activated' in cleaned:
        failures.append("Greeting fired - re-bootstrap should exit before Show-Greeting")
    # Verify the new clone's canary file landed in the installed framework
    canary = os.path.join(ctx['project_dir'], 'thedoc', 'rerun-canary.txt')
    if not os.path.exists(canary):
        failures.append(f"Bootstrap overlay did not copy: {canary} missing")
    return failures


def pre_bootstrap_reinstall(project_dir, state_dir):
    """Like pre_bootstrap, but also pre-populates HOME/.bashrc with the
    exact lines setup.sh's bootstrap branch would add. Simulates a user
    re-running the install one-liner: the idempotency check (iter 70's
    grep -qF "$THEDOC_FINAL" / grep -qF 'source "$HOME/.secrets"') must
    skip the appends so the file still has exactly one of each.

    bootstrap_assertions's 'exactly 1 line' counts catch any regression
    where a future refactor loosens the grep matches and starts
    appending duplicates on every run."""
    extras = pre_bootstrap(project_dir, state_dir)
    fake_home = os.path.dirname(project_dir)
    thedoc_final = os.path.join(project_dir, 'thedoc')
    bashrc = os.path.join(fake_home, '.bashrc')
    with open(bashrc, 'w') as f:
        f.write('# thedoc - Emergency Medical Hologram framework\n')
        f.write(f'export PATH="{thedoc_final}:$PATH"\n')
        f.write('[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"\n')
    return extras


def _bashrc_line_counts(ctx):
    """Returns (path_count, secrets_count) for HOME/.bashrc, or (None, None)
    if the file is missing. Shared between bootstrap_assertions variants."""
    bashrc = os.path.join(ctx['fake_home'], '.bashrc')
    if not os.path.exists(bashrc):
        return None, None
    with open(bashrc) as f:
        rc_content = f.read()
    path_lines    = rc_content.count('export PATH="') + rc_content.count("export PATH='")
    secrets_lines = rc_content.count('source "$HOME/.secrets"')
    return path_lines, secrets_lines


def bootstrap_assertions(cleaned, ctx):
    """Bootstrap-install scenario: setup.sh moved thedoc into projects dir
    and added it to PATH + secrets sourcing. Verifies both the visible
    output markers AND the side effects on disk (HOME/.bashrc gets the
    PATH and source lines), each appearing exactly once (idempotency
    guard from iter 70's tightened grep checks)."""
    failures = list(default_assertions(cleaned, ctx))
    if 'Installed thedoc to' not in cleaned:
        failures.append("Bootstrap branch did not run ('Installed thedoc to' missing)")
    if 'Added thedoc to PATH' not in cleaned:
        failures.append("PATH append did not run ('Added thedoc to PATH' missing)")

    path_lines, secrets_lines = _bashrc_line_counts(ctx)
    if path_lines is None:
        failures.append("Bootstrap branch did not write .bashrc")
    else:
        if path_lines != 1:
            failures.append(f".bashrc has {path_lines} PATH export lines (expected 1)")
        if secrets_lines != 1:
            failures.append(f".bashrc has {secrets_lines} secrets-source lines (expected 1)")
    return failures


def bootstrap_reinstall_assertions(cleaned, ctx):
    """Bootstrap-reinstall scenario: HOME/.bashrc was pre-populated with
    the PATH + secrets lines. setup.sh's bootstrap branch must skip the
    appends (idempotency) so the file STILL has exactly one of each.

    The 'Added thedoc to PATH' message must NOT print, because the
    idempotency grep finds the path already there and the branch
    skips the append+message. That's the inverse of the install case.

    Iter 91 added 'already on PATH' / 'already wired' confirmation lines
    on the skip branches so the user sees ack of the idempotent state
    instead of an abrupt jump from 'Installed thedoc to...' to 'Got it.'.
    Requiring those messages locks iter 91 in place."""
    failures = list(default_assertions(cleaned, ctx))
    if 'Installed thedoc to' not in cleaned:
        failures.append("Bootstrap branch did not run ('Installed thedoc to' missing)")
    if 'Added thedoc to PATH' in cleaned:
        failures.append("PATH was appended on re-run (idempotency check broken)")
    if 'already on PATH' not in cleaned:
        failures.append("Idempotency skip did not acknowledge ('already on PATH' missing)")
    if 'secrets sourcing already wired' not in cleaned:
        failures.append("Secrets idempotency did not acknowledge")

    path_lines, secrets_lines = _bashrc_line_counts(ctx)
    if path_lines is None:
        failures.append("Bootstrap branch unexpectedly removed .bashrc")
    else:
        if path_lines != 1:
            failures.append(f".bashrc has {path_lines} PATH lines after re-run (expected 1)")
        if secrets_lines != 1:
            failures.append(f".bashrc has {secrets_lines} secrets-source lines after re-run (expected 1)")
    return failures


def pre_typed_path_decline(project_dir, state_dir):
    """Decline scenario types a non-existent path first (must NOT exist),
    then a real path on re-prompt (must exist). Reset both fixtures - the
    create scenario typically runs before this one and leaves
    TYPED_PATH_CREATE created behind."""
    shutil.rmtree(TYPED_PATH_CREATE, ignore_errors=True)
    shutil.rmtree(TYPED_PATH_FIXTURE, ignore_errors=True)
    os.makedirs(os.path.join(TYPED_PATH_FIXTURE, 'sub-project'))


def pre_write_state(project_dir, state_dir, slug='claude-code'):
    """Pre-write a thedoc state file under $XDG_STATE_HOME/thedoc/state to
    simulate a returning user. is_first_run() in setup.sh returns false,
    so the greeting types a quip and the script jumps straight to the
    doctor-type pick - no Voyager prompt, no tricorder scan, no project
    folder picker."""
    thedoc_dir = os.path.join(state_dir, 'thedoc')
    os.makedirs(thedoc_dir, exist_ok=True)
    with open(os.path.join(thedoc_dir, 'state'), 'w') as f:
        f.write('first_run=2026-05-09T12:00:00+00:00\n')
        f.write(f'projects_dir={project_dir}\n')
        f.write('platform=linux\n')


# Returning user: state file exists, setup skips greeting/scan/projects
# and jumps straight to doctor-type pick. Most-common real-world flow -
# the user already ran setup once.
RETURNING_USER_STEPS = [
    (re.compile(r'What is this doctor for\?'),             b'1',  'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                      b'1',  'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                          b'1',  'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),  b'\n', 'Default instance name'),
    (re.compile(r'already exists.*\[Y/n\]'),               b'\n', 'Open existing if any'),
]


# Picks "Type a path" instead of an auto-detected candidate. Confirms the
# custom-path branch end-to-end: prompt appears, typed path is accepted as
# an existing directory, structure explainer fires, instance gets created
# under the typed path. Catches regressions in iter-2 commit 44ab195.
TYPED_PATH_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                  b'n',                                'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),       b' ',                                'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),   b'3',                                'Projects: option 3 (Type a path)'),
    (re.compile(r'Enter the full path:'),                  (TYPED_PATH_FIXTURE + '\n').encode(), 'Type fixture path'),
    (re.compile(r'Press any key to continue \(space'),     b' ',                                'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),             b'1',                                'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                      b'1',                                'Engine: 1 (Claude Code)'),
    (re.compile(r'Setup mode\?'),                          b'1',                                'Mode: 1 (Quick)'),
    (re.compile(r'Name for your doctor instance folder'),  b'\n',                               'Default name'),
    (re.compile(r'already exists.*\[Y/n\]'),               b'\n',                               'Open existing if any'),
]


# User types a non-existent path, declines "Create it?", expects setup
# to re-prompt for a path rather than aborting. Tests the re-prompt loop
# in iter-2 commit 44ab195. Requires the driver's last_pos cursor (added
# in this commit) to disambiguate the second "Enter the full path:".
TYPED_PATH_DECLINE_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n',                                'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ',                                'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'3',                                'Projects: option 3 (Type a path)'),
    (re.compile(r'Enter the full path:'),                   (TYPED_PATH_CREATE + '\n').encode(),  'Type non-existent path'),
    (re.compile(r"That folder doesn't exist. Create it\?"), b'n\n',                              'Decline create'),
    (re.compile(r'Enter the full path:'),                   (TYPED_PATH_FIXTURE + '\n').encode(), 'Type real path on re-prompt'),
    (re.compile(r'Press any key to continue \(space'),      b' ',                                'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1',                                'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1',                                'Engine: 1'),
    (re.compile(r'Setup mode\?'),                           b'1',                                'Mode: 1'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n',                               'Default name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n',                               'Open existing if any'),
]


# User types a relative path ('.') which the wizard must reject because
# PROJECTS_DIR ends up saved to state literally - a relative path would
# resolve against whatever cwd 'thedoc list' / setup ran from later,
# silently pointing at the wrong place. The wizard should print
# "Path must be absolute" and re-prompt; absolute path then accepted.
TYPED_PATH_RELATIVE_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n',                                 'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ',                                 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'3',                                 'Projects: option 3 (Type a path)'),
    (re.compile(r'Enter the full path:'),                   b'.\n',                               'Type relative path'),
    (re.compile(r'Path must be absolute'),                  (TYPED_PATH_FIXTURE + '\n').encode(), 'Type absolute on re-prompt'),
    (re.compile(r'Press any key to continue \(space'),      b' ',                                 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1',                                 'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1',                                 'Engine: 1'),
    (re.compile(r'Setup mode\?'),                           b'1',                                 'Mode: 1'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n',                                'Default name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n',                                'Open existing if any'),
]


# Like TYPED_PATH_STEPS, but the typed path doesn't exist beforehand so
# setup hits the "doesn't exist. Create it?" branch and exercises mkdir.
TYPED_PATH_CREATE_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n',                              'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ',                              'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'3',                              'Projects: option 3 (Type a path)'),
    (re.compile(r'Enter the full path:'),                   (TYPED_PATH_CREATE + '\n').encode(), 'Type non-existent path'),
    (re.compile(r"That folder doesn't exist. Create it\?"), b'\n',                             'Default Y - create'),
    (re.compile(r'Press any key to continue \(space'),      b' ',                              'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'1',                              'Doctor type: 1'),
    (re.compile(r'Which LLM engine'),                       b'1',                              'Engine: 1'),
    (re.compile(r'Setup mode\?'),                           b'1',                              'Mode: 1'),
    (re.compile(r'Name for your doctor instance folder'),   b'\n',                             'Default name'),
    (re.compile(r'already exists.*\[Y/n\]'),                b'\n',                             'Open existing if any'),
]


# Picks an unsupported doctor type (Gemini today). Setup must print the
# "templates are coming soon" message and exit without creating any
# instance. Different assertions than the default (Ready to launch
# should NOT appear).
COMING_SOON_STEPS = [
    (re.compile(r'Star Trek: Voyager\?'),                   b'n', 'Voyager: n'),
    (re.compile(r'Press any key to begin the scan'),        b' ', 'Skip animations'),
    (re.compile(r'Which one is your projects folder\?'),    b'1', 'Projects: option 1'),
    (re.compile(r'Press any key to continue \(space'),      b' ', 'Continue from explainer'),
    (re.compile(r'What is this doctor for\?'),              b'3', 'Doctor type: 3 (Gemini stub)'),
]


# Pre-populates a non-thedoc directory at the default-name path. Confirms
# setup refuses it ("isn't a thedoc instance") and re-prompts for a
# different name, instead of running claude in a random project folder.
NON_THEDOC_FOLDER_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),  b'\n',               'Accept default (will collide)'),
    (re.compile(r"isn't a thedoc instance"),               b'fresh-instance\n', 'Pick fresh name after rejection'),
]


# Tests whitespace-only instance name. The trim step in the validation
# loop must zero-out "   " into "" and trip the empty-string guard,
# re-prompting the user. Different arm of the loop than slash/dot tests.
EMPTY_NAME_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),   b'   \n',             'Whitespace-only name'),
    (re.compile(r"Name can't be empty or whitespace"),      b'fresh-instance\n',  'Good name after rejection'),
]


# Drives the wizard through a deliberately bad instance name first, then
# a valid one. Confirms the validation loop in setup.sh actually re-prompts.
NEGATIVE_NAME_STEPS = COMMON_FIRSTRUN_STEPS + [
    (re.compile(r'Name for your doctor instance folder'),   b'foo/bar\n',           'Bad name: foo/bar (slash)'),
    (re.compile(r"Name can't contain '/'"),                 b'.hidden\n',           'Bad name: .hidden (leading dot)'),
    (re.compile(r"Name can't start with '\.'"),             b'good-instance\n',    'Good name'),
]


def green(s):  return f'\x1b[32m{s}\x1b[0m'
def red(s):    return f'\x1b[31m{s}\x1b[0m'
def yellow(s): return f'\x1b[33m{s}\x1b[0m'


def default_assertions(cleaned, ctx=None):
    """Standard pass criteria: setup.sh reached the launch gate cleanly."""
    failures = []
    if 'Ready to launch' not in cleaned:
        failures.append("Did not reach 'Ready to launch.'")
    if 'THEDOC_NO_LAUNCH' not in cleaned:
        failures.append("Did not reach the THEDOC_NO_LAUNCH gate")
    return failures


def setup_mode_assertions(expected_mode):
    """Default + verify the generated CLAUDE.md actually got the expected
    setup_mode slug. Iter 153 found that the `full-mode` smoke scenario
    sent '2' at the Setup-mode prompt but never verified setup.sh
    actually treated it as 'full' downstream - a regression that swapped
    the SETUP_SLUGS order would have shipped 'quick' under the 'full'
    label and the test still PASSED (the silent-pass pattern: visible
    output post-prompt is identical, only the CLAUDE.md byte payload
    differs). Reading the generated file closes that loophole."""
    def _check(cleaned, ctx=None):
        failures = list(default_assertions(cleaned, ctx))
        # Instance lands at <project_dir>/<slug>-doctor/ - see setup.sh
        # `INSTANCE_DIR="$PROJECTS_DIR/$instance_name"`. Default slug name
        # for Claude Code is 'claude-code-doctor'.
        claude_md = os.path.join(ctx['project_dir'], 'claude-code-doctor', 'CLAUDE.md')
        if not os.path.exists(claude_md):
            failures.append(f"Generated CLAUDE.md missing: {claude_md}")
            return failures
        with open(claude_md) as f:
            content = f.read()
        marker = f"**Setup mode:** {expected_mode}"
        if marker not in content:
            failures.append(
                f"CLAUDE.md should contain {marker!r}; "
                f"got:\n{_excerpt(content, 'Setup mode')}")
        return failures
    return _check


def doctor_type_assertions(expected_slug, expected_display_name):
    """Default + verify the right doctor template actually got installed.
    Same silent-pass closing as setup_mode_assertions (iter 153): the
    openclaw-doctor scenario sends '2' at the doctor-type prompt but
    only checking 'Ready to launch' would PASS even if DOCTOR_SLUGS got
    reordered and Claude Code's template shipped under the openclaw
    slug. Three artifacts pin the choice:
      1. instance dir named '<slug>-doctor' must exist (proves
         INSTANCE_DIR computed from the right DOCTOR_SLUGS[idx])
      2. CLAUDE.md must contain '**Doctor type:** <display_name>'
         (proves the right doctor_name flowed through generation)
      3. DOCTOR.md must contain the per-doctor H1 ('Emergency Medical
         Hologram - <display_name>') so we know the right template
         file got copied, not just renamed cosmetically
    """
    def _check(cleaned, ctx=None):
        failures = list(default_assertions(cleaned, ctx))
        instance_dir = os.path.join(ctx['project_dir'], f'{expected_slug}-doctor')
        if not os.path.isdir(instance_dir):
            failures.append(f"Instance dir missing: {instance_dir}")
            return failures
        claude_md = os.path.join(instance_dir, 'CLAUDE.md')
        doctor_md = os.path.join(instance_dir, 'DOCTOR.md')
        if not os.path.exists(claude_md):
            failures.append(f"CLAUDE.md missing: {claude_md}")
        else:
            with open(claude_md) as f:
                content = f.read()
            marker = f"**Doctor type:** {expected_display_name}"
            if marker not in content:
                failures.append(
                    f"CLAUDE.md should contain {marker!r}; "
                    f"got:\n{_excerpt(content, 'Doctor type')}")
        if not os.path.exists(doctor_md):
            failures.append(f"DOCTOR.md missing: {doctor_md}")
        else:
            with open(doctor_md) as f:
                content = f.read()
            h1_marker = f"Emergency Medical Hologram - {expected_display_name}"
            if h1_marker not in content:
                failures.append(
                    f"DOCTOR.md should contain {h1_marker!r}; "
                    f"first 200 chars:\n{content[:200]!r}")
        return failures
    return _check


def _excerpt(content, needle, ctx_lines=2):
    """Trim a multi-line string to the lines around the first occurrence
    of `needle`. Keeps assertion-failure output manageable on big files."""
    lines = content.splitlines()
    for i, line in enumerate(lines):
        if needle in line:
            lo = max(0, i - ctx_lines)
            hi = min(len(lines), i + ctx_lines + 1)
            return '\n'.join(lines[lo:hi])
    return f"(needle {needle!r} not found)"


def typed_path_assertions(expected_projects_dir):
    """Default + verify the instance landed under the typed projects_dir,
    not in a fallback location. Same silent-pass closing as iter 153:
    typed-path scenarios sent '3' + a path for many iterations but only
    checked 'Ready to launch' - a regression where the typed-path branch
    fell through to $HOME/GitHub fallback would have PASSED visibly
    (the wizard reaches Ready to launch either way; only the directory
    where the instance lands differs).

    Also reads state file to confirm projects_dir was persisted under
    the typed value. The state file is what 'thedoc list' / 'thedoc
    open' rely on, so if it diverged from the typed-path branch this
    catches it."""
    def _check(cleaned, ctx=None):
        failures = list(default_assertions(cleaned, ctx))
        expected_instance = os.path.join(expected_projects_dir, 'claude-code-doctor')
        if not os.path.isdir(expected_instance):
            failures.append(
                f"Instance did not land at typed path; expected "
                f"{expected_instance}")
        # State file should record the typed path. ctx['state_dir'] is the
        # XDG_STATE_HOME smoke set up; setup.sh writes to <state_dir>/thedoc/state.
        state_file = os.path.join(ctx['state_dir'], 'thedoc', 'state')
        if not os.path.exists(state_file):
            failures.append(f"State file missing: {state_file}")
        else:
            with open(state_file) as f:
                state = f.read()
            marker = f"projects_dir={expected_projects_dir}"
            if marker not in state:
                failures.append(
                    f"State file should contain {marker!r}; got:\n{state}")
        return failures
    return _check


def space_skip_assertions(cleaned, ctx=None):
    """default + lock in that the space-to-skip keypress was actually
    captured. Iter 151 discovered `read -rsn1 key` silently drops space
    under default IFS, so SKIP_TYPING never flipped from a real user's
    keystroke - the bug was masked in tests by THEDOC_TEST_SKIP_TYPING=1.
    The fix uses `IFS= read -rsn1 key` plus a visible 'Animations
    disabled.' ack. Requiring 2 occurrences of the ack proves BOTH:
    (a) the tricorder-scan space-keypress path executed, AND
    (b) the structure-explainer space-keypress path executed.

    Without this assertion, the test would silently revert to relying on
    the env var if the IFS= fix got reverted - exactly the failure mode
    iter 87/iter 148 documented for assertions on AFTER-the-gate text."""
    failures = list(default_assertions(cleaned, ctx))
    ack_count = cleaned.count('Animations disabled.')
    if ack_count < 2:
        failures.append(
            f"Expected 2x 'Animations disabled.' acks, got {ack_count} - "
            "space-keypress may not be reaching read -rsn1")
    return failures


def coming_soon_assertions(cleaned, ctx=None):
    """For scenarios that pick an unsupported doctor type and bail early."""
    failures = []
    if 'doctor templates are coming soon' not in cleaned:
        failures.append("Did not reach 'doctor templates are coming soon'")
    if 'Ready to launch' in cleaned:
        failures.append("Reached 'Ready to launch' - should have exited earlier")
    return failures


def name_validation_assertions(*required_messages):
    """Builds an assertions function that requires Ready to launch AND
    each of the given validation messages to appear in cleaned output.
    Guards iter 87's class of bug: a test that drove "rejection then
    recovery" steps could silently fall through to the happy-path if the
    rejection branch was unreachable - the smoke driver would just never
    match the rejection regex, and default_assertions's "Ready to launch
    reached" was satisfied by the wizard accepting the default instead.

    Asserting on the rejection text directly closes that loophole."""
    def _check(cleaned, ctx=None):
        failures = list(default_assertions(cleaned, ctx))
        for msg in required_messages:
            if msg not in cleaned:
                failures.append(f"Validation message missing: {msg!r}")
        return failures
    return _check


def engine_decline_assertions(cleaned, ctx=None):
    """User declined the 'Run with Claude Code instead?' fallback - setup
    should print the 'Check back later' line and exit without creating any
    instance (no Ready to launch)."""
    failures = []
    if 'Check back later' not in cleaned:
        failures.append("Did not see 'Check back later' on decline")
    if 'Ready to launch' in cleaned:
        failures.append("Reached 'Ready to launch' - should have exited at decline")
    return failures


def run(steps=HAPPY_PATH_STEPS, timeout=20.0, columns=80, label='happy-path',
        pre_setup=None, assertions=None):
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
    # already-existing doctor instance, or a saved state file simulating
    # a returning-user run). Receives both directories so callbacks can
    # populate either side without needing access to internals. May
    # return a dict to merge into the child's env (e.g. THEDOC_BOOTSTRAP_DIR).
    extra_env = None
    if pre_setup:
        extra_env = pre_setup(project_dir, state_dir)

    env = os.environ.copy()
    env.update({
        'XDG_STATE_HOME':           state_dir,
        'COLUMNS':                  str(columns),
        'LINES':                    '40',
        'TERM':                     'xterm-256color',
        'THEDOC_NO_LAUNCH':         '1',
        'THEDOC_TEST_SKIP_TYPING':  '1',
        'HOME':                     fake_home,
    })
    if isinstance(extra_env, dict):
        env.update(extra_env)
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
    started = time.time()
    deadline = started + timeout
    step_idx = 0
    sent     = []
    # Position cursor in the cleaned-output string. Each step's regex only
    # searches output produced after the previous successful match, so a
    # second occurrence of the same prompt (e.g. "Enter the full path:"
    # after the user declines to create the typed path) doesn't get
    # matched by stale cumulative output.
    last_pos = 0

    def drain_until_quiet(quiet_ms=120, max_wait_ms=1500):
        """Read bytes until no new output arrives for `quiet_ms`. Used to
        wait for a prompt to finish painting before sending input - the
        typing animation can otherwise be mid-character when the regex
        matches the prompt text, racing with our keystroke.

        120ms quiet threshold tuned to balance reliability and speed:
        higher (200ms) added ~1s per scenario without measurable benefit,
        lower (50ms) caused flakes on slow machines."""
        last_chunk = time.time()
        end = last_chunk + (max_wait_ms / 1000.0)
        while time.time() < end and time.time() < deadline:
            if (time.time() - last_chunk) * 1000 >= quiet_ms:
                return
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                    if not chunk:
                        return
                    out.extend(chunk)
                    log.write(chunk)
                    log.flush()
                    last_chunk = time.time()
                except OSError:
                    return

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
            m = pattern.search(cleaned, last_pos)
            if m:
                # Most steps wait for the prompt to finish painting before
                # sending. Pre-skip steps (which queue a space for typeit's
                # async-poll BEFORE typing starts) must skip the drain -
                # otherwise drain_until_quiet hits its max_wait while the
                # greeting types continuously, and by the time we send,
                # most of the greeting is already typed.
                if not step_label.startswith('Pre-skip'):
                    drain_until_quiet()
                os.write(fd, data)
                sent.append(step_label)
                step_idx += 1
                last_pos = m.end()
                # Small post-send delay so the script can register the
                # keystroke and start producing the next prompt. 80ms
                # tuned the same way as drain_until_quiet's threshold.
                time.sleep(0.08)

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
    # Default to "reached Ready to launch" criteria; scenarios can override
    # for paths that intentionally exit early (e.g. unsupported doctor type).
    if assertions is None:
        assertions = default_assertions
    ctx = {
        'fake_home':   fake_home,
        'project_dir': project_dir,
        'state_dir':   state_dir,
    }
    failures = list(assertions(cleaned, ctx))

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

    elapsed = time.time() - started
    print()
    print(f'  [{label}]')
    print(f'  steps sent:   {len(sent)}/{len(steps)}')
    print(f'  output bytes: {len(out)}')
    print(f'  elapsed:      {elapsed:.2f}s')
    print(f'  log:          {log_path}')
    if failures:
        print(f'  result:       {red("FAIL")}')
        for f in failures:
            print(f'    - {red(f)}')
        return 1, log_path
    print(f'  result:       {green("PASS")}')
    return 0, log_path


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
    # Each entry is (label, kwargs-for-run). Order is the run order.
    SCENARIOS = [
        ('happy-path',        dict(steps=HAPPY_PATH_STEPS,
                                   assertions=space_skip_assertions)),
        # Assert BOTH the tagline AND a chunk of the ASCII art rendered.
        # Tagline-only would silently pass if a future refactor broke the
        # `cat "$SCRIPT_DIR/thedoc.txt"` call (wrong path, empty file,
        # missing permission) - the tagline prints after the cat regardless.
        # A run of '@' chars is the strongest content signature in thedoc.txt.
        ('voyager-yes',       dict(steps=VOYAGER_YES_STEPS,
                                   assertions=name_validation_assertions(
                                       'The Emergency Medical Hologram, reporting for duty',
                                       '@@@@@@@@@@@@@@@@@@@@'))),
        ('openclaw-doctor',   dict(steps=OPENCLAW_DOCTOR_STEPS,
                                   assertions=doctor_type_assertions(
                                       'openclaw', 'OpenClaw'))),
        ('bootstrap-install', dict(steps=HAPPY_PATH_STEPS,
                                   pre_setup=pre_bootstrap,
                                   assertions=bootstrap_assertions)),
        ('bootstrap-reinstall', dict(steps=HAPPY_PATH_STEPS,
                                     pre_setup=pre_bootstrap_reinstall,
                                     assertions=bootstrap_reinstall_assertions)),
        ('bootstrap-rerun',   dict(steps=[],
                                   pre_setup=pre_bootstrap_rerun_with_state,
                                   assertions=bootstrap_rerun_assertions,
                                   timeout=10.0)),
        ('bootstrap-rerun-missing-install',
                              dict(steps=[],
                                   pre_setup=pre_bootstrap_rerun_no_install,
                                   assertions=bootstrap_reinstall_branch_assertions,
                                   timeout=10.0)),
        ('negative-name',     dict(steps=NEGATIVE_NAME_STEPS,
                                   assertions=name_validation_assertions(
                                       "Name can't contain '/'",
                                       "Name can't start with '.'"))),
        ('empty-name',        dict(steps=EMPTY_NAME_STEPS,
                                   assertions=name_validation_assertions(
                                       "Name can't be empty or whitespace"))),
        ('engine-fallback',   dict(steps=ENGINE_FALLBACK_STEPS,
                                   assertions=name_validation_assertions(
                                       'OpenClaw engine support is coming soon',
                                       'OK - using Claude Code instead'))),
        ('engine-fallback-decline', dict(steps=ENGINE_FALLBACK_DECLINE_STEPS,
                                         assertions=engine_decline_assertions)),
        ('open-existing',     dict(steps=OPEN_EXISTING_STEPS,
                                   pre_setup=pre_create_instance,
                                   assertions=name_validation_assertions(
                                       'already exists as a doctor instance',
                                       'OK - opening existing instance'))),
        ('open-existing-decline', dict(steps=OPEN_EXISTING_DECLINE_STEPS,
                                       pre_setup=pre_create_instance,
                                       assertions=name_validation_assertions(
                                           'OK - pick a different name'))),
        ('non-thedoc-folder', dict(steps=NON_THEDOC_FOLDER_STEPS,
                                   pre_setup=pre_create_non_thedoc_folder,
                                   assertions=name_validation_assertions(
                                       "isn't a thedoc instance"))),
        ('returning-user',    dict(steps=RETURNING_USER_STEPS,
                                   pre_setup=pre_write_state)),
        # Stale-state warning scenario: state file's projects_dir is gone,
        # setup.sh falls back to dirname-of-script. We only need to verify
        # the warning appears - the full doctor-creation flow lands the
        # instance in the fallback dir (which on a test machine has
        # unpredictable contents). Use a no-step scenario with a custom
        # assertions that ONLY checks for the warning.
        ('returning-user-stale-state',
                              dict(steps=[],
                                   pre_setup=pre_write_stale_state,
                                   assertions=stale_state_assertions,
                                   timeout=2.5)),
        ('coming-soon',       dict(steps=COMING_SOON_STEPS,
                                   assertions=coming_soon_assertions)),
        ('typed-path',          dict(steps=TYPED_PATH_STEPS,
                                     pre_setup=pre_typed_path,
                                     assertions=typed_path_assertions(
                                         TYPED_PATH_FIXTURE))),
        ('typed-path-create',   dict(steps=TYPED_PATH_CREATE_STEPS,
                                     pre_setup=pre_typed_path_create,
                                     assertions=typed_path_assertions(
                                         TYPED_PATH_CREATE))),
        ('typed-path-decline',  dict(steps=TYPED_PATH_DECLINE_STEPS,
                                     pre_setup=pre_typed_path_decline,
                                     assertions=name_validation_assertions(
                                         "That folder doesn't exist. Create it?",
                                         'OK - type a different path'))),
        ('typed-path-relative', dict(steps=TYPED_PATH_RELATIVE_STEPS,
                                     pre_setup=pre_typed_path,
                                     assertions=name_validation_assertions(
                                         'Path must be absolute'))),
        ('full-mode',         dict(steps=_full_mode_steps(),
                                   assertions=setup_mode_assertions('full'))),
    ]

    # Optional argv filter: `python3 smoke_test.py happy-path negative-name`
    # runs only the named scenarios. No args = run all.
    # --keep-logs preserves per-scenario PTY logs even on PASS, for visual
    # inspection of what setup.sh actually rendered (rendering glitches
    # don't always trip the regex/error-pattern assertions). Iter 82's
    # hanging-indent fix was found this way.
    argv = sys.argv[1:]

    # --help / -h: print usage and exit. Without this, --help falls through
    # to the "unknown scenario" branch which is confusing.
    if any(a in ('--help', '-h', 'help') for a in argv):
        print('thedoc smoke test driver')
        print()
        print('Usage:')
        print('  python3 tests/smoke_test.py                        Run all scenarios')
        print('  python3 tests/smoke_test.py <scenario> [<sc2>...]  Run named scenarios')
        print('  python3 tests/smoke_test.py --list                 List scenario labels')
        print('  python3 tests/smoke_test.py --keep-logs            Keep PTY logs on PASS (default deletes)')
        print('  python3 tests/smoke_test.py --clean-logs           Remove all /tmp/thedoc-smoke-*.log and exit')
        print('  python3 tests/smoke_test.py --help                 Show this help')
        print()
        print('Exit codes: 0 = all PASS, 1 = any FAIL, 2 = unknown scenario name')
        return

    keep_logs = '--keep-logs' in argv
    argv = [a for a in argv if a != '--keep-logs']

    # --clean-logs: nuke all kept PTY logs and exit. Hundreds of /tmp/thedoc-smoke-*
    # logs can accumulate from --keep-logs / failed runs; this is the recovery.
    if '--clean-logs' in argv:
        removed = 0
        for p in glob.glob('/tmp/thedoc-smoke-*.log'):
            try:
                os.remove(p)
                removed += 1
            except OSError:
                pass
        print(f'Removed {removed} log file(s) under /tmp/thedoc-smoke-*.log')
        return

    requested = argv
    if requested == ['--list']:
        for label, _ in SCENARIOS:
            print(label)
        return
    if requested:
        known = {label for label, _ in SCENARIOS}
        unknown = [s for s in requested if s not in known]
        if unknown:
            print(red(f'Unknown scenario(s): {", ".join(unknown)}'))
            print('Available: ' + ', '.join(label for label, _ in SCENARIOS))
            sys.exit(2)
        SCENARIOS = [(l, k) for l, k in SCENARIOS if l in requested]

    failures = 0
    log_files = []
    print('=' * 60)
    for label, kwargs in SCENARIOS:
        f, log_path = run(label=label, **kwargs)
        failures += f
        log_files.append(log_path)
    # Clean up the typed-path fixtures (live outside any per-run fake_home).
    # Also covered by the atexit hook above, but doing it eagerly keeps
    # the disk tidy if the user inspects /tmp between runs.
    _cleanup_typed_path_fixtures()
    # On full PASS, remove the per-scenario PTY logs - they're only useful
    # for postmortem on failure, and /tmp can otherwise accumulate hundreds
    # of stale logs across many runs. On any FAIL, all logs are kept.
    # --keep-logs overrides: useful for visual inspection of rendered output.
    if failures == 0 and not keep_logs:
        for lp in log_files:
            try:
                os.remove(lp)
            except OSError:
                pass
    print('=' * 60)
    print(f'  overall: {green("PASS") if failures == 0 else red(f"{failures} FAILED")}')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
