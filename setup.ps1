# thedoc setup wizard (PowerShell)
# Native Windows PowerShell 7+ counterpart to setup.sh.
#
# STATUS: scaffolding. Most flow steps are stubs marked TODO. The bash
# setup.sh is the source of truth for behavior; mirror it module by module.
# See README.md and setup.sh for the canonical UX.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Preflight ────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  thedoc setup.ps1 needs PowerShell 7+. You're on $($PSVersionTable.PSVersion)."
    Write-Host "  Install PowerShell 7: https://github.com/PowerShell/PowerShell/releases"
    Write-Host ""
    exit 1
}

foreach ($cmd in @('git')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  thedoc needs '$cmd' but it isn't on your PATH."
        Write-Host ""
        exit 1
    }
}

# Clean exit on Ctrl+C. PowerShell normally throws a PipelineStoppedException;
# the trap below replaces it with a friendly message.
trap [System.Management.Automation.PipelineStoppedException] {
    Write-Host ""
    Write-Host ""
    Write-Host "  Aborted. No instance was created."
    Write-Host ""
    exit 130
}

# ── Constants ────────────────────────────────────────────────────────
$Titles = @(
    'Emergency LLM Hologram',
    'Emergency CLI Hologram',
    'Emergency AI Medical Hologram',
    'Emergency AI Med Hologram',
    'Emergency Harness Hologram',
    'Emergency Agent Hologram',
    'Emergency Config Hologram',
    'Medical AI'
)
$Greetings = @(
    'Please state the nature of the LLM emergency.',
    'Please state the nature of the CLI emergency.',
    'Please state the nature of the AI emergency.',
    'Please state the nature of the medical emergency.',
    'Please state the nature of the harness emergency.',
    'Please state the nature of the agent emergency.',
    'Please state the nature of the configuration emergency.',
    'Please state the nature of the emergency.'
)
$Quips = @(
    'Back so soon? What did you break this time?',
    'Ah, a returning patient. Let me pull up your chart.',
    "I'm a doctor, not a debugger. Well, actually, I'm both.",
    'House call or emergency? Either way, I''m here.',
    "No need to describe your symptoms - I'll run a diagnostic.",
    'The doctor is in.',
    'Another day, another config file in critical condition.',
    'I see you''ve returned. The prognosis must be serious.'
)

# ── State file ───────────────────────────────────────────────────────
$StateDir  = Join-Path $env:LOCALAPPDATA 'thedoc'
$StateFile = Join-Path $StateDir 'state.json'

function Test-FirstRun { -not (Test-Path $StateFile) }

function Save-State {
    param([string]$ProjectsDir, [string]$Platform)
    if (-not (Test-Path $StateDir)) { New-Item -Type Directory -Path $StateDir | Out-Null }
    @{
        first_run    = (Get-Date).ToString('o')
        projects_dir = $ProjectsDir
        platform     = $Platform
    } | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

function Get-State {
    if (Test-Path $StateFile) {
        return Get-Content $StateFile -Raw | ConvertFrom-Json
    }
    return $null
}

# ── Typing effect ────────────────────────────────────────────────────
$Script:SkipTyping = $false

function Write-Typed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [double]$Delay = 0.008,
        [string]$Prefix = '  '
    )
    # TODO: port the awk-based word-wrap from setup.sh. For now, write whole.
    if ($Script:SkipTyping) {
        Write-Host "$Prefix$Text"
        return
    }
    Write-Host -NoNewline $Prefix
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host -NoNewline $ch
        # TODO: per-char non-blocking poll for [space] to flip $Script:SkipTyping
        Start-Sleep -Milliseconds ([int]($Delay * 1000))
    }
    Write-Host ''
}

# ── Greeting ─────────────────────────────────────────────────────────
function Show-Greeting {
    $idx      = Get-Random -Minimum 0 -Maximum $Titles.Count
    $title    = $Titles[$idx]
    $greeting = $Greetings[$idx]

    Write-Host ''
    Write-Host "  +$([string]::new('=', $title.Length + 4))+"
    Write-Host "  |  $title  |"
    Write-Host "  +$([string]::new('=', $title.Length + 4))+"
    Write-Host ''

    if (Test-FirstRun) {
        Write-Typed $greeting -Delay 0.02
        Write-Host ''
        Start-Sleep -Milliseconds 500
        Write-Typed '...' -Delay 0.3
        Write-Host ''

        # Voyager check
        Write-Host ''
        Write-Host '  Have you ever seen Star Trek: Voyager? [y/n]'
        $key = [System.Console]::ReadKey($true)
        Write-Host ''

        if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
            $artPath = Join-Path $ScriptDir 'thedoc.txt'
            if (Test-Path $artPath) {
                Write-Host ''
                Get-Content $artPath
                Write-Host ''
                Write-Host '  The Emergency Medical Hologram, reporting for duty.'
                Write-Host ''
                Write-Host '  Press any key to continue...'
                [System.Console]::ReadKey($true) | Out-Null
                Write-Host ''
            }
        }

        Write-Typed "No emergency? Just a checkup? That's fine too."
        Write-Typed "Contrary to my name, I handle everything from routine"
        Write-Typed "configuration to catastrophic meltdowns."
        Write-Host ''
        Write-Typed "I'm going to need to scan your system first."
        Write-Typed "Think of it as a routine physical."
        Write-Host ''
    }
    else {
        $quip = $Quips | Get-Random
        Write-Typed $quip
        Write-Host ''
    }
}

# ── Stubs for the remaining flow (TODO) ──────────────────────────────
function Invoke-TricorderScan { throw 'TODO: port tricorder_scan from setup.sh' }
function Get-ProjectsDir       { throw 'TODO: port detect_projects_dirs / prompt_projects_dir' }
function Show-Menu             { throw 'TODO: port prompt_choice with arrow-key navigation' }
function Show-StructureExplainer { throw 'TODO: port print_structure_explainer' }
function New-DoctorInstance    { throw 'TODO: port the instance creation block' }

# ── Main ─────────────────────────────────────────────────────────────
Show-Greeting

# TODO: rest of the flow
# Invoke-TricorderScan
# $ProjectsDir = Get-ProjectsDir
# $DoctorType  = Show-Menu 'What is this doctor for?' @('Claude Code','OpenClaw','Gemini CLI')
# $Engine      = Show-Menu 'Which LLM engine?' @('Claude Code')
# $SetupMode   = Show-Menu 'Setup mode?' @('Quick','Full')
# New-DoctorInstance ...

Write-Host ''
Write-Host '  setup.ps1 is currently a scaffold; the full flow lives in setup.sh.'
Write-Host '  For now, run the bash setup.sh under WSL2 or Git Bash on Windows.'
Write-Host ''
