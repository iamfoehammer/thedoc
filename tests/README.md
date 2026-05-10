# thedoc tests

Small set of smoke tests. Not a full test suite — just enough to catch
regressions in the core setup.sh flow before they ship.

## Running

```bash
python3 tests/smoke_test.py
```

Requires Python 3 and a Linux/macOS PTY (won't run under cmd.exe). The
test:

1. Spawns `setup.sh` under a real PTY
2. Walks the wizard end-to-end with scripted input (Voyager: no, skip
   animations, pick first projects folder, accept defaults through to
   instance name)
3. Sets `THEDOC_NO_LAUNCH=1` so the script exits before spawning Claude
4. Asserts no `unbound variable`, no `command not found`, no mid-word
   wrap regressions, and that the flow reaches `Ready to launch.`

A `HOME` override + `GitHub` symlink to a temp directory ensures the
projects-folder scan succeeds without depending on the developer's
real `~/GitHub/`.

Exit 0 = PASS, exit 1 = FAIL with the captured log preserved.
