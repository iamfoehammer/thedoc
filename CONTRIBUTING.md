# Contributing to thedoc

Thanks for considering a contribution. thedoc is small and aims to stay
that way; this guide covers how to extend it without breaking the
runtime expectations.

## Repo layout

```
thedoc/
├── thedoc, setup.sh, bootstrap.sh         # Entry points (bash)
├── setup.ps1, bootstrap.ps1               # Entry points (PowerShell 7+)
├── doctors/<type>/DOCTOR.md               # Per-doctor brain
│   └── updates/                           # Versioned update notes
├── engines/<engine>.{sh,ps1}              # LLM backend launchers
├── common/templates/                      # Battle-tested config templates
├── common/skills/                         # Reusable Claude Code skills
├── llm-secrets, llm-secrets.ps1           # Secret storage tool
├── tests/smoke_test.py                    # E2E test driver
└── .github/workflows/test.yml             # CI: Ubuntu + macOS smoke
```

## Running the test suite

```bash
python3 tests/smoke_test.py     # or: thedoc test
```

Requires Python 3 and a real PTY (Linux/macOS — won't run under
cmd.exe). The full suite finishes in ~25s. Every PR runs the
suite on both Ubuntu and macOS via GitHub Actions. See
[`tests/README.md`](tests/README.md) for what each scenario covers
and how to add a new one.

The smoke harness sets `THEDOC_TEST_SKIP_TYPING=1` so every
scenario runs with typing animations and dramatic pauses
disabled. If you're debugging a race or stress-testing the
animated path, run `python3 tests/smoke_test.py happy-path`
under a debugger that doesn't propagate the env var.

## Code style and portability

This is a strict requirement, not a preference: **all bash code in this
repo must run on macOS (BSD userland + bash 3.2)**, not just Linux.
A surprising number of common patterns are GNU-only:

| Avoid | Use |
|---|---|
| `grep -P` (Perl regex) | `grep -E` (POSIX extended) or `sed -n 's/…/&/p'` |
| `sed 's/…/\+/'` (BRE plus) | `sed -E 's/…/+/'` (ERE) |
| `find -readable` | drop the flag; `find` skips unreadable dirs anyway |
| `date -Iseconds` | `date -u +"%Y-%m-%dT%H:%M:%SZ"` |
| `readlink -f` | manual loop or `cd "$(dirname "$f")" && pwd` |
| `xargs -r` | `xargs` (no need to skip empty input on BSD) |
| `sort -V` | `sort -t. -n -k1 -k2 -k3` (or just stick to lexical) |
| `fold -s -w N` | awk word-wrap (BSD `fold -s` mis-handles tight columns) |

Bash 3.2 also has a couple of footguns worth knowing:

- `${arr[@]}` on an empty array errors out under `set -u`. Guard with
  `[ "${#arr[@]}" -gt 0 ]` before iterating.
- Per-character loops with `printf '%s' "${var:$i:1}"` are slow. If you
  need speed, batch.

The CI macOS job (`smoke-macos` in `.github/workflows/test.yml`) is the
canonical regression rig for these portability rules.

PowerShell code targets PS 7+, not Windows PowerShell 5.1. The preflight
in `setup.ps1` and `bootstrap.ps1` rejects older versions with a clear
message.

## Adding a new doctor type

1. Create `doctors/<slug>/DOCTOR.md` with the doctor's brain. If the
   doctor isn't actually implemented yet, include the literal string
   `not yet supported` in the first 5 lines — the gate in setup.sh
   (`is_stub` helper) and setup.ps1 (`Test-IsStub`) treats that as a
   stub and gracefully exits with "templates are coming soon" instead
   of dropping the user into Claude reading a useless brain.
2. Add an entry in `setup.sh` and `setup.ps1`'s `DOCTOR_TYPES` /
   `DOCTOR_SLUGS` arrays.
3. Create `doctors/<slug>/updates/.gitkeep` so the empty directory
   ships in the clone (otherwise the framework-update symlink/junction
   created by setup points at a non-existent path).
4. Run `python3 tests/smoke_test.py` to confirm nothing else broke.

## Adding a new engine

1. Create `engines/<slug>.sh` (and `.ps1` if you want Windows native
   support). Same `not yet supported` stub convention applies.
2. Add to `ENGINE_TYPES` / `ENGINE_SLUGS` in both setup scripts.
3. The engine launcher receives three args: `INSTANCE_DIR SETUP_MODE
   DOCTOR_TYPE`. See `engines/claude-code.sh` for the canonical shape.
4. The PS launcher mirrors the bash signature with `-InstanceDir
   -SetupMode -DoctorType` named parameters.

## Adding a smoke test scenario

See [`tests/README.md`](tests/README.md). The short version:

```python
MY_NEW_STEPS = [
    (re.compile(r'…prompt regex…'), b'…input bytes…', 'human label'),
    …
]

# in main():
failures += run(steps=MY_NEW_STEPS, label='my-new')
```

Include `THEDOC_NO_LAUNCH=1` is set automatically — your scenario
exits before spawning a real Claude session. If your scenario doesn't
reach `Ready to launch.`, write a custom `assertions(cleaned)` function
and pass it via `assertions=` (see `coming_soon_assertions` for an
example).

## Pull requests

- Keep changes focused: one fix or feature per PR.
- Include `Co-Authored-By:` if you used an AI assistant.
- The CI must pass on both Ubuntu and macOS.
- New behavior should have a smoke test scenario when feasible.

## License

MIT.
