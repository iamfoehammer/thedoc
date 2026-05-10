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

function Get-Wrapped {
    # Greedy whitespace word-wrap, matching the awk pass in setup.sh.
    param([string]$Text, [int]$Width)
    $words = $Text -split ' '
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $line = ''
    foreach ($word in $words) {
        if ([string]::IsNullOrEmpty($word)) { continue }
        if ($line.Length -eq 0) {
            $line = $word
        }
        elseif ($line.Length + 1 + $word.Length -le $Width) {
            $line = "$line $word"
        }
        else {
            $lines.Add($line) | Out-Null
            $line = $word
        }
    }
    if ($line.Length -gt 0) { $lines.Add($line) | Out-Null }
    return $lines.ToArray()
}

function Write-Typed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [double]$Delay = 0.008,
        [string]$Prefix = '  '
    )
    # Width-aware word-wrap so the terminal never breaks a word mid-character.
    try { $cols = [Console]::WindowWidth } catch { $cols = 80 }
    $wrapAt = $cols - $Prefix.Length
    if ($wrapAt -lt 20) { $wrapAt = 20 }
    $lines = Get-Wrapped -Text $Text -Width $wrapAt

    # Skip mode: dump every wrapped line in a single Write-Host. No char loop.
    if ($Script:SkipTyping) {
        foreach ($line in $lines) {
            Write-Host "$Prefix$line"
        }
        return
    }

    # Animated path with async space-to-skip.
    $delayMs = [int]($Delay * 1000)
    foreach ($line in $lines) {
        if ($Script:SkipTyping) {
            # Skip flipped on mid-paragraph - dump the rest whole.
            Write-Host "$Prefix$line"
            continue
        }
        Write-Host -NoNewline $Prefix
        $chars = $line.ToCharArray()
        for ($i = 0; $i -lt $chars.Length; $i++) {
            Write-Host -NoNewline $chars[$i]
            # Non-blocking poll. KeyAvailable is the PS analogue of bash's
            # `read -t 0`, but unlike piped bash it actually consumes the
            # char only after we call ReadKey.
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq ' ') {
                    $Script:SkipTyping = $true
                    Write-Host -NoNewline ($line.Substring($i + 1))
                    break
                }
                # Non-space chars during animation are eaten silently
                # (same trade-off as the bash version).
            }
            if (-not $Script:SkipTyping) {
                Start-Sleep -Milliseconds $delayMs
            }
        }
        Write-Host ''
    }
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

# ── Tricorder scan ───────────────────────────────────────────────────
function Invoke-TricorderScan {
    Write-Host '  Press any key to begin the scan (space to skip animations)...' -ForegroundColor DarkGray
    $key = [Console]::ReadKey($true)
    if ($key.KeyChar -eq ' ') { $Script:SkipTyping = $true }
    Write-Host ''

    $platform = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'Windows' }
                elseif ($IsMacOS) { 'macOS' }
                elseif ($IsLinux)  { 'Linux' }
                else               { 'unknown' }

    $scan = '  [scan] '
    Write-Host -NoNewline "${scan}Detecting platform..."
    Start-Sleep -Milliseconds 300
    Write-Host " $platform" -ForegroundColor White

    Write-Host -NoNewline "${scan}PowerShell..."
    Start-Sleep -Milliseconds 200
    Write-Host " $($PSVersionTable.PSVersion)" -ForegroundColor White

    Write-Host -NoNewline "${scan}git..."
    Start-Sleep -Milliseconds 200
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host ' installed' -ForegroundColor Green
    } else {
        Write-Host ' not found' -ForegroundColor Red
        Write-Host '          (required - install Git for Windows: https://git-scm.com/download/win)' -ForegroundColor DarkGray
    }

    Write-Host -NoNewline "${scan}claude..."
    Start-Sleep -Milliseconds 200
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host ' installed' -ForegroundColor Green
    } else {
        Write-Host ' not found' -ForegroundColor Yellow
    }

    Write-Host ''
    Start-Sleep -Milliseconds 300
    Write-Typed 'Good. Vitals look stable.'
    Write-Host ''
}

# ── Menu (arrow-key nav) ─────────────────────────────────────────────
# Returns the 0-based index of the selected option. Number keys 1..9 act
# as direct shortcuts (matching the bash prompt_choice behavior). Up/Down
# arrows navigate; wraps at the ends. Enter selects.
function Show-Menu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string[]]$Options
    )
    $selected = 0
    $count    = $Options.Count

    Write-Host "  $Prompt"
    Write-Host ''
    $startTop = [Console]::CursorTop

    while ($true) {
        # Redraw the option list in place
        [Console]::SetCursorPosition(0, $startTop)
        for ($i = 0; $i -lt $count; $i++) {
            $marker = if ($i -eq $selected) { '  > ' } else { '    ' }
            $line   = "$marker$($Options[$i])"
            try { $w = [Console]::WindowWidth } catch { $w = 80 }
            $pad = [Math]::Max(0, $w - $line.Length - 1)
            $color = if ($i -eq $selected) { 'Green' } else { 'DarkGray' }
            Write-Host ($line + (' ' * $pad)) -ForegroundColor $color
        }
        Write-Host ''
        Write-Host '  Arrow keys to move, Enter to select' -ForegroundColor DarkGray

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $selected = if ($selected -gt 0)         { $selected - 1 } else { $count - 1 } }
            'DownArrow' { $selected = if ($selected -lt $count - 1) { $selected + 1 } else { 0 } }
            'Enter'     { return $selected }
            default {
                if ($key.KeyChar -match '^[1-9]$') {
                    $num = [int]([string]$key.KeyChar)
                    if ($num -le $count) { return $num - 1 }
                }
            }
        }
    }
}

# ── Stubs for the remaining flow (TODO) ──────────────────────────────
function Get-ProjectsDir         { throw 'TODO: port detect_projects_dirs / prompt_projects_dir' }
function Show-StructureExplainer { throw 'TODO: port print_structure_explainer' }
function New-DoctorInstance      { throw 'TODO: port the instance creation block' }

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
