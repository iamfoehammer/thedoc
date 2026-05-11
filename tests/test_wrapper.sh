#!/usr/bin/env bash
# Non-PTY tests for the `thedoc` wrapper subcommands.
# Complements tests/smoke_test.py (which is PTY-based and only covers
# setup.sh end to end). The wrapper's help / list / unknown-command
# paths are quick and deterministic enough to test with subprocess
# captures.
#
# Run:
#   bash tests/test_wrapper.sh
#
# Exit 0 = all PASS, exit 1 = any FAIL.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEDOC="$REPO_ROOT/thedoc"

GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

failures=0

_assert_contains() {
    local label="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo -e "  ${GREEN}PASS${RESET}: $label"
    else
        echo -e "  ${RED}FAIL${RESET}: $label"
        echo "        Expected to contain: $needle"
        echo "        Output was:"
        echo "$haystack" | sed 's/^/          /'
        failures=$((failures + 1))
    fi
}

_assert_exit_code() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo -e "  ${GREEN}PASS${RESET}: $label"
    else
        echo -e "  ${RED}FAIL${RESET}: $label"
        echo "        Expected exit $expected, got $actual"
        failures=$((failures + 1))
    fi
}

echo "============================================================"
echo "  thedoc wrapper tests"
echo "============================================================"

# 1. `thedoc help` shows the commands list
out=$("$THEDOC" help 2>&1) && rc=$? || rc=$?
_assert_exit_code   "thedoc help: exit 0"     0 "$rc"
_assert_contains    "thedoc help: shows 'Commands:'"  "Commands:"     "$out"
_assert_contains    "thedoc help: lists 'thedoc setup'" "thedoc setup" "$out"
_assert_contains    "thedoc help: lists 'thedoc test'"  "thedoc test"  "$out"
_assert_contains    "thedoc help: lists 'thedoc update'" "thedoc update" "$out"

# 1b. `thedoc version` shows framework dir + git info
out=$("$THEDOC" version 2>&1) && rc=$? || rc=$?
_assert_exit_code   "thedoc version: exit 0"        0 "$rc"
_assert_contains    "thedoc version: shows dir"     "Framework dir" "$out"
_assert_contains    "thedoc version: shows commit"  "Commit:"       "$out"

# 1c. `--version` and `-V` are aliases for version
out=$("$THEDOC" --version 2>&1)
_assert_contains    "thedoc --version: same as version" "Framework dir" "$out"
out=$("$THEDOC" -V 2>&1)
_assert_contains    "thedoc -V: same as version"        "Framework dir" "$out"

# 2. `thedoc --help` and `thedoc -h` are aliases for help
out=$("$THEDOC" --help 2>&1)
_assert_contains    "thedoc --help: same as help"  "Commands:"  "$out"
out=$("$THEDOC" -h 2>&1)
_assert_contains    "thedoc -h: same as help"      "Commands:"  "$out"

# 3. Unknown command exits non-zero
set +e
"$THEDOC" totally-bogus-command >/dev/null 2>&1
rc=$?
set -e
_assert_exit_code   "thedoc bogus-command: exit non-zero"  1  "$rc"

# 4. `thedoc list` exits 0 regardless of whether instances exist
"$THEDOC" list >/dev/null 2>&1
rc=$?
_assert_exit_code   "thedoc list: exit 0" 0 "$rc"

# 4b. `thedoc list` finds an instance via state file. Writes a fake state
# file pointing at a synthetic projects dir with one valid instance, then
# asserts the instance name appears in the output. Catches regressions in
# state-file parsing or path resolution.
# Creates THREE instances with deliberately non-alphabetical mkdir order
# so the alphabetical-sort assertion catches list-order regressions.
_list_state="$(mktemp -d)"
_list_proj="$(mktemp -d)"
for name in zebra-doctor alpha-doctor mango-doctor; do
    mkdir -p "$_list_proj/$name"
    echo "# Pretend Doctor: $name" > "$_list_proj/$name/DOCTOR.md"
    printf -- '- **Doctor type:** Pretend\n- **Created:** 2026-05-10T00:00:00Z\n' > "$_list_proj/$name/CLAUDE.md"
