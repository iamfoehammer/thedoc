# thedoc tests

Three test suites for the framework. The bash + smoke suites run in CI on
Ubuntu and macOS; the PowerShell wrapper suite runs on Windows.

| File | What it covers | Runtime |
|---|---|---|
| `test_wrapper.sh` | bash `thedoc` wrapper subcommand surface - non-PTY, exit codes + output strings | ~50ms |
| `test_wrapper.ps1` | `thedoc.ps1` wrapper subcommands - same assertions on the PowerShell side | ~1s |
| `smoke_test.py` | `setup.sh` end-to-end via real PTY across 22 scenarios | ~45s |

`thedoc test` runs the bash wrapper + smoke (POSIX shells) or
parse-checks .ps1 + the PowerShell wrapper suite (Windows). Both
mirror what CI runs.

## Running

```bash
bash tests/test_wrapper.sh                       # bash wrapper only
pwsh -File tests/test_wrapper.ps1                # PowerShell wrapper only
python3 tests/smoke_test.py                      # smoke: all scenarios
python3 tests/smoke_test.py happy-path           # smoke: one scenario
python3 tests/smoke_test.py typed-path typed-path-create
python3 tests/smoke_test.py --list               # list smoke labels
python3 tests/smoke_test.py happy-path --keep-logs  # keep PTY logs on PASS
python3 tests/smoke_test.py --clean-logs         # nuke /tmp/thedoc-{smoke,home,state}-* tempdirs/logs
thedoc test                                      # everything available on this OS
```

`--keep-logs` preserves the per-scenario `/tmp/thedoc-smoke-*.log`
files even on overall PASS. Useful when visually inspecting what
setup.sh actually rendered - some glitches (mid-bullet wrap, indent
loss, color-bleed) don't trip the regex/error-pattern assertions
but show clearly in the cleaned PTY transcript.

The smoke suite requires Python 3 and a real PTY (Linux/macOS - won't run
under cmd.exe). Each scenario takes 1-3s; the full 22-scenario suite
finishes in ~45s. Exit codes: 0 = all PASS, 1 = at least one FAIL,
2 = unknown smoke scenario name.

## What it does

For each scenario, the driver:

1. Spawns `setup.sh` under a real PTY (so tty-only behaviors -
   `IFS= read -rsn1` at the "Press any key (space to skip)" prompts
   and `prompt_choice`'s `flush_input` - fire the same code path a
   real user hits).
2. Builds an isolated `$HOME` with a real `~/GitHub/placeholder-project/`
   so the projects-folder scan succeeds without depending on the
   developer's actual `~/GitHub/`.
3. Sets `XDG_STATE_HOME` to a temp dir so first-run state never leaks
   in or out.
4. Sets `THEDOC_NO_LAUNCH=1` so the wizard exits before spawning a real
   `claude` session.
5. Walks each prompt by regex: waits for the prompt text, then waits
   for output to go quiet for 200ms (so the keystroke doesn't race
   with mid-typing animation), then sends the scripted input.
6. Asserts no `unbound variable`, no GNU-only flag rejections, no
   mid-word wrap regressions, and that the scenario's expected end
   state was reached.

Exit 0 = all scenarios PASS. Exit 1 = at least one FAIL, with the
captured PTY log preserved at `/tmp/thedoc-smoke-*.log` for postmortem.

## Scenarios

| Scenario | What it covers | Reference commit |
|---|---|---|
| `happy-path` | Default fresh install, all defaults, reaches `Ready to launch.` | baseline |
| `voyager-yes` | Answers Y to Voyager prompt → exercises EMH ASCII-art reveal + "Press any key to continue" branch | iter 129 |
| `openclaw-doctor` | Picks OpenClaw doctor type (non-default slug) → exercises cp/symlink for a slug ≠ "claude-code" | iter 63 |
| `bootstrap-install` | Sets THEDOC_BOOTSTRAP_DIR to a fake clone; verifies the install branch moves it + adds to PATH | iter 79 |
| `bootstrap-reinstall` | Pre-populated .bashrc; verifies the idempotency check skips the append and the file still has exactly one of each line | iter 81 |
| `bootstrap-rerun` | Existing install + state + new clone: verifies the re-bootstrap branch updates in place, copies new files, and exits before the wizard | iter 100 |
| `bootstrap-rerun-missing-install` | State intact but framework dir deleted + new clone: re-bootstrap moves the clone over instead of orphaning it | iter 101 |
| `negative-name` | Slash and leading-dot rejection in the instance-name validation loop | `44ab195` |
| `empty-name` | Whitespace-only input → trim → empty rejection | `7cc8e5e` |
| `engine-fallback` | Stub engine → "Run with Claude Code instead?" prompt → fallback path | `5fb0980` |
| `engine-fallback-decline` | Same setup, user declines fallback → "Check back later" → exit 0 | iter 60 |
| `open-existing` | Pre-populated valid instance triggers "Open existing? [Y/n]" | `176d16f` |
| `open-existing-decline` | Same setup, user declines → re-prompts for fresh name in same wizard | iter 61 |
| `non-thedoc-folder` | Pre-populated random project folder rejected ("isn't a thedoc instance") | `176d16f` |
| `returning-user` | State file present → wizard skips greeting/scan/projects, jumps to doctor pick | baseline |
| `returning-user-stale-state` | State file points at a deleted projects_dir → setup warns + falls back to dirname-of-script | iter 104 |
| `coming-soon` | Stub doctor type (Gemini) → "templates are coming soon" early exit | `5a93d35` |
| `typed-path` | Custom projects-folder path, target already exists | baseline |
| `typed-path-create` | Custom projects-folder path, target doesn't exist → mkdir branch | baseline |
| `typed-path-decline` | Typed path doesn't exist, user declines "Create it?", re-prompts and accepts a different existing path | iter 42 |
| `typed-path-relative` | Relative path (`.`) rejected with "Path must be absolute"; absolute path then accepted | iter 59 |
| `full-mode` | Setup mode 2 (Full audit) reaches `Ready to launch.` | baseline |

Each scenario has a custom step list and (where the assertion logic
differs from the default) custom `assertions` function. See
`smoke_test.py` for the wiring.

## Adding a scenario

1. Define a step list: `[(regex, bytes_to_send, label), ...]`. Each
   step waits for the regex to appear in cleaned output, then sends
   the bytes.
2. If the scenario needs pre-state (e.g. an existing folder), write a
   `pre_setup(project_dir, state_dir)` callback.
3. If the scenario doesn't reach `Ready to launch.`, write a custom
   `assertions(cleaned)` function (see `coming_soon_assertions`).
4. Add a `failures += run(steps=..., label=..., pre_setup=..., assertions=...)`
   call in `main()`.

The driver and helpers live in `smoke_test.py`. CI runs the suite on
both Ubuntu and macOS via `.github/workflows/test.yml`.
