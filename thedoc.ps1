# thedoc.ps1 - Entry point for the Emergency Medical Hologram framework
#               (native PowerShell 7+ counterpart of the `thedoc` bash wrapper)
#
# Usage:
#   thedoc                Run setup (create or open a doctor instance)
#   thedoc setup          Same as above
#   thedoc list           List existing doctor instances
#   thedoc open <name>    Open an existing instance directly
#   thedoc test           Run wrapper + smoke tests (mirrors CI)
#   thedoc update         git pull the framework to latest
#   thedoc help           Show this help

[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'setup',
    [Parameter(Position=1)][string]$Arg1
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Locate the projects directory (where doctor instances live). Prefer the
# state file the wizard wrote - that's what the user chose. Fall back to
# the parent of the framework dir, which works when bootstrap put thedoc
# inside <ProjectsDir>/thedoc/.
# Path precedence matches setup.ps1's Save-State exactly: XDG_STATE_HOME
# wins (POSIX convention, honored if set), then LOCALAPPDATA (Windows
# default), then $HOME/.local/state (POSIX default).
$stateFile = if ($env:XDG_STATE_HOME) {
    Join-Path $env:XDG_STATE_HOME 'thedoc/state'
} elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA 'thedoc/state'
} else {
    Join-Path $HOME '.local/state/thedoc/state'
}
$GithubDir = $null
if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
    $line = (Select-String -LiteralPath $stateFile -Pattern '^projects_dir=' -SimpleMatch:$false |
             Select-Object -First 1).Line
    if ($line) { $GithubDir = $line -replace '^projects_dir=', '' }
}
if (-not $GithubDir -or -not (Test-Path -LiteralPath $GithubDir -PathType Container)) {
    $GithubDir = Split-Path -Parent $ScriptDir
}

function Invoke-Help {
    Write-Host ""
    Write-Host "  thedoc - Emergency Medical Hologram framework"
    Write-Host ""
    Write-Host "  Commands:"
    Write-Host "    thedoc setup    Create or open a doctor instance (default)"
    Write-Host "    thedoc list     List existing doctor instances"
    Write-Host "    thedoc open     Open an existing instance: thedoc open <name>"
    Write-Host "    thedoc test     Parse-check setup.ps1 (PowerShell-side coverage)"
    Write-Host "    thedoc update   git pull the framework to latest"
    Write-Host "    thedoc help     Show this help"
    Write-Host ""
}

