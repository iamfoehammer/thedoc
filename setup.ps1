# thedoc setup wizard (PowerShell)
# Native Windows PowerShell 7+ counterpart to setup.sh. Behavioral parity
# with setup.sh end to end, with one deferred feature: the WSL drive scan
# and full folder browser don't apply on PS7 native, so the projects-folder
# picker offers a "Type a path" fallback instead of the bash browse_for_folder.
#
# When in doubt about behavior, setup.sh is still the source of truth - the
# bash version has live E2E tests; this one is verified structurally only
# until run on a real Windows host.

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── --help short-circuit ─────────────────────────────────────────────
# Mirrors setup.sh's help text so the bash-vs-PS UX matches: a user on
# Windows native pwsh can run 'setup.ps1 --help' and get usage info
# before the preflight checks fire.
#
# Uses $args directly (not param/CmdletBinding) so PS doesn't try to
# parse '--help' or '-h' as parameter names. With CmdletBinding,
# 'script.ps1 --help' fails with "A parameter cannot be found that
# matches parameter name 'help'" because PS treats the leading -- as
# the start of a -help parameter.
if ($args.Count -gt 0 -and $args[0] -in @('--help', '-h', 'help', '/?', '-?')) {
    @'
thedoc setup wizard (PowerShell)

Usage:
  setup.ps1           Run the interactive setup wizard.
  setup.ps1 --help    Show this help.

The wizard walks through:
  1. System scan (platform, PowerShell, git, claude)
  2. Picking your projects directory
  3. Choosing a doctor type (Claude Code or OpenClaw today)
  4. Choosing an LLM engine
  5. Naming the instance folder

State is saved at $env:XDG_STATE_HOME\thedoc\state, falling back to
$env:LOCALAPPDATA\thedoc\state (then $HOME\.local\state\thedoc\state),
so the first-run greeting only shows once per machine.

Skip the typing animation any time by pressing space at the
"Press any key" prompts, or by pressing space mid-paragraph
(mid-paragraph skip is PowerShell-only; the bash port skips only
at the explicit prompts).

To skip ALL animations from the very start, set $env:THEDOC_TEST_SKIP_TYPING:
  $env:THEDOC_TEST_SKIP_TYPING = 1; .\setup.ps1

For most users the friendlier entry point is the 'thedoc' wrapper:
  thedoc            same as 'thedoc setup'
  thedoc list       list existing doctor instances
  thedoc open NAME  open an existing instance directly
  thedoc test       parse-check + wrapper tests (Windows-side coverage)
  thedoc version    show framework version (git commit)
  thedoc update     pull the latest framework (git pull --ff-only)
  thedoc help       show wrapper help
'@
    exit 0
}

# Reject unknown args explicitly (iter 261 parity with setup.sh). Pre-
# iter-261 the script silently ran the wizard on any unrecognized arg,
# so a typo like `--debug` or `setup.ps1 foo` looked like nothing was
# wrong. Mirrors the bash port's case-with-explicit-rejection.
if ($args.Count -gt 0) {
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine("  Unknown argument: $($args[0])")
    [Console]::Error.WriteLine("  Run 'setup.ps1 --help' for usage.")
    [Console]::Error.WriteLine('')
    exit 1
}

# ── Preflight ────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  thedoc setup.ps1 needs PowerShell 7+. You're on $($PSVersionTable.PSVersion)."
    Write-Host "  Install PowerShell 7: https://github.com/PowerShell/PowerShell/releases"
    Write-Host ""
    exit 1
}

# setup.ps1 targets Windows-native PowerShell 7+. pwsh on Linux/macOS is
# also PS 7+, but key paths ($env:LOCALAPPDATA, Junction-style symlinks,
# User-scoped PATH env via [Environment]) are Windows-only. Non-Windows
# pwsh users should run setup.sh under their native shell instead. Without
# this check, an empty $env:LOCALAPPDATA crashes Join-Path at first use
# of $StateDir with an unhandled exception, not a friendly message.
if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
    Write-Host ""
    Write-Host "  thedoc setup.ps1 targets Windows-native PowerShell 7+."
    Write-Host "  Looks like you're on $($PSVersionTable.OS)."
    Write-Host "  Run setup.sh under your native shell instead:"
    Write-Host "      bash $(Split-Path -Parent $MyInvocation.MyCommand.Path)/setup.sh"
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

# Catch-all for unhandled exceptions so the user sees a friendly line
# instead of a stack trace. Canonical trigger: [Console]::ReadKey()
# throws InvalidOperationException when stdin has been redirected
# (e.g. `setup.ps1 < script.txt`, piped invocation in CI). Bash's
# `read -rsn1` returns 1 on EOF and setup.sh's _on_exit EXIT trap
# (iter 241) catches that; PS doesn't have an EXIT-trap equivalent
# but a typed [System.Exception] catch-all serves the same purpose.
#
# PipelineStoppedException is a subtype of Exception, but PS's trap
# resolution picks the most-specific matching type, so Ctrl+C still
# routes to the trap above. Try/catch blocks inside functions take
# precedence over either trap, so intentional error handling is
# unaffected. Mirrors setup.sh's _on_exit for consistent UX across
# ports.
trap [System.Exception] {
    Write-Host ''
    Write-Host '  Setup did not complete. No instance was created.' -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host '  If stdin was piped/closed, run setup.ps1 interactively.' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
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
# Path precedence and format match bash setup.sh exactly so the same state
# file works across ports if a user happens to share it (e.g. a cross-shell
# script setting XDG_STATE_HOME explicitly):
#   1. $env:XDG_STATE_HOME (POSIX convention, honored if set)
#   2. $env:LOCALAPPDATA   (Windows default)
#   3. $HOME/.local/state  (POSIX default)
# Format is KEY=VALUE (one per line), not JSON - thedoc.ps1 already parses
# this with Select-String '^projects_dir=' and bash uses sed -n
# 's/^projects_dir=//p'.
$StateDir = if ($env:XDG_STATE_HOME) {
    Join-Path $env:XDG_STATE_HOME 'thedoc'
} elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA 'thedoc'
} else {
    Join-Path $HOME '.local/state/thedoc'
}
$StateFile = Join-Path $StateDir 'state'