done
mkdir -p "$_list_state/thedoc"
printf 'first_run=2026-05-10T00:00:00Z\nprojects_dir=%s\nplatform=linux\n' "$_list_proj" > "$_list_state/thedoc/state"
out=$(XDG_STATE_HOME="$_list_state" "$THEDOC" list 2>&1)
_assert_contains    "thedoc list: shows alpha-doctor"  "alpha-doctor"  "$out"
_assert_contains    "thedoc list: shows mango-doctor"  "mango-doctor"  "$out"
_assert_contains    "thedoc list: shows zebra-doctor"  "zebra-doctor"  "$out"
_assert_contains    "thedoc list: shows doctor type from CLAUDE.md" "Pretend" "$out"
# Verify alphabetical order: alpha-doctor must precede zebra-doctor in
# the output. grep -n returns line numbers; lower must come first.
_alpha_line=$(echo "$out" | grep -n 'alpha-doctor' | head -1 | cut -d: -f1)
_zebra_line=$(echo "$out" | grep -n 'zebra-doctor' | head -1 | cut -d: -f1)
if [ -n "$_alpha_line" ] && [ -n "$_zebra_line" ] && [ "$_alpha_line" -lt "$_zebra_line" ]; then
    echo -e "  ${GREEN}PASS${RESET}: thedoc list: instances are alphabetical"
else
    echo -e "  ${RED}FAIL${RESET}: thedoc list: alpha-doctor (line $_alpha_line) should precede zebra-doctor (line $_zebra_line)"
    failures=$((failures + 1))
fi
rm -rf "$_list_state" "$_list_proj"

# 4d. `thedoc list` handles CRLF-format state files. PS Save-State on
# Windows can write CRLF line endings; bash `sed -n s/^projects_dir=//p`
# captures the trailing \r in the value, breaking [ -d ] - state's
# projects_dir would silently look invalid even when valid. Iter 108
# added the %$'\r' strip; this test pins it.
_crlf_state="$(mktemp -d)"
_crlf_proj="$(mktemp -d)"
mkdir -p "$_crlf_proj/crlf-test-instance"
echo '# Pretend Doctor' > "$_crlf_proj/crlf-test-instance/DOCTOR.md"
printf -- '- **Doctor type:** CrlfTest\r\n- **Created:** 2026-05-11T00:00:00Z\r\n' > "$_crlf_proj/crlf-test-instance/CLAUDE.md"
mkdir -p "$_crlf_state/thedoc"
# Deliberately CRLF line endings:
printf 'first_run=2026-05-11T00:00:00Z\r\nprojects_dir=%s\r\nplatform=windows\r\n' "$_crlf_proj" > "$_crlf_state/thedoc/state"
out=$(XDG_STATE_HOME="$_crlf_state" "$THEDOC" list 2>&1)
_assert_contains    "thedoc list (CRLF state): finds instance" "crlf-test-instance" "$out"
# Negative: stale-state warning must NOT appear (would mean we mis-read the path)
if echo "$out" | grep -qF "state's projects_dir is missing"; then
    echo -e "  ${RED}FAIL${RESET}: thedoc list (CRLF state): false-positive stale warning (CR not stripped)"
    failures=$((failures + 1))
else
    echo -e "  ${GREEN}PASS${RESET}: thedoc list (CRLF state): no false stale warning"
fi
rm -rf "$_crlf_state" "$_crlf_proj"

# 4c. `thedoc list` warns when state's projects_dir is gone. Pre-iter-102
# the fallback to dirname-of-script was silent, so the user got
# "(none found)" with no clue why.
_stale_state="$(mktemp -d)"
mkdir -p "$_stale_state/thedoc"
printf 'projects_dir=/nonexistent/never/existed-%s\n' "$$" > "$_stale_state/thedoc/state"
out=$(XDG_STATE_HOME="$_stale_state" "$THEDOC" list 2>&1)
_assert_contains    "thedoc list (stale state): warns about missing projects_dir" "state's projects_dir is missing" "$out"
rm -rf "$_stale_state"

