# Contributing to thedoc

Thanks for considering a contribution. thedoc is small and aims to stay
that way; this guide covers how to extend it without breaking the
runtime expectations.

## Repo layout

```
thedoc/
├── thedoc, setup.sh, bootstrap.sh         # Entry points (bash)
├── thedoc.ps1, setup.ps1, bootstrap.ps1   # Entry points (PowerShell 7+)
├── thedoc.cmd                             # cmd.exe shim for thedoc.ps1
├── doctors/<type>/DOCTOR.md               # Per-doctor brain
│   └── updates/                           # Versioned update notes
├── engines/<engine>.{sh,ps1}              # LLM backend launchers
├── common/templates/                      # Battle-tested config templates
├── common/skills/                         # Reusable Claude Code skills
├── llm-secrets, llm-secrets.ps1           # Secret storage tool
├── tests/smoke_test.py                    # PTY-based E2E driver (POSIX-only)
├── tests/test_wrapper.{sh,ps1}            # Wrapper subcommand assertions
└── .github/workflows/test.yml             # CI: Ubuntu + macOS smoke + Windows parse/wrapper
```

## Running the test suite

```bash
# POSIX shells (Linux/macOS/WSL/Git Bash)
bash tests/test_wrapper.sh             # wrapper subcommand assertions, ~50ms
python3 tests/smoke_test.py            # setup.sh end-to-end via PTY, ~47s
python3 tests/smoke_test.py --help     # all driver flags + exit codes

# PowerShell
pwsh -File tests/test_wrapper.ps1      # thedoc.ps1 subcommand assertions

# Or run everything for the current OS:
thedoc test                            # forwards args to smoke (--keep-logs, scenario name, etc.)
```

The smoke driver uses `pty.fork()` and is POSIX-only — it won't
run under cmd.exe or native Windows pwsh. On Windows, CI's parse
+ AST function-presence check plus `tests/test_wrapper.ps1` are
the closest equivalents. Every PR runs the bash + smoke suite on
Ubuntu and macOS, and the parse + wrapper suite on Windows.
See [`tests/README.md`](tests/README.md) for what each smoke
scenario covers and how to add a new one.

The smoke harness sets `THEDOC_TEST_SKIP_TYPING=1` so every
scenario runs with typing animations and dramatic pauses
disabled. If you're debugging a race or stress-testing the
animated path, run `python3 tests/smoke_test.py happy-path`
under a debugger that doesn't propagate the env var.

Useful smoke flags when investigating a rendering issue:

- `--keep-logs` — preserve `/tmp/thedoc-smoke-*.log` even on PASS so
  you can `sed 's/\x1b\[[0-9;]*m//g'` and read the cleaned PTY transcript.
  Several rendering bugs (iter 82's hanging indent, iter 84's stub
  redundancy, iter 86's wrap overflow) were found by reading the
  transcript directly, not by writing more assertions.
- `--clean-logs` — nuke all kept logs and exit. `/tmp/` can accumulate
  hundreds of files from repeated `--keep-logs` runs.

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
| `mktemp -t TEMPLATE` | bare `mktemp` (GNU `-t` takes a template; BSD takes a prefix - X's not interpreted) |

Bash 3.2 also has a couple of footguns worth knowing:

- `${arr[@]}` on an empty array errors out under `set -u`. Guard with
  `[ "${#arr[@]}" -gt 0 ]` before iterating.
- Per-character loops with `printf '%s' "${var:$i:1}"` are slow. If you
  need speed, batch.
- `read` (default IFS) silently strips leading/trailing whitespace.
  Combined with `${var:-default}`, whitespace-only input substitutes
  the default and bypasses validation. Prefix with `IFS=` when you
  want the validator to see what the user actually typed.
- Reading a file that crossed OSes (state file written by Windows PS
  Set-Content, anything that might come from Notepad, etc.) via
  `sed -n 's/^k=//p'` preserves the trailing `\r` in the captured
  value. The result fails `[ -d ]` / `[ -f ]` even when the path is
  valid. Strip with `${var%$'\r'}` after every such capture.

The CI macOS job (`smoke-macos` in `.github/workflows/test.yml`) is the
canonical regression rig for these portability rules.

PowerShell code targets PS 7+, not Windows PowerShell 5.1. The preflight
in `setup.ps1` and `bootstrap.ps1` rejects older versions with a clear
message. A few PS gotchas that bit during the port (inline-commented
at the call sites; flagging here for cross-shell contributors):

| Trap | Symptom | Fix |
|---|---|---|
| `Copy-Item -LiteralPath "$dir/*"` | `*` is treated literally, nothing copies | Use `-Path` with `Join-Path $dir '*'` |
| `[CmdletBinding()] param([string]$Command)` then `script.ps1 --help` | "A parameter cannot be found that matches parameter name 'help'" | Drop param/CmdletBinding, read `$args[0]` instead |
| `Get-ChildItem ... \| ForEach-Object { ... }` for list output | Filesystem order, not alphabetical | Pipe through `Sort-Object Name` first |
| `[Console]::ReadKey($true)` directly after typing animation | Stale keypress from animation skip auto-selects menu | Drain with `while ([Console]::KeyAvailable) { [Console]::ReadKey($true) \| Out-Null }` |

## Line endings + editor settings

`.editorconfig` pins LF + 4-space indent for shells / PS / Python /
Markdown / YAML; most modern editors honor this without a plugin.

`.gitattributes` pins LF in git's working-tree normalization, which
matters more than the editor setting: without it, Windows clones
with `core.autocrlf=true` (a common default) would convert bash
scripts to CRLF on checkout and break heredocs / EOL behavior.
`.cmd` files keep the default (CRLF on Windows is the native batch
convention).

If you're adding a new file type that needs strict LF preservation,
add a `*.ext text eol=lf` line to `.gitattributes`.

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

1. Create BOTH `engines/<slug>.sh` AND `engines/<slug>.ps1`. The
   stub-gate in `setup.sh` checks the `.sh` file and the stub-gate
   in `setup.ps1` checks the `.ps1` file - each port checks the
   launcher it will exec. If you only create one, the other
   platform's gate falls back to "coming soon" / Claude Code.
2. Same `not yet supported` first-5-lines stub convention applies
   if the engine isn't ready yet (e.g. `engines/openclaw.{sh,ps1}`).
3. Add to `ENGINE_TYPES` / `ENGINE_SLUGS` in both setup scripts.
4. The bash launcher receives three positional args:
   `INSTANCE_DIR SETUP_MODE DOCTOR_TYPE`. See `engines/claude-code.sh`.
5. The PS launcher mirrors with `-InstanceDir -SetupMode -DoctorType`
   named parameters. See `engines/claude-code.ps1`.

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