function Test-FirstRun {
    # First-run if state is missing, empty, OR has no usable
    # projects_dir entry. Three clauses match bash's is_first_run
    # (iter 270 added clauses 1-2 for missing/empty file; iter 274
    # added clause 3 for partial-write state files that have some
    # content but never wrote the projects_dir= line).
    if (-not (Test-Path -LiteralPath $StateFile)) { return $true }
    if ((Get-Item -LiteralPath $StateFile).Length -eq 0) { return $true }
    $state = Get-State
    return ($null -eq $state -or [string]::IsNullOrEmpty($state.projects_dir))
}

function Save-State {
    param([string]$ProjectsDir, [string]$Platform)
    # -Force auto-creates parent directories (matches bash setup.sh's
    # `mkdir -p "$STATE_DIR"`). Without it, an XDG_STATE_HOME pointing
    # at a not-yet-created path (test harnesses, scripted first-run
    # scenarios, unusual user setups) throws an unhandled
    # DirectoryNotFoundException instead of just creating the tree.
    if (-not (Test-Path $StateDir)) { New-Item -Type Directory -Path $StateDir -Force | Out-Null }
    # Preserve first_run across saves. Bash setup.sh loads FIRST_RUN_DATE
    # from the existing state file (lines 161-168) and re-writes the same
    # value via `${FIRST_RUN_DATE:-current-time}`. PS Save-State was
    # unconditionally writing current time, so every returning run
    # clobbered the original "first ever" timestamp. Iter 199 parity fix.
    # Get-State is defined further down the file; PS function resolution
    # happens at invocation time, so forward reference is fine here.
    $existing = Get-State
    $firstRun = if ($existing -and $existing.first_run) {
        $existing.first_run
    } else {
        (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $lines = @(
        "first_run=$firstRun"
        "projects_dir=$ProjectsDir"
        "platform=$Platform"
    )
    # Atomic-rename pattern: write to tmp then Move-Item -Force.
    # Direct Set-Content can leave a partial file if the process is
    # killed mid-write (signal, power loss, etc.) - iter 274 added a
    # recovery path for that corruption mode but avoiding the corruption
    # in the first place is better. Mirrors iter-276 bash save_state.
    $tmp = "$StateFile.tmp.$PID"
    Set-Content -LiteralPath $tmp -Value $lines -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Get-State {
    if (-not (Test-Path $StateFile)) { return $null }
    $state = @{}
    try {
        Get-Content -LiteralPath $StateFile -ErrorAction Stop | ForEach-Object {
            if ($_ -match '^([a-z_]+)=(.*)$') {
                $state[$Matches[1]] = $Matches[2]
            }
        }
    } catch { return $null }
    # Surface dotted-access (state.projects_dir) for callers used to the
    # old JSON shape: ConvertFrom-Json returned a PSCustomObject.
    return [PSCustomObject]$state
}

# ── Typing effect ────────────────────────────────────────────────────
$Script:SkipTyping = $false
# Test/automation hook - same as bash THEDOC_TEST_SKIP_TYPING. Lets the
# test harness skip all animations and dramatic pauses without trying
# to queue a stdin space (which races with read -rsn1 calls).
if ($env:THEDOC_TEST_SKIP_TYPING) { $Script:SkipTyping = $true }

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

    # Animated path with async space-to-skip. PS gets mid-line skip; the
    # bash port doesn't (iter 152 found bash's per-char `read -t 0` is a
    # pure poll that never consumes/assigns, and the heredoc-driven outer
    # loop redirects fd 0 anyway - the bash check has been dead code).
    # Here KeyAvailable + ReadKey($true) is the correct two-step pattern.
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
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq ' ') {
                    $Script:SkipTyping = $true
                    Write-Host -NoNewline ($line.Substring($i + 1))
                    break
                }
                # Non-space chars during animation are eaten silently.
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

    # Box-drawing chars match bash print_box: U+2554 U+2550 U+2557 (top
    # row), U+2551 (sides), U+255A U+2550 U+255D (bottom). Modern Windows
    # Terminal + PS7 default to UTF-8 output and render these correctly;
    # for older powershell.exe sessions the [Console]::OutputEncoding
    # below ensures the bytes go out as UTF-8 rather than the host codepage.
    if ([Console]::OutputEncoding.WebName -ne 'utf-8') {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    }
    $border = [string]::new([char]0x2550, $title.Length + 4)
    Write-Host ''
    Write-Host "  $([char]0x2554)$border$([char]0x2557)" -ForegroundColor Cyan
    Write-Host "  $([char]0x2551)  $title  $([char]0x2551)" -ForegroundColor Cyan
    Write-Host "  $([char]0x255A)$border$([char]0x255D)" -ForegroundColor Cyan
    Write-Host ''

    if (Test-FirstRun) {
        Write-Typed $greeting -Delay 0.02
        Write-Host ''
        Wait-Dramatic -Milliseconds 500
        Write-Typed '...' -Delay 0.3
        Write-Host ''

        # Voyager check
        Write-Host ''
        # White approximates bash's BOLD; DarkGray on [y/n] mirrors bash's DIM
        # so the emphasis split matches.
        Write-Host -NoNewline '  Have you ever seen Star Trek: Voyager?' -ForegroundColor White
        Write-Host ' [y/n]' -ForegroundColor DarkGray
        $key = [System.Console]::ReadKey($true)
        Write-Host ''

        if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'Y') {
            $artPath = Join-Path $ScriptDir 'thedoc.txt'
            if (Test-Path $artPath) {
                Write-Host ''
                # Cyan wrap matches bash's `echo -e "  ${CYAN}"; cat ...;
                # echo -e "${RESET}"`. Streaming via ForEach-Object is the
                # cmdlet equivalent of cat-with-color (Get-Content alone
                # streams to default Foreground).
                Get-Content $artPath | ForEach-Object {
                    Write-Host $_ -ForegroundColor Cyan
                }
                Write-Host ''
                Write-Host '  The Emergency Medical Hologram, reporting for duty.' -ForegroundColor White
                Write-Host ''
                Write-Host '  Press any key to continue...' -ForegroundColor DarkGray
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
    Write-Host ''
    # Gap-after-action ack - space-to-skip needs visible confirmation,
    # otherwise the user can't tell whether their keystroke registered.
    if ($key.KeyChar -eq ' ') {
        $Script:SkipTyping = $true
        Write-Host '  Animations disabled.' -ForegroundColor DarkGray
        Write-Host ''
    }

    $platform = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'Windows' }
                elseif ($IsMacOS) { 'macOS' }
                elseif ($IsLinux)  { 'Linux' }
                else               { 'unknown' }

    $scan = '  [scan] '
    Write-Host -NoNewline "${scan}Detecting platform..."
    Wait-Dramatic -Milliseconds 300
    Write-Host " $platform" -ForegroundColor White

    Write-Host -NoNewline "${scan}PowerShell..."
    Wait-Dramatic -Milliseconds 200
    Write-Host " $($PSVersionTable.PSVersion)" -ForegroundColor White

    Write-Host -NoNewline "${scan}git..."
    Wait-Dramatic -Milliseconds 200
    if (Get-Command git -ErrorAction SilentlyContinue) {
        # `git version 2.43.0` -> 3rd whitespace-separated field.
        $gitVer = (& git --version 2>$null) -split '\s+' | Select-Object -Index 2
        if (-not $gitVer) { $gitVer = 'unknown' }
        Write-Host " installed ($gitVer)" -ForegroundColor Green
    } else {
        Write-Host ' not found' -ForegroundColor Red
        Write-Host '          (required - install Git for Windows: https://git-scm.com/download/win)' -ForegroundColor DarkGray
    }

    Write-Host -NoNewline "${scan}claude..."
    Wait-Dramatic -Milliseconds 200
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        # `claude --version` emits e.g. `2.1.139 (Claude Code)`. First field.
        $claudeVer = (& claude --version 2>$null) -split '\s+' | Select-Object -Index 0
        if (-not $claudeVer) { $claudeVer = 'unknown' }
        Write-Host " installed ($claudeVer)" -ForegroundColor Green
    } else {
        Write-Host ' not found' -ForegroundColor Yellow
    }

    Write-Host ''
    Wait-Dramatic -Milliseconds 300
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

    # Drain stale keypresses from the input buffer. Mirrors bash
    # flush_input: if the user mashed keys (or hit a digit) during
    # the typing animation, that key would otherwise pop out of
    # ReadKey on the first menu render and auto-select an option.
    while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }

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

# ── Read helpers ─────────────────────────────────────────────────────
# Read-Host always appends ": " to the prompt, which mangles UX for
# bracketed prompts like "[Y/n]" (you'd see "[Y/n]: " instead of "[Y/n] ").
# This wrapper writes the literal prompt and reads a line, no decoration -
# matching bash `read -rp "prompt"` behavior.
function Read-Line {
    param([string]$Prompt = '')
    if ($Prompt) { [Console]::Write($Prompt) }
    $line = [Console]::ReadLine()
    # Coerce $null (EOF / closed stdin / pipe shutdown) to "". Without
    # this, callers that do `(Read-Line ...).Trim()` crash with
    # MethodInvocationException - line 594's "Enter the full path"
    # prompt is the canonical site. Bash's `read -rp` leaves the var
    # empty on EOF rather than throwing, and the surrounding loop
    # spins on empty until the user types a real value (or Ctrl+C's
    # out). Matching that here is gracefully-degrades parity.
    if ($null -eq $line) { return '' }
    return $line
}

# ── Dramatic pauses ──────────────────────────────────────────────────
# Sleep for dramatic effect during the tricorder scan / candidate folder
# discovery. Skipped when $Script:SkipTyping is true so a user pressing
# space to skip animations skips ALL animations, not just typing.
# Mirrors bash _dramatic_sleep().
function Wait-Dramatic {
    param([int]$Milliseconds)
    if (-not $Script:SkipTyping) {
        Start-Sleep -Milliseconds $Milliseconds
    }
}

# ── Stub detection ───────────────────────────────────────────────────
# Returns $true if the file is missing OR carries the "not yet supported"
# marker in its first 5 lines. Used by both the doctor and engine gates so
# stub placeholder files (committed to reserve the slot) don't slip past.
# Mirrors bash is_stub() exactly.
function Test-IsStub {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    if ((Get-Content -LiteralPath $Path -TotalCount 5) -match 'not yet supported') {
        return $true
    }
    return $false
}

# ── Path helpers ─────────────────────────────────────────────────────
# Cross-platform short path display ($HOME -> ~). Mirrors bash short_path.
function Get-ShortPath {
    param([string]$Path)
    if ($Path -and $Path.StartsWith($HOME)) {
        return '~' + $Path.Substring($HOME.Length)
    }
    return $Path
}

# ── Project-folder discovery ─────────────────────────────────────────
# Mirrors bash detect_projects_dirs. Native Windows-only candidates;
# WSL-mounted /mnt/ paths intentionally skipped (those users run setup.sh).
function Get-CandidateProjectDirs {
    $candidates = @(
        (Join-Path $HOME 'GitHub'),
        (Join-Path $HOME 'projects'),
        (Join-Path $HOME 'repos'),
        (Join-Path $HOME 'Claude Projects'),
        (Join-Path $HOME 'code'),
        (Join-Path $HOME 'workspace'),
        (Join-Path $HOME 'dev'),
        (Join-Path $HOME 'Documents/GitHub'),
        (Join-Path $HOME 'Documents/projects'),
        (Join-Path $HOME 'source/repos')   # Visual Studio's default
    )
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($dir in $candidates) {
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $count = 0
            try {
                $count = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue).Count
            } catch {}
            if ($count -gt 0) {
                $results.Add([PSCustomObject]@{
                    Path  = $dir
                    Count = $count
                }) | Out-Null
            }
        }
    }
    return $results.ToArray()
}

