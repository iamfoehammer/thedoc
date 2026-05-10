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

echo ""
echo "============================================================"
if [ "$failures" -eq 0 ]; then
    echo -e "  overall: ${GREEN}PASS${RESET}"
    exit 0
else
    echo -e "  overall: ${RED}${failures} FAILED${RESET}"
    exit 1
fi
