# Engine: Claude Code (PowerShell)
# Native counterpart to engines/claude-code.sh. Launches a Claude Code
# session in the doctor instance directory. Normally invoked by
# setup.ps1, not directly - the [Parameter(Mandatory)] on $InstanceDir
# triggers an interactive prompt if missing.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstanceDir,
    [string]$SetupMode  = 'quick',
    [string]$DoctorType = 'claude-code'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InstanceDir -PathType Container)) {
    Write-Host ''
    Write-Host "  Instance directory does not exist: $InstanceDir"
    Write-Host ''
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

Set-Location -LiteralPath $InstanceDir
& claude $launchPrompt
