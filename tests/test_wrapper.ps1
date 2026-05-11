# Non-interactive tests for the thedoc.ps1 wrapper subcommands.
# Mirrors tests/test_wrapper.sh on the PowerShell side. The smoke
# driver (tests/smoke_test.py) is POSIX-only (pty.fork), so the PS
# port has no E2E equivalent - these subcommand tests are the
# Windows-side coverage for everything below setup.ps1 itself.
#
# Run:
#   pwsh -NoProfile -File tests/test_wrapper.ps1
#
# Exit 0 = all PASS, exit 1 = any FAIL.

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TheDoc   = Join-Path $RepoRoot 'thedoc.ps1'

$failures = 0

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Needle,
        [Parameter(Mandatory)][string]$Haystack
    )
    if ($Haystack -like "*$Needle*") {
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        Expected to contain: $Needle"
        Write-Host "        Output was:"
        $Haystack -split "`n" | ForEach-Object { Write-Host "          $_" }
        $script:failures++
    }
}

function Assert-ExitCode {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$Expected,
        [Parameter(Mandatory)][int]$Actual
    )
    if ($Actual -eq $Expected) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        Expected exit $Expected, got $Actual"
        $script:failures++
    }
}

# Invoke thedoc.ps1 in-process. Using `& $TheDoc <args>` keeps the
# pwsh process the same, so subcommands that read $env: / $HOME / etc.
# see this process's environment. Stderr is merged via 2>&1.
function Invoke-TheDoc {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Args)
    $output = & $TheDoc @Args 2>&1 | Out-String
    return @{ Output = $output; ExitCode = $LASTEXITCODE }
}

Write-Host "============================================================"
Write-Host "  thedoc.ps1 wrapper tests"
Write-Host "============================================================"

# 1. `thedoc help` shows the commands list.
$r = Invoke-TheDoc help
Assert-ExitCode  'thedoc help: exit 0'                0 $r.ExitCode
Assert-Contains  "thedoc help: shows 'Commands:'"     'Commands:'     $r.Output
Assert-Contains  "thedoc help: lists 'thedoc setup'"  'thedoc setup'  $r.Output
Assert-Contains  "thedoc help: lists 'thedoc test'"   'thedoc test'   $r.Output
Assert-Contains  "thedoc help: lists 'thedoc update'" 'thedoc update' $r.Output

# 2. `--help` and `-h` are aliases for help.
$r = Invoke-TheDoc --help
Assert-Contains  'thedoc --help: same as help'  'Commands:'  $r.Output
$r = Invoke-TheDoc -h
Assert-Contains  'thedoc -h: same as help'      'Commands:'  $r.Output

# 3. Unknown command exits non-zero.
$r = Invoke-TheDoc totally-bogus-command
Assert-ExitCode  'thedoc bogus-command: exit non-zero' 1 $r.ExitCode

# 4. `thedoc list` exits 0 regardless of whether instances exist.
$r = Invoke-TheDoc list
Assert-ExitCode  'thedoc list: exit 0' 0 $r.ExitCode

# 5. `thedoc open` with no arg fails with usage hint.
$r = Invoke-TheDoc open
Assert-ExitCode  'thedoc open (no arg): exit non-zero' 1 $r.ExitCode
Assert-Contains  'thedoc open (no arg): suggests usage' 'Usage' $r.Output

# 6. `thedoc open NONEXISTENT` fails with friendly error.
$r = Invoke-TheDoc open this-instance-does-not-exist-anywhere-zzz
Assert-ExitCode  'thedoc open <missing>: exit non-zero' 1 $r.ExitCode
Assert-Contains  "thedoc open <missing>: tells user it's missing" 'Not a doctor instance' $r.Output

# 7. `thedoc update` from a non-git directory bails with a friendly message.
# Copy the wrapper to a scratch dir so $ScriptDir resolves there and skips
# the .git probe with the framed error. Mirrors the bash test exactly.
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-wrapper-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    Copy-Item -LiteralPath $TheDoc -Destination (Join-Path $scratch 'thedoc.ps1')
    $scratchTheDoc = Join-Path $scratch 'thedoc.ps1'
    $output = & $scratchTheDoc update 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Assert-ExitCode  'thedoc update (non-git dir): exit non-zero' 1 $rc
    Assert-Contains  'thedoc update (non-git dir): explains why'  'not a git checkout' $output
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '============================================================'
if ($failures -eq 0) {
    Write-Host '  overall: PASS' -ForegroundColor Green
    exit 0
} else {
    Write-Host "  overall: $failures FAILED" -ForegroundColor Red
    exit 1
}
