# Engine: Claude Code (PowerShell)
# Native counterpart to engines/claude-code.sh. Launches a Claude Code
# session in the doctor instance directory. Normally invoked by
# setup.ps1, not directly.
[CmdletBinding()]
param(
    [string]$InstanceDir,
    [string]$SetupMode  = 'quick',
    [string]$DoctorType = 'claude-code'
)

$ErrorActionPreference = 'Stop'

# Match the bash side's `[ "$#" -lt 1 ]` usage check rather than
# [Parameter(Mandatory)]. Mandatory would prompt interactively on a
# stdin-attached console (annoying) and hang/throw in non-interactive
# contexts (CI, piped stdin). Explicit usage-and-exit is predictable
# either way and mirrors engines/claude-code.sh exactly.
if ([string]::IsNullOrWhiteSpace($InstanceDir)) {
    $scriptName = Split-Path -Leaf $PSCommandPath
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine("  Usage: $scriptName <INSTANCE_DIR> [SETUP_MODE] [DOCTOR_TYPE]")
    [Console]::Error.WriteLine('  This launcher is normally invoked by setup.ps1, not directly.')
    [Console]::Error.WriteLine('')
    exit 2
}

if (-not (Test-Path -LiteralPath $InstanceDir -PathType Container)) {
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine("  Instance directory does not exist: $InstanceDir")
    [Console]::Error.WriteLine('')
    exit 2
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host ''
    Write-Host '  Claude Code is not installed or not in PATH.'
    Write-Host '  Install it: npm install -g @anthropic-ai/claude-code'
    Write-Host ''
    exit 1
}

if ($SetupMode -eq 'full') {
    $launchPrompt = 'Start by reading DOCTOR.md in this directory - it has your personality, instructions, and the full audit checklist. Then read CLAUDE.md to get the framework path and system info. Follow the Full Audit Checklist in DOCTOR.md step by step. Present each recommendation and let me accept or reject it.'
}
else {
    $launchPrompt = 'Start by reading DOCTOR.md in this directory - it has your personality, instructions, and setup checklist. Then read CLAUDE.md to get the framework path and system info. Follow the Quick Setup instructions in DOCTOR.md - scan everything and show me a summary, then ask what I want to configure first.'
}

# Load ~/.secrets.ps1 before invoking claude. When thedoc.cmd runs
# `pwsh -NoProfile`, iter 69's profile-wired secret sourcing is
# skipped - claude would then miss API keys etc. that the user set
# via llm-secrets.ps1. Source explicitly so we work regardless of
# how setup.ps1 got invoked. Mirrors thedoc.ps1's open subcommand.
$secretsFile = Join-Path $HOME '.secrets.ps1'
if (Test-Path -LiteralPath $secretsFile -PathType Leaf) {
    # Wrap in try/catch so a syntax error in the secrets file (manual
    # edit, accidental keystroke, partial write from an earlier crash)
    # degrades to a warning + launching claude WITHOUT env vars, rather
    # than throwing under $ErrorActionPreference='Stop' and dumping a
    # stack trace. The user sees a clear message and can fix the file.
    try {
        . $secretsFile
    } catch {
        Write-Host ''
        Write-Host '  Warning: ~/.secrets.ps1 has syntax errors and could not be loaded:' -ForegroundColor Yellow
        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host '  Launching claude without env vars from llm-secrets.' -ForegroundColor DarkGray
        Write-Host '  Edit ~/.secrets.ps1 to fix, or remove broken lines.' -ForegroundColor DarkGray
        Write-Host ''
    }
}

Set-Location -LiteralPath $InstanceDir
& claude $launchPrompt
# Propagate claude's exit code. Bash engines/claude-code.sh ends with
# `exec claude "$PROMPT"`, where exec replaces the bash process so the
# child's exit code IS the script's exit code automatically. PS's `&`
# does not propagate (iter 162 - PS gotcha #5), so without this an
# `claude` crash would surface as engine exit 0 upstream and setup.ps1
# / thedoc.ps1 / CI would think the launch succeeded.
exit $LASTEXITCODE