# ── Get-ProjectsDir ──────────────────────────────────────────────────
# Mirrors prompt_projects_dir. Returns the chosen absolute path.
# Note: the WSL drive scan and full folder browser from setup.sh are not
# ported - PS7 native users almost always have one of the candidate dirs,
# and the "Type a path" fallback covers anything missed.
function Get-ProjectsDir {
    Write-Host ''
    Write-Typed 'Now I need to find where you keep your projects.'
    Write-Host ''
    Write-Typed 'Most people have a folder where each subfolder is a separate project or agent workspace.'
    Write-Typed 'Some call it "GitHub", others call it "Claude Projects" or just "projects".'
    Write-Host ''
    Write-Typed 'Let me scan your drives...'
    Write-Host ''

    $candidates = Get-CandidateProjectDirs
    foreach ($c in $candidates) {
        $short = Get-ShortPath $c.Path
        # Singular/plural for grammar nit - matches bash detect_projects_dirs
        # output. PS menu rendering already does this; the scan line lagged.
        $word  = if ($c.Count -eq 1) { 'folder' } else { 'folders' }
        Write-Host "  [scan] Found $short/  ($($c.Count) $word)"
        Wait-Dramatic -Milliseconds 150
    }
    if ($candidates.Count -eq 0) {
        Write-Host '  [scan] No project folders found.' -ForegroundColor Yellow
    }

    Write-Host ''
    Wait-Dramatic -Milliseconds 300
    Write-Typed 'Scan complete.'
    Write-Host ''

    # Build menu options
    $options = New-Object 'System.Collections.Generic.List[string]'
    foreach ($c in $candidates) {
        $short = Get-ShortPath $c.Path
        $word  = if ($c.Count -eq 1) { 'folder' } else { 'folders' }
        $options.Add("$short/  ($($c.Count) $word)") | Out-Null
    }
    $options.Add('Type a path') | Out-Null

    $idx = Show-Menu -Prompt 'Which one is your projects folder?' -Options $options.ToArray()

    if ($idx -eq $candidates.Count) {
        # Type a path - re-prompt on empty / mkdir failure (matches setup.sh)
        while ($true) {
            Write-Host ''
            $custom = Read-Line '  Enter the full path: '
            $custom = $custom.Trim()
            # Expand leading ~ ONLY when it's the entire path or
            # followed by '/' or '\'. Previous `-replace '^~', $HOME`
            # also stripped the bare ~ off `~user/foo`, turning it
            # into $HOMEuser/foo (concatenation, not the requested
            # user's homedir). Mirrors the iter 246 case-statement
            # fix in setup.sh.
            if ($custom -eq '~') {
                $custom = $HOME
            } elseif ($custom -match '^~[/\\]') {
                $custom = $HOME + $custom.Substring(1)
            }
            # Strip a single trailing slash/backslash so "$ProjectsDir\foo"
            # doesn't produce a double separator in later messages. Skip
            # for root-like paths ("/" or "C:\").
            if ($custom.Length -gt 1 -and ($custom.EndsWith('/') -or $custom.EndsWith('\'))) {
                if ($custom.Length -ne 3 -or $custom[1] -ne ':') {
                    $custom = $custom.Substring(0, $custom.Length - 1)
                }
            }

            if ([string]::IsNullOrEmpty($custom)) {
                Write-Host "  Path can't be empty." -ForegroundColor Yellow
                continue
            }

            # Require an absolute path (mirrors setup.sh). A relative path
            # like '.' would get saved literally to state and silently
            # point at the wrong place next session.
            if (-not [System.IO.Path]::IsPathRooted($custom)) {
                Write-Host "  Path must be absolute." -ForegroundColor Yellow
                Write-Host "  Example: C:\Users\you\GitHub" -ForegroundColor DarkGray
                continue
            }

            if (-not (Test-Path -LiteralPath $custom -PathType Container)) {
                Write-Host ''
                $create = Read-Line "  That folder doesn't exist. Create it? [Y/n] "
                if ($create -match '^[Nn]') {
                    # Ack the decline before the re-prompt loop (mirrors
                    # setup.sh; gap-after-action heuristic).
                    Write-Host '  OK - type a different path.' -ForegroundColor DarkGray
                    continue
                }
                try {
                    New-Item -Type Directory -Path $custom -Force | Out-Null
                    # Match bash + the surrounding ~-prefixed messages.
                    Write-Host "  Created $(Get-ShortPath $custom)" -ForegroundColor Green
                } catch {
                    Write-Host "  Failed to create $custom." -ForegroundColor Red
                    Write-Host '  Check permissions or try a different path.' -ForegroundColor DarkGray
                    continue
                }
            }
            return $custom
        }
    }

    return $candidates[$idx].Path
}

# ── Show-StructureExplainer ──────────────────────────────────────────
function Show-StructureExplainer {
    param([Parameter(Mandatory)][string]$ProjectsDir)
    $short = Get-ShortPath $ProjectsDir
    Write-Host ''
    # Hanging-indent the path on its own line (mirrors setup.sh): long
    # typed paths otherwise overflow 80 cols and the wrap leaves the
    # path flush-left, making the sentence look truncated.
    Write-Typed 'Got it. Your doctors will live in:'
    Write-Typed "$short/" -Prefix '    '
    Write-Host ''
    Write-Typed "Here's how thedoc works:"
    Write-Typed "- This framework (thedoc) stays where you cloned it"
    # Use a generic example to keep this bullet short (mirrors setup.sh):
    # inlining $short blew past 80 cols when the user typed a long
    # absolute path, and the word-wrap continuation lost its indent.
    Write-Typed "- Each doctor gets its own folder (e.g. claude-code-doctor/)"
    Write-Typed "- The doctor folder has a CLAUDE.md (your personal config)"
    # Get-Wrapped splits on whitespace and skips empty tokens, so leading
    # spaces inside the message get stripped. Use the Prefix arg to get
    # a 4-space hanging indent that survives the wrap (matches bash).
    Write-Typed "and a DOCTOR.md (shared diagnostic instructions)" -Prefix '    '
    Write-Typed "- You update thedoc with 'thedoc update' - your configs are never overwritten"
    Write-Host ''
    Write-Host '  Press any key to continue (space to skip animations)...' -ForegroundColor DarkGray
    $key = [Console]::ReadKey($true)
    Write-Host ''
    # Gap-after-action ack (mirrors bash structure-explainer + tricorder).
    if ($key.KeyChar -eq ' ') {
        $Script:SkipTyping = $true
        Write-Host '  Animations disabled.' -ForegroundColor DarkGray
        Write-Host ''
    }
}

# ── New-DoctorInstance ───────────────────────────────────────────────
# Mirrors the bash instance-creation block: validates instance name with the
# same rules (no slashes, no leading dot, not whitespace, not a non-thedoc
# folder), creates the directory, copies DOCTOR.md, generates CLAUDE.md,
# saves state, and either exec's the engine or short-circuits on
# THEDOC_NO_LAUNCH=1 for testing.
function New-DoctorInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectsDir,
        [Parameter(Mandatory)][string]$DoctorSlug,
        [Parameter(Mandatory)][string]$DoctorName,
        [Parameter(Mandatory)][string]$EngineSlug,
        [Parameter(Mandatory)][string]$EngineName,
        [Parameter(Mandatory)][string]$SetupMode
    )

    # Compute the canonical lowercase platform string ONCE up front.
    # Used both in the CLAUDE.md template (when a new instance is being
    # created) and in the Save-State call further down (which runs on
    # both new-instance and open-existing paths). Pre-iter-260 there
    # were two copies of this if-elseif chain; consolidating prevents
    # drift if the detection logic ever needs to change.
    $platform = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'windows' }
                elseif ($IsMacOS)                            { 'macos' }
                elseif ($IsLinux)                            { 'linux' }
                else                                         { 'unknown' }

    $defaultInstance = "$DoctorSlug-doctor"
    Write-Host "  Name for your doctor instance folder?"
    # Drop the inline path here (mirrors setup.sh): the structure-
    # explainer already showed it on its own indented line, and inlining
    # blew past 80 cols on long typed paths.
    Write-Host '  Press Enter for default.' -ForegroundColor DarkGray

    while ($true) {
        Write-Host ''
        $entered = Read-Line "  [$defaultInstance] > "
        # Iter 178: distinguish empty input (Enter alone → use default) from
        # whitespace-only input (reject). Bash iter 87 makes this distinction
        # via `IFS= read` + trim + -z check; PS used to collapse both cases
        # to "use default", which was friendlier but inconsistent with bash
        # and hid an actual typo (user meaning to type a name but only
        # hitting spaces) behind a silent substitution.
        if ($entered.Length -eq 0) {
            $instanceName = $defaultInstance
        }
        elseif ([string]::IsNullOrWhiteSpace($entered)) {
            Write-Host "  Name can't be empty or whitespace." -ForegroundColor Yellow
            continue
        }
        else {
            $instanceName = $entered.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($instanceName)) {
            Write-Host "  Name can't be empty or whitespace." -ForegroundColor Yellow
            continue
        }
        if ($instanceName -match '[/\\]') {
            Write-Host "  Name can't contain '/' or '\'. Use just the folder name." -ForegroundColor Yellow
            continue
        }
        if ($instanceName.StartsWith('.')) {
            Write-Host "  Name can't start with '.' (would create a hidden folder)." -ForegroundColor Yellow
            continue
        }
        $candidate = Join-Path $ProjectsDir $instanceName
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and
            -not (Test-Path -LiteralPath (Join-Path $candidate 'DOCTOR.md'))) {
            Write-Host "  $(Get-ShortPath $candidate) exists but isn't a thedoc instance" -ForegroundColor Yellow
            Write-Host "  (no DOCTOR.md inside). Pick a different name." -ForegroundColor DarkGray
            continue
        }
        # If candidate IS an existing thedoc instance, let the user open it
        # or re-pick a name without restarting the whole wizard.
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            Write-Host ''
            Write-Host "  $(Get-ShortPath $candidate) already exists as a doctor instance." -ForegroundColor Yellow
            $resp = Read-Line '  Open existing instance? [Y/n] '
            if ($resp -match '^[Nn]') {
                Write-Host '  OK - pick a different name.' -ForegroundColor DarkGray
                continue
            }
            # Acknowledge the open so the user sees confirmation between
            # [Y/n] and "Ready to launch." Mirrors setup.sh.
            Write-Host '  OK - opening existing instance.' -ForegroundColor DarkGray
        }
        break
    }

    $instanceDir = Join-Path $ProjectsDir $instanceName

    if (-not (Test-Path -LiteralPath $instanceDir -PathType Container)) {
        try {
            New-Item -Type Directory -Path $instanceDir -Force -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "  Failed to create $(Get-ShortPath $instanceDir)" -ForegroundColor Red
            Write-Host '  Try creating it manually and re-running.' -ForegroundColor DarkGray
            exit 1
        }
        Write-Host "  Created $(Get-ShortPath $instanceDir)" -ForegroundColor Green

        Copy-Item -LiteralPath (Join-Path $ScriptDir "doctors/$DoctorSlug/DOCTOR.md") `
                  -Destination  (Join-Path $instanceDir 'DOCTOR.md')
        Write-Host "  Copied DOCTOR.md ($DoctorName)" -ForegroundColor Green

        # Junction is the Windows-friendly equivalent of `ln -s` for dirs;
        # works without admin/dev mode. Falls back to a text file holding
        # the absolute path if the FS rejects it (e.g. some network shares).
        # An empty `updates/` dir used to be created here too - dead code
        # since the initial release, removed iter 189.
        $junctionPath   = Join-Path $instanceDir '.framework-updates'
        $junctionTarget = Join-Path $ScriptDir "doctors/$DoctorSlug/updates"
        try {
            New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -ErrorAction Stop | Out-Null
            Write-Host '  Linked framework updates' -ForegroundColor Green
        }
        catch {
            Set-Content -LiteralPath $junctionPath -Value $junctionTarget
            Write-Host '  Linked framework updates (text fallback)' -ForegroundColor Green
        }

        # $platform was set at the top of this function so it's the
        # same canonical value used for Save-State below.

        # UTC Zulu format to match bash setup.sh's
        # `date -u +"%Y-%m-%dT%H:%M:%SZ"` exactly. Both 'thedoc list'
        # parsers strip at first T anyway, but writing the same format
        # keeps CLAUDE.md files diffable across ports and prevents a
        # future stricter parser from being confused by .NET's
        # round-trip 'o' format (trailing fractional seconds + offset).
        $created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $claudeMd = @"
# $DoctorName Doctor

Read DOCTOR.md for your core instructions and personality.
Everything below is this instance's personal configuration.

## Setup Info

- **Doctor type:** $DoctorName
- **Engine:** $EngineName
- **Setup mode:** $SetupMode
- **Created:** $created
- **Framework:** $ScriptDir

## System

- **OS:** $($PSVersionTable.OS)
- **Platform:** $platform
- **Shell:** PowerShell $($PSVersionTable.PSVersion)
- **WSL:** no
- **Home:** $HOME
- **Projects dir:** $ProjectsDir

## Known Issues & Fixes

| Issue | Cause | Fix |
|---|---|---|

## Where to Save New Learnings

Add new issues and fixes to the Known Issues & Fixes table above.
"@
        Set-Content -LiteralPath (Join-Path $instanceDir 'CLAUDE.md') -Value $claudeMd
        Write-Host '  Generated CLAUDE.md' -ForegroundColor Green

        New-Item -Type File -Path (Join-Path $instanceDir '.applied-updates') -Force | Out-Null

        $gitignore = @"
# Framework link (local path, not portable)
.framework-updates

# Update tracker (per-user state)
.applied-updates

# Private configs
.private/
"@
        Set-Content -LiteralPath (Join-Path $instanceDir '.gitignore') -Value $gitignore
        Write-Host '  Created .gitignore' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Ready to launch.' -ForegroundColor White
    Write-Host ''

    # $platform was computed once at the top of this function (iter 260
    # consolidated the previous two copies). Iter 200's fix is preserved:
    # we use the freshly-detected runtime value, not whatever the state
    # file might have on disk from a different shell/OS.
    Save-State -ProjectsDir $ProjectsDir -Platform $platform

    if ($env:THEDOC_NO_LAUNCH) {
        Write-Host '  THEDOC_NO_LAUNCH set - skipping engine launch (test mode).' -ForegroundColor DarkGray
        Write-Host "  Instance ready at $(Get-ShortPath $instanceDir)" -ForegroundColor DarkGray
        Write-Host ''
        exit 0
    }

    # By here engineSlug is either claude-code (real) or a stub that the
    # user accepted fallback for (so engineSlug got rewritten to claude-code
    # above). The earlier Test-IsStub gate already caught missing/stub
    # launchers, so this Test-Path is just a paranoid backstop for the
    # claude-code.ps1-was-deleted-from-the-checkout case.
    $engineScript = Join-Path $ScriptDir "engines/$EngineSlug.ps1"
    if (Test-Path -LiteralPath $engineScript) {
        & $engineScript -InstanceDir $instanceDir -SetupMode $SetupMode -DoctorType $DoctorSlug
        # Propagate the engine's exit code. Bash uses `exec engines/X.sh`
        # which inherits exit code automatically; PS's `&` does not, so
        # without this an engine crash (e.g. claude exits 1) would
        # surface as setup.ps1 exit 0 in the parent (thedoc.ps1, CI,
        # any caller). Iter 162 propagation fix.
        exit $LASTEXITCODE
    }
    else {
        Write-Host "  Engine launcher missing: $engineScript" -ForegroundColor Red
        Write-Host "  This shouldn't happen - try 'thedoc update' to refresh the framework." -ForegroundColor DarkGray
        exit 1
    }
}

# ── Main ─────────────────────────────────────────────────────────────

# Re-bootstrap shortcut: if state already exists AND bootstrap set
# THEDOC_BOOTSTRAP_DIR, the user re-ran the install one-liner - they
# want update/re-install, not "create another instance". Handle both
# subcases (matches setup.sh branch above):
#   1. installed framework still exists - update in place
#   2. framework deleted but state intact - re-install (move from TEMP)
if ($env:THEDOC_BOOTSTRAP_DIR -and
    (Test-Path -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -PathType Container) -and
    -not (Test-FirstRun)) {
    $state = Get-State
    if ($state -and $state.projects_dir -and (Test-Path -LiteralPath $state.projects_dir -PathType Container)) {
        $thedocFinal = Join-Path $state.projects_dir 'thedoc'
        Write-Host ''
        if (Test-Path -LiteralPath $thedocFinal -PathType Container) {
            Write-Host "  Updating thedoc at $(Get-ShortPath $thedocFinal)..."
            Copy-Item -Path (Join-Path $env:THEDOC_BOOTSTRAP_DIR '*') `
                      -Destination $thedocFinal -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host '  Updated thedoc.' -ForegroundColor Green
        } else {
            Write-Host "  Re-installing thedoc at $(Get-ShortPath $thedocFinal)..."
            try {
                Move-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Destination $thedocFinal -ErrorAction Stop
            } catch {
                New-Item -ItemType Directory -Path $thedocFinal -Force | Out-Null
                Copy-Item -Path (Join-Path $env:THEDOC_BOOTSTRAP_DIR '*') `
                          -Destination $thedocFinal -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host '  Installed thedoc.' -ForegroundColor Green
        }
        Write-Host ''
        Write-Host "  Run 'thedoc' to create another instance, or 'thedoc open <name>' to resume." -ForegroundColor DarkGray
        Write-Host ''
        exit 0
    }
}

Show-Greeting

if (Test-FirstRun) {
    Invoke-TricorderScan
    $script:ProjectsDir = Get-ProjectsDir

    # If launched from bootstrap.ps1, the repo currently lives in
    # $env:TEMP\thedoc-<guid>. Move it into the chosen projects dir and
    # add to User PATH so 'thedoc' is on PATH in future sessions. Mirrors
    # the THEDOC_BOOTSTRAP_DIR branch in setup.sh.
    if ($env:THEDOC_BOOTSTRAP_DIR -and (Test-Path -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -PathType Container)) {
        $thedocFinal = Join-Path $script:ProjectsDir 'thedoc'
        Write-Host ''
        Write-Typed 'Moving thedoc to your projects folder...'

        if (Test-Path -LiteralPath $thedocFinal -PathType Container) {
            Write-Host "  $(Get-ShortPath $thedocFinal) already exists - updating..." -ForegroundColor Yellow
            # -Path takes a wildcard; -LiteralPath does not. Copy contents
            # (not the dir itself) by globbing the bootstrap dir.
            Copy-Item -Path (Join-Path $env:THEDOC_BOOTSTRAP_DIR '*') `
                      -Destination $thedocFinal -Recurse -Force -ErrorAction SilentlyContinue
            # Mirror the catch-branch below: purge $THEDOC_BOOTSTRAP_DIR
            # after the copy. The Move-Item branch below takes care of
            # cleanup naturally; this branch was the parity-outlier (same
            # gap iter 165 fixed on the bash side).
            Remove-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            # Move-Item fails across volumes (TEMP on C:, projects on D:).
            # Try the cheap move first, fall back to Copy + cleanup.
            try {
                Move-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Destination $thedocFinal -ErrorAction Stop
            }
            catch {
                New-Item -ItemType Directory -Path $thedocFinal -Force | Out-Null
                Copy-Item -Path (Join-Path $env:THEDOC_BOOTSTRAP_DIR '*') `
                          -Destination $thedocFinal -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $env:THEDOC_BOOTSTRAP_DIR -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "  Installed thedoc to $(Get-ShortPath $thedocFinal)" -ForegroundColor Green
        $script:ScriptDir = $thedocFinal

        # User PATH (HKCU). Only append if not already present - avoids
        # ballooning the var on repeat installs. Read via .NET API rather
        # than $env:PATH (which is the merged session view).
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if (-not $userPath) { $userPath = '' }
        $pathEntries = $userPath -split ';' | Where-Object { $_ -ne '' }
        if ($pathEntries -notcontains $thedocFinal) {
            $newPath = if ($userPath) { "$thedocFinal;$userPath" } else { $thedocFinal }
            [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
            $env:PATH = "$thedocFinal;$env:PATH"
            Write-Host "  Added thedoc to User PATH" -ForegroundColor Green
        } else {
            # On re-bootstrap, confirm the PATH is already wired - otherwise
            # the bootstrap branch ends abruptly after "Installed thedoc to..."
            # and the user can't tell if PATH was silently skipped.
            Write-Host '  thedoc already on User PATH' -ForegroundColor DarkGray
        }

        # Wire ~/.secrets.ps1 into the user's PowerShell profile so
        # llm-secrets.ps1's stored env vars are loaded in new shells.
        # Mirrors the bash branch's '[ -f ~/.secrets ] && source ~/.secrets'
        # bashrc append. CurrentUserAllHosts is shared between pwsh and
        # powershell.exe, which is what we want.
        $profilePath = $PROFILE.CurrentUserAllHosts
        $profileDir  = Split-Path -Parent $profilePath
        if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        # Defensive single-line form: try/catch the dot-source so a
        # broken ~/.secrets.ps1 (manual edit, partial write, accidental
        # keystroke) produces a Write-Warning at shell open rather than
        # a fatal stack trace. The user still sees something's wrong
        # and can fix the file, but the shell still loads. iter 296
        # added the same guard at the two thedoc-internal dot-source
        # sites (engines/claude-code.ps1, thedoc.ps1 open); this
        # extends the resilience to every new PS shell the user opens
        # after thedoc wired the profile.
        # Write-Host with -ForegroundColor instead of Write-Warning so a
        # user who sets $WarningPreference='Stop' (rare, but power
        # users do) doesn't get a fresh terminating error in their
        # catch block. Write-Host bypasses the warning preference
        # entirely - the message always shows, in yellow, on every
        # new shell where ~/.secrets.ps1 has issues.
        $secretsLine = 'if (Test-Path "$HOME/.secrets.ps1") { try { . "$HOME/.secrets.ps1" } catch { Write-Host "~/.secrets.ps1: $($_.Exception.Message)" -ForegroundColor Yellow } }'
        $existing = if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
            Get-Content -LiteralPath $profilePath -Raw
        } else { '' }
        # Match the dot-source expression specifically, not just '.secrets.ps1'
        # as substring - the looser check would false-positive on a comment
        # mentioning the file, or an unrelated reference.
        if ($existing -notmatch [regex]::Escape('. "$HOME/.secrets.ps1"')) {
            if ($existing -and -not $existing.EndsWith("`n")) {
                Add-Content -LiteralPath $profilePath -Value ''
            }
            Add-Content -LiteralPath $profilePath -Value '# thedoc - load llm-secrets'
            Add-Content -LiteralPath $profilePath -Value $secretsLine
            Write-Host "  Added secrets sourcing to $(Split-Path -Leaf $profilePath)" -ForegroundColor Green
        } else {
            Write-Host "  secrets sourcing already wired in $(Split-Path -Leaf $profilePath)" -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Show-StructureExplainer -ProjectsDir $script:ProjectsDir
}
else {
    $state = Get-State
    if ($state -and $state.projects_dir -and (Test-Path -LiteralPath $state.projects_dir)) {
        $script:ProjectsDir = $state.projects_dir
    } else {
        $script:ProjectsDir = Split-Path -Parent $ScriptDir
        # Surface stale state explicitly so the user sees WHERE the new
        # instance will land (mirrors setup.sh; same UX as list/open in
        # iter 102/103).
        if ($state -and $state.projects_dir -and -not (Test-Path -LiteralPath $state.projects_dir)) {
            Write-Host ''
            Write-Host "  Note: state's projects_dir ($(Get-ShortPath $state.projects_dir)) is missing." -ForegroundColor Yellow
            Write-Host "  New instances will be created in $(Get-ShortPath $script:ProjectsDir)/ for this run." -ForegroundColor DarkGray
            Write-Host ''
        }
    }
}

# Doctor type / engine / setup mode selection (number-key shortcuts work)
$DoctorTypes = @('Claude Code', 'OpenClaw', 'Gemini CLI (not yet supported)')
$DoctorSlugs = @('claude-code', 'openclaw',  'gemini')
$EngineTypes = @('Claude Code', 'OpenClaw (not yet supported)', 'Gemini CLI (not yet supported)')
$EngineSlugs = @('claude-code', 'openclaw',                      'gemini')
$SetupModes  = @('Quick - generate a starter config, refine later',
                 'Full - interactive audit of your current setup')
$SetupSlugs  = @('quick', 'full')

Write-Host ''
$doctorIdx  = Show-Menu -Prompt 'What is this doctor for?' -Options $DoctorTypes
$doctorSlug = $DoctorSlugs[$doctorIdx]
$doctorName = $DoctorTypes[$doctorIdx]

# Doctor type supported? Stub DOCTOR.md files trigger the same coming-soon
# exit as missing files (see Test-IsStub above).
if (Test-IsStub (Join-Path $ScriptDir "doctors/$doctorSlug/DOCTOR.md")) {
    # Strip the "(not yet supported)" suffix from the menu name when used
    # in the status message - otherwise it reads redundantly as
    # "Gemini CLI (not yet supported) doctor templates are coming soon."
    $displayName = $doctorName -replace ' \(not yet supported\)$', ''
    Write-Host ''
    Write-Host "  $displayName doctor templates are coming soon." -ForegroundColor Yellow
    Write-Host '  The framework is here - contributions welcome!'
    Write-Host "  See doctors/$doctorSlug/ to help build it." -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

Write-Host ''
$engineIdx  = Show-Menu -Prompt 'Which LLM engine will power this doctor?' -Options $EngineTypes
$engineSlug = $EngineSlugs[$engineIdx]
$engineName = $EngineTypes[$engineIdx]

# Engine supported on this platform? The .ps1 launcher is the one this
# script will exec, so checking it (not the .sh sibling) is correct: if
# someone fills in claude-code.sh but leaves openclaw.ps1 as a stub, a
# PowerShell user should still see "coming soon" rather than crashing
# later. Test-IsStub returns true for both missing and stub-marked files.
if (Test-IsStub (Join-Path $ScriptDir "engines/$engineSlug.ps1")) {
    # Strip the "(not yet supported)" suffix - same reason as the doctor-
    # type stub branch above. "OpenClaw engine support is coming soon" reads
    # cleaner than "OpenClaw (not yet supported) engine support...".
    $displayEngineName = $engineName -replace ' \(not yet supported\)$', ''
    Write-Host ''
    Write-Host "  $displayEngineName engine support is coming soon." -ForegroundColor Yellow
    Write-Host ''
    $fallback = Read-Line '  Run with Claude Code instead? [Y/n] '
    if ($fallback -match '^[Nn]') {
        Write-Host "  No worries. Check back later or help build it: engines/$engineSlug.ps1" -ForegroundColor DarkGray
        exit 0
    }
    $engineSlug = 'claude-code'
    $engineName = 'Claude Code'
    # Acknowledge the swap so the next prompt ("Setup mode?") doesn't
    # come out of nowhere - mirrors setup.sh's confirmation line.
    Write-Host '  OK - using Claude Code instead.' -ForegroundColor DarkGray
}

Write-Host ''
$modeIdx   = Show-Menu -Prompt 'Setup mode?' -Options $SetupModes
$setupMode = $SetupSlugs[$modeIdx]

Write-Host ''
New-DoctorInstance -ProjectsDir $script:ProjectsDir `
                   -DoctorSlug $doctorSlug -DoctorName $doctorName `
                   -EngineSlug $engineSlug -EngineName $engineName `
                   -SetupMode  $setupMode