switch ($Command) {
    { $_ -in 'setup', '' } {
        & (Join-Path $ScriptDir 'setup.ps1')
        exit $LASTEXITCODE
    }

    'test' {
        # The PTY-based smoke test driver uses pty.fork() which is
        # POSIX-only - there's no equivalent Windows-native test driver
        # yet (see CI's parse-powershell job, which is the closest thing).
        # Parse-check every .ps1 + run the wrapper test suite. Mirrors
        # what CI's Windows job runs.
        Write-Host ""
        Write-Host "  Parse-checking .ps1 files..."
        $errors = 0
        Get-ChildItem -LiteralPath $ScriptDir -Recurse -File -Filter '*.ps1' | ForEach-Object {
            $tokens = $null; $perr = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName, [ref]$tokens, [ref]$perr) | Out-Null
            if ($perr.Count -gt 0) {
                Write-Host "    FAIL: $($_.FullName)" -ForegroundColor Red
                $perr | ForEach-Object { Write-Host "      $_" }
                $errors++
            } else {
                Write-Host "    OK:   $($_.Name)" -ForegroundColor Green
            }
        }
        if ($errors -gt 0) {
            Write-Host ""
            Write-Host "  $errors file(s) failed to parse." -ForegroundColor Red
            exit 1
        }
        Write-Host ""

        # Wrapper tests for thedoc.ps1 itself (mirrors test_wrapper.sh).
        $wrapperTests = Join-Path $ScriptDir 'tests/test_wrapper.ps1'
        if (Test-Path -LiteralPath $wrapperTests -PathType Leaf) {
            & $wrapperTests
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        } else {
            Write-Host "  (tests/test_wrapper.ps1 not found - skipping)" -ForegroundColor DarkGray
        }
        Write-Host "  (The PTY-based smoke suite is POSIX-only; run it under WSL/macOS)" -ForegroundColor DarkGray
        Write-Host ""
    }

    'update' {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host ""
            Write-Host "  thedoc update requires git."
            Write-Host ""
            exit 1
        }
        if (-not (Test-Path -LiteralPath (Join-Path $ScriptDir '.git') -PathType Container)) {
            Write-Host ""
            Write-Host "  $ScriptDir is not a git checkout - can't pull."
            Write-Host "  If you installed via the bootstrap one-liner, this is a bug."
            Write-Host ""
            exit 1
        }
        # Dirty working tree blocks ff-only.
        git -C $ScriptDir diff --quiet HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Local changes detected in $ScriptDir."
            Write-Host "  Commit, stash, or revert them before running 'thedoc update'."
            Write-Host ""
            Write-Host "  Files changed:"
            git -C $ScriptDir status --short
            Write-Host ""
            exit 1
        }
        git -C $ScriptDir rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Current branch has no upstream tracking."
            Write-Host "  Set one up with:"
            Write-Host "      git -C $ScriptDir branch --set-upstream-to=origin/main"
            Write-Host ""
            exit 1
        }
        Write-Host ""
        Write-Host "  Updating thedoc..."
        git -C $ScriptDir pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Pull failed. Your local history may have diverged from origin."
            Write-Host "  Inspect with 'git -C $ScriptDir log --oneline @{u}..HEAD'."
            Write-Host ""
            exit 1
        }
        Write-Host ""
    }

    'list' {
        Write-Host ""
        Write-Host "  Doctor instances in $GithubDir/:"
        Write-Host ""
        $found = $false
        # Sort by name for deterministic, alphabetical output - matches
        # bash thedoc's `for dir in "$GITHUB_DIR"/*/` which globs in
        # alphabetical order. Without Sort-Object, Get-ChildItem returns
        # filesystem order (close to alphabetical on Windows but not
        # guaranteed); a user with multiple instances could see a
        # different ordering than the bash wrapper.
        Get-ChildItem -LiteralPath $GithubDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name | ForEach-Object {
            $doctorMd = Join-Path $_.FullName 'DOCTOR.md'
            if (-not (Test-Path -LiteralPath $doctorMd -PathType Leaf)) { return }

            $doctorType = 'unknown'
            $created    = ''
            $claudeMd   = Join-Path $_.FullName 'CLAUDE.md'
            if (Test-Path -LiteralPath $claudeMd -PathType Leaf) {
                $content = Get-Content -LiteralPath $claudeMd -ErrorAction SilentlyContinue
                $typeLine = $content | Where-Object { $_ -match '^- \*\*Doctor type:\*\* (.*)$' } | Select-Object -First 1
                if ($typeLine -match '^- \*\*Doctor type:\*\* (.*)$') { $doctorType = $Matches[1] }
                $createdLine = $content | Where-Object { $_ -match '^- \*\*Created:\*\* (.*)$' } | Select-Object -First 1
                if ($createdLine -match '^- \*\*Created:\*\* (.*?)(T.*)?$') { $created = $Matches[1] }
            }
            if ($created) {
                Write-Host "    $($_.Name)  ($doctorType, $created)"
            } else {
                Write-Host "    $($_.Name)  ($doctorType)"
            }
            $found = $true
        }
        if (-not $found) {
            Write-Host "    (none found - run 'thedoc setup' to create one)"
        }
        Write-Host ""
    }

    'open' {
        if (-not $Arg1) {
            Write-Host "Usage: thedoc open <instance-name>"
            Write-Host "Run 'thedoc list' to see available instances."
            exit 1
        }
        $instanceDir = Join-Path $GithubDir $Arg1
        $doctorMd = Join-Path $instanceDir 'DOCTOR.md'
        if (-not (Test-Path -LiteralPath $instanceDir -PathType Container) -or
            -not (Test-Path -LiteralPath $doctorMd -PathType Leaf)) {
            Write-Host "Not a doctor instance: $instanceDir"
            Write-Host "Run 'thedoc list' to see available instances."
            exit 1
        }
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            Write-Host ''
            Write-Host '  Claude Code is not installed or not in PATH.'
            Write-Host '  Install it: npm install -g @anthropic-ai/claude-code'
            Write-Host ''
            exit 1
        }
        Push-Location $instanceDir
        try {
            $prompt = 'Re-entering this doctor instance. Start by reading DOCTOR.md for your role and CLAUDE.md for the personal config of this instance. Then ask what I''d like to work on this session.'
            & claude $prompt
        } finally {
            Pop-Location
        }
    }

    { $_ -in 'help', '--help', '-h' } {
        Invoke-Help
    }

    default {
        Write-Host "Unknown command: $Command"
        Write-Host "Run 'thedoc help' for usage."
        exit 1
    }
}
