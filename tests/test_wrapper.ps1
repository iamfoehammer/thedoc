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

# 4b. `thedoc list` finds an instance via the state file. Mirrors the
# bash test - writes a fake state file pointing at a synthetic projects
# dir with multiple instances, asserts they appear in alphabetical
# order. Catches regressions in state-file path / format (iter 73 unified
# PS and bash here) AND list ordering (iter 95 added Sort-Object).
$listState = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-list-state-$([guid]::NewGuid())"
$listProj  = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-list-proj-$([guid]::NewGuid())"
foreach ($name in 'zebra-doctor', 'alpha-doctor', 'mango-doctor') {
    $inst = Join-Path $listProj $name
    New-Item -ItemType Directory -Path $inst -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inst 'DOCTOR.md') -Value "# Pretend Doctor: $name"
    Set-Content -LiteralPath (Join-Path $inst 'CLAUDE.md') -Value @(
        '- **Doctor type:** Pretend'
        '- **Created:** 2026-05-10T00:00:00Z'
    )
}
New-Item -ItemType Directory -Path (Join-Path $listState 'thedoc') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $listState 'thedoc/state') -Value @(
    'first_run=2026-05-10T00:00:00Z'
    "projects_dir=$listProj"
    'platform=windows'
)
try {
    $prevXdg = $env:XDG_STATE_HOME
    $env:XDG_STATE_HOME = $listState
    $r = Invoke-TheDoc list
    Assert-Contains  'thedoc list: shows alpha-doctor'  'alpha-doctor'  $r.Output
    Assert-Contains  'thedoc list: shows mango-doctor'  'mango-doctor'  $r.Output
    Assert-Contains  'thedoc list: shows zebra-doctor'  'zebra-doctor'  $r.Output
    Assert-Contains  'thedoc list: shows doctor type from CLAUDE.md' 'Pretend' $r.Output

    # alpha-doctor must precede zebra-doctor in the output (alphabetical).
    $alphaIdx = $r.Output.IndexOf('alpha-doctor')
    $zebraIdx = $r.Output.IndexOf('zebra-doctor')
    if ($alphaIdx -ge 0 -and $zebraIdx -gt $alphaIdx) {
        Write-Host '  PASS: thedoc list: instances are alphabetical' -ForegroundColor Green
    } else {
        Write-Host "  FAIL: thedoc list: alpha-doctor ($alphaIdx) should precede zebra-doctor ($zebraIdx)" -ForegroundColor Red
        $script:failures++
    }
} finally {
    $env:XDG_STATE_HOME = $prevXdg
    Remove-Item -LiteralPath $listState -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $listProj  -Recurse -Force -ErrorAction SilentlyContinue
}

$staleState = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-stale-state-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path (Join-Path $staleState 'thedoc') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $staleState 'thedoc/state') -Value "projects_dir=/nonexistent/never/existed-$PID"
try {
    $prevXdg = $env:XDG_STATE_HOME
    $env:XDG_STATE_HOME = $staleState
    $r = Invoke-TheDoc list
    Assert-Contains  'thedoc list (stale state): warns about missing projects_dir' "state's projects_dir is missing" $r.Output
} finally {
    $env:XDG_STATE_HOME = $prevXdg
    Remove-Item -LiteralPath $staleState -Recurse -Force -ErrorAction SilentlyContinue
}

# 5. `thedoc open` with no arg fails with usage hint.
$r = Invoke-TheDoc open
Assert-ExitCode  'thedoc open (no arg): exit non-zero' 1 $r.ExitCode
Assert-Contains  'thedoc open (no arg): suggests usage' 'Usage' $r.Output

# 6. `thedoc open NONEXISTENT` fails with friendly error.
$r = Invoke-TheDoc open this-instance-does-not-exist-anywhere-zzz
Assert-ExitCode  'thedoc open <missing>: exit non-zero' 1 $r.ExitCode
Assert-Contains  "thedoc open <missing>: tells user it's missing" 'Not a doctor instance' $r.Output

# 6b. `thedoc open <valid>` when 'claude' is missing from PATH bails
# with a friendly install hint. Pre-iter-99 the & invocation would
# surface a "term 'claude' is not recognized" error.
$noClaudeState = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-noclaude-state-$([guid]::NewGuid())"
$noClaudeProj  = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-noclaude-proj-$([guid]::NewGuid())"
$noClaudeInstance = Join-Path $noClaudeProj 'check-instance'
New-Item -ItemType Directory -Path $noClaudeInstance -Force | Out-Null
Set-Content -LiteralPath (Join-Path $noClaudeInstance 'DOCTOR.md') -Value '# Pretend Doctor'
New-Item -ItemType Directory -Path (Join-Path $noClaudeState 'thedoc') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $noClaudeState 'thedoc/state') -Value "projects_dir=$noClaudeProj"
try {
    $prevXdg  = $env:XDG_STATE_HOME
    $prevPath = $env:PATH
    $env:XDG_STATE_HOME = $noClaudeState
    # Strip any directory containing 'claude' from PATH (typical install
    # locations: ~/.npm-global/bin, /usr/local/bin). The remaining PATH
    # still lets pwsh find git, sed, etc.
    $env:PATH = ($env:PATH -split [System.IO.Path]::PathSeparator |
                 Where-Object { -not (Test-Path -LiteralPath (Join-Path $_ 'claude') -ErrorAction SilentlyContinue) -and
                                -not (Test-Path -LiteralPath (Join-Path $_ 'claude.exe') -ErrorAction SilentlyContinue) -and
                                -not (Test-Path -LiteralPath (Join-Path $_ 'claude.cmd') -ErrorAction SilentlyContinue) }) -join [System.IO.Path]::PathSeparator
    $r = Invoke-TheDoc open check-instance
    Assert-ExitCode  'thedoc open (no claude): exit non-zero' 1 $r.ExitCode
    Assert-Contains  'thedoc open (no claude): tells user to install' 'npm install -g @anthropic-ai/claude-code' $r.Output
} finally {
    $env:XDG_STATE_HOME = $prevXdg
    $env:PATH = $prevPath
    Remove-Item -LiteralPath $noClaudeState -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $noClaudeProj  -Recurse -Force -ErrorAction SilentlyContinue
}

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

# 8. `thedoc update` with a dirty working tree bails BEFORE attempting
# git pull. Scaffolds a git repo with one commit + a tracked-file edit,
# then runs update. Guards the iter 58 preflight branch on the PS side.
$scratchDirty = Join-Path ([System.IO.Path]::GetTempPath()) "thedoc-wrapper-dirty-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $scratchDirty -Force | Out-Null
try {
    Push-Location $scratchDirty
    git init -q
    git config user.email 't@t' | Out-Null
    git config user.name  'T'   | Out-Null
    Set-Content -LiteralPath 'tracked-file' -Value 'original'
    git add tracked-file
    git commit -qm init
    Add-Content -LiteralPath 'tracked-file' -Value 'modified'
    Pop-Location

    Copy-Item -LiteralPath $TheDoc -Destination (Join-Path $scratchDirty 'thedoc.ps1')
    $scratchTheDoc = Join-Path $scratchDirty 'thedoc.ps1'
    $output = & $scratchTheDoc update 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Assert-ExitCode  'thedoc update (dirty tree): exit non-zero' 1 $rc
    Assert-Contains  'thedoc update (dirty tree): explains why'  'Local changes detected' $output
} finally {
    Remove-Item -LiteralPath $scratchDirty -Recurse -Force -ErrorAction SilentlyContinue
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