# 5. `thedoc open` with no arg fails with usage hint
set +e
out=$("$THEDOC" open 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc open (no arg): exit non-zero" 1 "$rc"
_assert_contains    "thedoc open (no arg): suggests usage" "Usage" "$out"

# 6. `thedoc open NONEXISTENT` fails with friendly error
set +e
out=$("$THEDOC" open this-instance-does-not-exist-anywhere-zzz 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc open <missing>: exit non-zero" 1 "$rc"
_assert_contains    "thedoc open <missing>: tells user it's missing" "Not a doctor instance" "$out"

# 6c. `thedoc open <missing>` with stale state also tells the user the
# state is stale (so they realize their instance might still exist at
# the old projects_dir location).
_stale_open_state="$(mktemp -d)"
mkdir -p "$_stale_open_state/thedoc"
printf 'projects_dir=/nonexistent/never/existed-open-%s\n' "$$" > "$_stale_open_state/thedoc/state"
set +e
out=$(XDG_STATE_HOME="$_stale_open_state" "$THEDOC" open whatever 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc open <missing> (stale state): exit non-zero" 1 "$rc"
_assert_contains    "thedoc open <missing> (stale state): mentions stale state" "state's projects_dir is missing" "$out"
rm -rf "$_stale_open_state"

# 6b. `thedoc open <valid>` when 'claude' is missing from PATH bails with
# a friendly install hint rather than the cryptic 'bash: exec: claude:
# not found' that the bare exec would produce. Pre-iter-99 the exec
# error would surface; now we check command availability first.
_noclaude_state="$(mktemp -d)"
_noclaude_proj="$(mktemp -d)"
mkdir -p "$_noclaude_proj/check-instance"
echo '# Pretend Doctor' > "$_noclaude_proj/check-instance/DOCTOR.md"
mkdir -p "$_noclaude_state/thedoc"
printf 'projects_dir=%s\n' "$_noclaude_proj" > "$_noclaude_state/thedoc/state"
set +e
# Sanitize PATH so 'claude' isn't found. Keep /usr/bin + /bin so the
# script can still use sed/awk/printf/etc.
out=$(PATH=/usr/bin:/bin XDG_STATE_HOME="$_noclaude_state" "$THEDOC" open check-instance 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc open (no claude): exit non-zero" 1 "$rc"
_assert_contains    "thedoc open (no claude): tells user to install" "npm install -g @anthropic-ai/claude-code" "$out"
rm -rf "$_noclaude_state" "$_noclaude_proj"

# 7. `thedoc update` from a non-git directory bails with a friendly message
# (no `git pull` attempted). Copy the wrapper to a scratch dir so SCRIPT_DIR
# resolves there and skips the .git probe with the framed error.
_scratch="$(mktemp -d)"
trap 'rm -rf "$_scratch" "$_scratch_dirty"' EXIT
cp "$THEDOC" "$_scratch/thedoc"
set +e
out=$("$_scratch/thedoc" update 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc update (non-git dir): exit non-zero" 1 "$rc"
_assert_contains    "thedoc update (non-git dir): explains why"  "not a git checkout" "$out"

# 8. `thedoc update` with a dirty working tree bails BEFORE attempting
# git pull. Scaffolds a git repo with one commit, then modifies a tracked
# file, then runs update. Guards iter 58's friendly-preflight branch.
_scratch_dirty="$(mktemp -d)"
(
    cd "$_scratch_dirty"
    git init -q
    git -c user.email=t@t -c user.name=T config user.email t@t
    git -c user.email=t@t -c user.name=T config user.name T
    echo "original" > tracked-file
    git add tracked-file
    git -c user.email=t@t -c user.name=T commit -qm init
    echo "modified" >> tracked-file
)
cp "$THEDOC" "$_scratch_dirty/thedoc"
set +e
out=$("$_scratch_dirty/thedoc" update 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc update (dirty tree): exit non-zero" 1 "$rc"
_assert_contains    "thedoc update (dirty tree): explains why"  "Local changes detected" "$out"

# 9. `thedoc test` from a scratch dir without tests/ bails before running
# anything. Same idiom as the non-git update test: copy only the wrapper,
# leave the dir empty otherwise.
set +e
out=$("$_scratch/thedoc" test 2>&1)
rc=$?
set -e
_assert_exit_code   "thedoc test (no tests/ dir): exit non-zero" 1 "$rc"
_assert_contains    "thedoc test (no tests/ dir): explains why"  "Tests not found" "$out"

echo ""

# 11. tests/README.md scenario table stays in sync with smoke_test.py.
# Catches the kind of doc drift where someone adds a scenario but
# forgets to row it in the README - found iter 111 (typed-path-decline
# was missing).
_readme_count=$(grep -cE '^\| `[a-z-]+` \|' "$REPO_ROOT/tests/README.md")
_code_count=$(python3 "$REPO_ROOT/tests/smoke_test.py" --list 2>/dev/null | wc -l | tr -d ' ')
if [ "$_readme_count" -eq "$_code_count" ]; then
    echo -e "  ${GREEN}PASS${RESET}: tests/README.md scenario table matches smoke_test.py ($_code_count rows)"
else
    echo -e "  ${RED}FAIL${RESET}: tests/README.md has $_readme_count scenario rows, smoke_test.py has $_code_count"
    echo "        Diff between sets:"
    diff <(python3 "$REPO_ROOT/tests/smoke_test.py" --list | sort) \
         <(grep -E '^\| `[a-z-]+`' "$REPO_ROOT/tests/README.md" | awk -F'`' '{print $2}' | sort) | sed 's/^/          /'
    failures=$((failures + 1))
fi

echo ""
echo "============================================================"
if [ "$failures" -eq 0 ]; then
    echo -e "  overall: ${GREEN}PASS${RESET}"
    exit 0
else
    echo -e "  overall: ${RED}${failures} FAILED${RESET}"
    exit 1
fi
