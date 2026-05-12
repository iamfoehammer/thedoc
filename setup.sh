#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── --help short-circuit ────────────────────────────────────────────
case "${1:-}" in
    --help|-h|help)
        cat <<'EOF'
thedoc setup wizard

Usage:
  setup.sh           Run the interactive setup wizard.
  setup.sh --help    Show this help.

The wizard walks through:
  1. System scan (platform, shell, tmux, git, claude)
  2. Picking your projects directory
  3. Choosing a doctor type (Claude Code or OpenClaw today)
  4. Choosing an LLM engine
  5. Naming the instance folder

State is saved at $XDG_STATE_HOME/thedoc/state (defaults to
~/.local/state/thedoc/state) so the first-run greeting only shows
once per machine.

Skip the typing animation any time by pressing space at the
"Press any key (space to skip animations)" prompts (flips skip
mode for the rest of the run).

To skip ALL animations from the very start (no waiting for
prompts), set the env var THEDOC_TEST_SKIP_TYPING=1:
  THEDOC_TEST_SKIP_TYPING=1 thedoc
(Originally a test hook; equally useful for impatient users.)

For most users the friendlier entry point is the 'thedoc' wrapper:
  thedoc            same as 'thedoc setup'
  thedoc list       list existing doctor instances
  thedoc open NAME  open an existing instance directly
  thedoc test       run the wrapper + setup.sh test suites (mirrors CI)
  thedoc version    show framework version (git commit)
  thedoc update     pull the latest framework (git pull --ff-only)
  thedoc help       show wrapper help
EOF
        exit 0
        ;;
esac

# ── Preflight: sanity checks before doing anything user-facing ─────
# Fail fast with a friendly message if the runtime can't support us.

# Bash 3.2+ required (macOS ships 3.2; any modern Linux is 4+ or 5+).
if [ "${BASH_VERSINFO[0]:-0}" -lt 3 ] || \
   { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
    echo "" >&2
    echo "  thedoc needs bash 3.2 or newer. You're on ${BASH_VERSION:-unknown}." >&2
    echo "  On macOS, install a modern bash with: brew install bash" >&2
    echo "" >&2
    exit 1
fi

_require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "" >&2
        echo "  thedoc needs '$1' but it isn't on your PATH." >&2
        if [ -n "${2:-}" ]; then
            echo "  ${2}" >&2
        else
            echo "  Install it via your package manager and try again." >&2
        fi
        echo "" >&2
        exit 1
    fi
}
_require git "On macOS: brew install git. On Linux: apt install git (or your distro's equivalent)."
_require awk
_require sed
_require find

# Clean exit on Ctrl+C / SIGTERM. Without this, a mid-flow interrupt leaves
# the user staring at a half-typed line with no idea what happened.
_on_interrupt() {
    echo ""
    echo ""
    echo "  Aborted. No instance was created." >&2
    echo "" >&2
    exit 130
}
trap _on_interrupt INT TERM

# ── Colors ──────────────────────────────────────────────────────────
# Honor https://no-color.org/ - if NO_COLOR is set (any non-empty value),
# emit no ANSI escape codes. Useful for accessibility, log capture, and
# pipelines that don't strip ANSI before consuming output.
if [ -n "${NO_COLOR:-}" ]; then
    BOLD='' DIM='' CYAN='' GREEN='' YELLOW='' RED='' RESET=''
else
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[36m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RED='\033[31m'
    RESET='\033[0m'
fi

# ── EMH title rotation ─────────────────────────────────────────────
TITLES=(
    "Emergency LLM Hologram"
    "Emergency CLI Hologram"
    "Emergency AI Medical Hologram"
    "Emergency AI Med Hologram"
    "Emergency Harness Hologram"
    "Emergency Agent Hologram"
    "Emergency Config Hologram"
    "Medical AI"
)

GREETINGS=(
    "Please state the nature of the LLM emergency."
    "Please state the nature of the CLI emergency."
    "Please state the nature of the AI emergency."
    "Please state the nature of the medical emergency."
    "Please state the nature of the harness emergency."
    "Please state the nature of the agent emergency."
    "Please state the nature of the configuration emergency."
    "Please state the nature of the emergency."
)

QUIPS=(
    "Back so soon? What did you break this time?"
    "Ah, a returning patient. Let me pull up your chart."
    "I'm a doctor, not a debugger. Well, actually, I'm both."
    "House call or emergency? Either way, I'm here."
    "No need to describe your symptoms - I'll run a diagnostic."
    "The doctor is in."
    "Another day, another config file in critical condition."
    "I see you've returned. The prognosis must be serious."
)

# ── State file ─────────────────────────────────────────────────────
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/thedoc"
STATE_FILE="$STATE_DIR/state"

is_first_run() {
    [ ! -f "$STATE_FILE" ]
}

save_state() {
    mkdir -p "$STATE_DIR"
    cat > "$STATE_FILE" << EOF
first_run=${FIRST_RUN_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}
projects_dir=${PROJECTS_DIR}
platform=${PLATFORM}
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        # POSIX sed - works on BSD (macOS) and GNU. grep -oP is GNU-only.
        FIRST_RUN_DATE=$(sed -n 's/^first_run=//p' "$STATE_FILE" 2>/dev/null || echo "")
        PROJECTS_DIR=$(sed -n 's/^projects_dir=//p' "$STATE_FILE" 2>/dev/null || echo "")
        PLATFORM=$(sed -n 's/^platform=//p' "$STATE_FILE" 2>/dev/null || echo "")
        # Strip trailing CR. PS Save-State on Windows may write CRLF; sed
        # preserves the \r in the captured value, which breaks [ -d ] tests
        # on what looks like a valid path. iter 108: don't trust the LF
        # contract across ports.
        FIRST_RUN_DATE="${FIRST_RUN_DATE%$'\r'}"
        PROJECTS_DIR="${PROJECTS_DIR%$'\r'}"
        PLATFORM="${PLATFORM%$'\r'}"
    fi
}

# ── Helpers ─────────────────────────────────────────────────────────
pick_random() {
    local arr=("$@")
    echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

# Sleep for dramatic effect during the tricorder scan / candidate folder
# discovery. Skipped entirely when SKIP_TYPING=1 - the user has signalled
# they want the animations gone, that includes pauses-between-events.
# Explicit `return 0` so the function never propagates the [ ... ] test
# failure under `set -e` (which would abort the entire script).
_dramatic_sleep() {
    if [ "$SKIP_TYPING" -eq 0 ]; then
        sleep "$1"
    fi
    return 0
}

# Returns 0 (true) if the file is missing OR carries the "not yet supported"
# marker in its first 5 lines. Used by the doctor-type and engine gates so
# stub placeholder files (committed to reserve the slot) don't slip past.
is_stub() {
    local file="$1"
    [ ! -f "$file" ] && return 0
    head -5 "$file" 2>/dev/null | grep -qF "not yet supported"
}

# Typing effect - prints text character by character.
# Width-aware: pre-wraps at word boundaries (awk; portable across BSD/GNU)
# so the terminal never breaks a word mid-character during the animation.
# Press space at the "press any key" prompts to flip SKIP_TYPING=1; in skip
# mode each typeit call dumps wrapped lines in a single print (no per-char
# loop, instant on bash 3.2).
SKIP_TYPING=0
# Test/automation hook: when THEDOC_TEST_SKIP_TYPING is non-empty in the
# environment, start with skip mode already on. Equivalent to the user
# pressing space at every "space to skip animations" prompt - dramatic
# pauses and typing animations all no-op from the first byte. Out-of-band
# (env var, not stdin) so the test harness avoids the race that would
# otherwise come from queueing a space byte and hoping typeit's async-poll
# consumes it before some other read does.
[ -n "${THEDOC_TEST_SKIP_TYPING:-}" ] && SKIP_TYPING=1

typeit() {
    local text="$1"
    local delay="${2:-0.008}"
    local prefix="${3:-  }"
    local cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    local wrap_at=$((cols - ${#prefix}))
    [ "$wrap_at" -lt 20 ] && wrap_at=20

    # awk-based word-wrap (BSD/GNU portable). fold -s mis-handles tight
    # column boundaries on macOS, hence rolling our own greedy wrap.
    local wrapped
    wrapped=$(printf '%s\n' "$text" | awk -v w="$wrap_at" '
    {
        n = split($0, words, " ")
        line = ""
        for (i = 1; i <= n; i++) {
            word = words[i]
            if (word == "") continue
            if (length(line) == 0) {
                line = word
            } else if (length(line) + 1 + length(word) <= w) {
                line = line " " word
            } else {
                print line
                line = word
            }
        }
        if (length(line) > 0) print line
    }')

    # Skip mode: dump every wrapped line in one print. The per-char loop
    # is slow on bash 3.2 even with delay=0 (one printf per character),
    # so we bypass it entirely once the user presses space.
    if [ "$SKIP_TYPING" -eq 1 ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            printf '%s%s\n' "$prefix" "$line"
        done <<< "$wrapped"
        return
    fi

    # Animated path. Mid-line space-to-skip USED to live here as a
    # per-char `read -t 0 -rsn1 key` poll, but iter 152 proved that's
    # dead code: bash's `-t 0` is a *poll only* (returns 0 if data is
    # available) - it does not actually consume the byte or assign the
    # variable. The check `[ "$key" = " " ]` therefore always saw the
    # initial empty string. The heredoc `<<< "$wrapped"` on the loop
    # also redirected fd 0 to the wrapped text, so even a "real" read
    # here would never see the user's keyboard. The space-to-skip
    # feature works at the explicit "Press any key (space to skip)"
    # prompts (post-iter-151 IFS= fix) - mid-animation skip is gone.
    local first=1
    while IFS= read -r line || [ -n "$line" ]; do
        [ "$first" -eq 1 ] || echo ""
        first=0

        # Skip already engaged - dump line whole, no newline (next loop adds it)
        if [ "$SKIP_TYPING" -eq 1 ]; then
            printf '%s%s' "$prefix" "$line"
            continue
        fi

        printf '%s' "$prefix"
        local i
        for ((i=0; i<${#line}; i++)); do
            printf '%s' "${line:$i:1}"
            sleep "$delay"
        done
    done <<< "$wrapped"
    echo ""
}

# Short path display - regex-free prefix strip so $HOME values with
# sed-meta chars (., |, &, \) don't break the substitution. Mirrors
# PS Get-ShortPath's StartsWith approach.
short_path() {
    if [[ "$1" == "$HOME"* ]]; then
        echo "~${1#$HOME}"
    else
        echo "$1"
    fi
}

print_box() {
    local text="$1"
    local len=${#text}
    local border=$(printf '═%.0s' $(seq 1 $((len + 4))))
    echo ""
    echo -e "  ${CYAN}╔${border}╗${RESET}"
    echo -e "  ${CYAN}║${RESET}  ${BOLD}${text}${RESET}  ${CYAN}║${RESET}"
    echo -e "  ${CYAN}╚${border}╝${RESET}"
    echo ""
}

print_greeting() {
    local idx=$((RANDOM % ${#TITLES[@]}))
    local title="${TITLES[$idx]}"
    local greeting="${GREETINGS[$idx]}"

    print_box "$title activated"
    echo ""

    if is_first_run; then
        typeit "$greeting" 0.02
        echo ""
        _dramatic_sleep 0.5
        typeit "..." 0.3
        echo ""

        # Voyager check - if the user knows the reference, the doctor reveals himself.
        # If not, skip the bit and proceed straight to the install.
        echo -e "  ${BOLD}Have you ever seen Star Trek: Voyager?${RESET} ${DIM}[y/n]${RESET}"
        echo ""
        read -rsn1 voyager_answer
        echo ""

        if [[ "$voyager_answer" == "y" || "$voyager_answer" == "Y" ]]; then
            if [ -f "$SCRIPT_DIR/thedoc.txt" ]; then
                # Set cyan, cat the art, reset. Skip leading "  " on the
                # ANSI-toggle echos so cleaned transcript doesn't carry
                # whitespace-only lines. Drop the redundant pre-art blank
                # (line 330's `echo ""` after the read already provides
                # vertical breathing room). Iter 228 polish matching PS
                # Show-Greeting's tighter render.
                echo -e "${CYAN}"
                cat "$SCRIPT_DIR/thedoc.txt"
                echo -e "${RESET}"
                echo -e "  ${BOLD}The Emergency Medical Hologram, reporting for duty.${RESET}"
                echo ""
                echo -e "  ${DIM}Press any key to continue...${RESET}"
                read -rsn1
                echo ""
            fi
        fi

        typeit "No emergency? Just a checkup? That's fine too."
        typeit "Contrary to my name, I handle everything from routine"
        typeit "configuration to catastrophic meltdowns."
        echo ""
        typeit "I'm going to need to scan your system first."
        typeit "Think of it as a routine physical."
        echo ""
    else
        local quip
        quip=$(pick_random "${QUIPS[@]}")
        typeit "$quip"
        echo ""
    fi
}

CHOICE_IDX=0

# Flush any buffered keyboard input
flush_input() {
    while read -rsn1 -t 0.05 _discard 2>/dev/null; do :; done
}

# Draw a menu with arrow key navigation
# Sets CHOICE_IDX to the selected index (0-based)
prompt_choice() {
    local prompt_text="$1"
    shift
    local options=("$@")
    local selected=0
    local count=${#options[@]}

    # Flush any stale keypresses from previous prompts
    flush_input

    echo -e "  ${BOLD}${prompt_text}${RESET}"
    echo ""

    # Draw menu
    draw_menu() {
        local i=0
        for opt in "${options[@]}"; do
            if [ "$i" -eq "$selected" ]; then
                echo -e "  ${GREEN}> ${BOLD}${opt}${RESET}"
            else
                echo -e "    ${DIM}${opt}${RESET}"
            fi
            i=$((i + 1))
        done
        echo ""
        echo -e "  ${DIM}Arrow keys to move, Enter to select${RESET}"
    }

    draw_menu

    while true; do
        # Read a keypress
        read -rsn1 key

        # Handle escape sequences (arrow keys)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 arrow
            case "$arrow" in
                '[A') # Up arrow
                    if [ "$selected" -gt 0 ]; then
                        selected=$((selected - 1))
                    else
                        selected=$((count - 1))
                    fi
                    ;;
                '[B') # Down arrow
                    if [ "$selected" -lt $((count - 1)) ]; then
                        selected=$((selected + 1))
                    else
                        selected=0
                    fi
                    ;;
            esac
            # Redraw: move cursor up (count lines + 1 for hint)
            local lines=$((count + 2))
            printf '\033[%dA' "$lines"
            # Clear those lines
            for ((i=0; i<lines; i++)); do
                printf '\033[2K\n'
            done
            printf '\033[%dA' "$lines"
            draw_menu
        elif [[ "$key" == "" ]]; then
            # Enter key
            CHOICE_IDX=$selected
            return 0
        elif [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$count" ]; then
            # Number key still works as shortcut
            CHOICE_IDX=$((key - 1))
            return 0
        fi
    done
}

# ── Platform detection ─────────────────────────────────────────────
detect_platform() {
    IS_WSL="no"
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL="yes"
        PLATFORM="linux-wsl2"
    elif [ "$(uname -s)" = "Darwin" ]; then
        PLATFORM="macos"
    elif [ "$(uname -s)" = "Linux" ]; then
        PLATFORM="linux"
    else
        PLATFORM="windows-gitbash"
    fi

    SHELL_NAME="$(basename "${SHELL:-unknown}")"

    HAS_TMUX="no"
    TMUX_VER=""
    if command -v tmux &>/dev/null; then
        HAS_TMUX="yes"
        TMUX_VER="$(tmux -V 2>/dev/null | awk '{print $2}' || echo "unknown")"
    fi

    HAS_GIT="no"
    GIT_VER=""
    if command -v git &>/dev/null; then
        HAS_GIT="yes"
        # `git version 2.43.0` -> third whitespace-separated field.
        # awk over cut so a future format with extra prefix tokens
        # doesn't shift the field index unexpectedly.
        GIT_VER="$(git --version 2>/dev/null | awk '{print $3}' || echo "unknown")"
    fi

    HAS_CLAUDE="no"
    CLAUDE_VER=""
    if command -v claude &>/dev/null; then
        HAS_CLAUDE="yes"
        # `claude --version` emits e.g. `2.1.139 (Claude Code)` - take
        # the first field. Trim to be defensive against future prefix.
        CLAUDE_VER="$(claude --version 2>/dev/null | awk '{print $1}' || echo "unknown")"
    fi
}

tricorder_scan() {
    echo -e "  ${DIM}Press any key to begin the scan (space to skip animations)...${RESET}"
    # IFS= is critical: default IFS strips space so `read -rsn1 key` puts
    # an empty string in $key when the user presses space - the space-to-
    # skip branch then never fires. This was silently broken for ~150
    # iterations because THEDOC_TEST_SKIP_TYPING=1 masked it in smoke
    # tests; real users mashing space saw nothing happen.
    IFS= read -rsn1 key
    echo ""
    # Gap-after-action ack so space-to-skip is visibly confirmed (mirrors
    # the structure-explainer prompt below).
    if [[ "$key" == " " ]]; then
        SKIP_TYPING=1
        echo -e "  ${DIM}Animations disabled.${RESET}"
        echo ""
    fi

    # Platform name
    local platform_display
    case "$PLATFORM" in
        linux-wsl2)       platform_display="Linux (WSL2 on Windows)" ;;
        linux)            platform_display="Linux" ;;
        macos)            platform_display="macOS" ;;
        windows-gitbash)  platform_display="Windows (Git Bash)" ;;
        *)                platform_display="$PLATFORM" ;;
    esac

    local scan_prefix="  ${CYAN}[scan]${RESET} "

    echo -ne "${scan_prefix}Detecting platform..."
    _dramatic_sleep 0.3
    echo -e " ${BOLD}${platform_display}${RESET}"

    echo -ne "${scan_prefix}Shell..."
    _dramatic_sleep 0.2
    echo -e " ${BOLD}${SHELL_NAME}${RESET}"

    echo -ne "${scan_prefix}tmux..."
    _dramatic_sleep 0.2
    if [ "$HAS_TMUX" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET} (${TMUX_VER})"
    else
        echo -e " ${YELLOW}not found${RESET}"
    fi

    echo -ne "${scan_prefix}git..."
    _dramatic_sleep 0.2
    if [ "$HAS_GIT" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET} (${GIT_VER})"
    else
        echo -e " ${RED}not found${RESET} (required)"
    fi

    echo -ne "${scan_prefix}claude..."
    _dramatic_sleep 0.2
    if [ "$HAS_CLAUDE" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET} (${CLAUDE_VER})"
    else
        echo -e " ${YELLOW}not found${RESET}"
    fi

    echo ""
    _dramatic_sleep 0.3
    typeit "Good. Vitals look stable."
    echo ""
}

# ── Projects folder detection ──────────────────────────────────────
detect_projects_dirs() {
    CANDIDATE_DIRS=()
    CANDIDATE_COUNTS=()

    # Home directory paths
    local search_paths=(
        "$HOME/GitHub"
        "$HOME/projects"
        "$HOME/repos"
        "$HOME/Claude Projects"
        "$HOME/code"
        "$HOME/workspace"
        "$HOME/dev"
    )

    # On WSL, also scan Windows drives
    if [ "$IS_WSL" = "yes" ]; then
        # Find available Windows drives
        for drive in /mnt/[a-z]; do
            [ -d "$drive" ] || continue
            local letter="${drive##*/}"

            # Scan all user home directories on each drive
            if [ -d "$drive/Users" ]; then
                for userdir in "$drive/Users"/*/; do
                    [ -d "$userdir" ] || continue
                    local username="$(basename "$userdir")"
                    # Skip system users
                    [[ "$username" == "Public" || "$username" == "Default" || "$username" == "Default User" || "$username" == "All Users" ]] && continue

                    search_paths+=(
                        "${userdir}GitHub"
                        "${userdir}projects"
                        "${userdir}repos"
                        "${userdir}Claude Projects"
                        "${userdir}code"
                        "${userdir}workspace"
                        "${userdir}dev"
                        "${userdir}Documents/GitHub"
                        "${userdir}Documents/projects"
                        "${userdir}source/repos"
                    )
                done
            fi

            # Also check drive root
            search_paths+=(
                "$drive/GitHub"
                "$drive/projects"
                "$drive/repos"
                "$drive/code"
            )
        done
    fi

    local scan_prefix="  ${CYAN}[scan]${RESET} "

    for dir in "${search_paths[@]}"; do
        if [ -d "$dir" ]; then
            local count
            # tr strips BSD wc's leading whitespace so the display stays clean on macOS
            count=$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
            # Skip empty folders
            [ "$count" -eq 0 ] && continue
            CANDIDATE_DIRS+=("$dir")
            CANDIDATE_COUNTS+=("$count")
            local short
            short=$(short_path "$dir")
            # Singular/plural for grammar nit; menu render below already
            # does this, the scan-output line lagged.
            local word="folders"
            [ "$count" -eq 1 ] && word="folder"
            echo -e "${scan_prefix}Found ${BOLD}${short}/${RESET} (${count} ${word})"
            _dramatic_sleep 0.15
        fi
    done
}

prompt_projects_dir() {
    echo ""
    typeit "Now I need to find where you keep your projects."
    echo ""
    typeit "Most people have a folder where each subfolder is a"
    typeit "separate project or agent workspace."
    typeit "Some call it \"GitHub\", others call it"
    typeit "\"Claude Projects\" or just \"projects\"."
    echo ""
    typeit "Let me scan your drives..."
    echo ""

    detect_projects_dirs

    if [ ${#CANDIDATE_DIRS[@]} -eq 0 ]; then
        echo -e "  ${CYAN}[scan]${RESET} ${YELLOW}No project folders found.${RESET}"
    fi

    echo ""
    _dramatic_sleep 0.3
    typeit "Scan complete."
    echo ""

    # Build the menu
    local options=()
    for i in "${!CANDIDATE_DIRS[@]}"; do
        local dir="${CANDIDATE_DIRS[$i]}"
        local count="${CANDIDATE_COUNTS[$i]}"
        local short
        short=$(short_path "$dir")
        if [ "$count" -eq 1 ]; then
            options+=("${short}/  (${count} folder)")
        else
            options+=("${short}/  (${count} folders)")
        fi
    done
    options+=("Browse to a folder")
    options+=("Type a path")

    local browse_idx=${#CANDIDATE_DIRS[@]}
    local custom_idx=$(( ${#CANDIDATE_DIRS[@]} + 1 ))

    prompt_choice "Which one is your projects folder?" "${options[@]}"
    local idx=$CHOICE_IDX

    # Browse to a folder
    if [ "$idx" -eq "$browse_idx" ]; then
        browse_for_folder
        return
    fi

    # Type a path - re-prompts on empty / mkdir failure instead of aborting,
    # so a typo or permission slip doesn't kick the user back to square one.
    if [ "$idx" -eq "$custom_idx" ]; then
        while true; do
            echo ""
            read -rp "  Enter the full path: " custom_path
            custom_path="${custom_path/#\~/$HOME}"
            # Trim leading/trailing whitespace
            custom_path="$(echo "$custom_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            # Strip a single trailing slash so "$PROJECTS_DIR/$x" doesn't
            # produce double slashes in later messages/paths. Safe even on
            # "/" (the test below skips an empty-after-strip, but / is its
            # own root and shouldn't be picked anyway).
            if [ "${#custom_path}" -gt 1 ]; then
                custom_path="${custom_path%/}"
            fi
            if [ -z "$custom_path" ]; then
                echo -e "  ${YELLOW}Path can't be empty.${RESET}"
                continue
            fi
            # Require an absolute path. A relative path like '.' or
            # '../projects' would resolve against whatever cwd setup.sh
            # happened to launch from, then get saved literally to state -
            # so 'thedoc list' from a different cwd would point at the
            # wrong place. Force the user to be explicit.
            case "$custom_path" in
                /*) ;;
                *)
                    echo -e "  ${YELLOW}Path must be absolute (start with /).${RESET}"
                    echo -e "  ${DIM}Example: /home/you/GitHub${RESET}"
                    continue
                    ;;
            esac
            if [ ! -d "$custom_path" ]; then
                echo ""
                read -rp "  That folder doesn't exist. Create it? [Y/n] " create_it
                if [[ "$create_it" =~ ^[Nn] ]]; then
                    # User said no - re-ask for path rather than aborting outright.
                    # Ack the decline so the re-prompt below doesn't appear out
                    # of nowhere (gap-after-action heuristic: every Y/n decision
                    # gets a visible confirmation line).
                    echo -e "  ${DIM}OK - type a different path.${RESET}"
                    continue
                fi
                if ! mkdir -p "$custom_path" 2>/dev/null; then
                    echo -e "  ${RED}Failed to create $(short_path "$custom_path").${RESET}"
                    echo -e "  ${DIM}Check permissions or try a different path.${RESET}"
                    continue
                fi
                # short_path so a $HOME-relative typed path renders as ~/foo
                # to match the surrounding messages (line 1138 + the "Your
                # doctors will live in: ${short}/" line below). Without it
                # the user sees the full /home/<user>/... here and the
                # ~-prefixed form everywhere else.
                echo -e "  ${GREEN}Created${RESET} $(short_path "$custom_path")"
            fi
            PROJECTS_DIR="$custom_path"
            return
        done
    fi

    PROJECTS_DIR="${CANDIDATE_DIRS[$idx]}"
}

# ── Folder browser ─────────────────────────────────────────────────
browse_for_folder() {
    local current="$HOME"

    # On WSL, start at /mnt so they can see all drives
    if [ "$IS_WSL" = "yes" ]; then
        current="/mnt"
    fi

    while true; do
        echo ""
        local short
        short=$(short_path "$current")

        # List subdirectories, skip hidden. Dropped GNU-only `-readable`;
        # find silently skips unreadable dirs on its own.
        local dirs=()
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$current" -maxdepth 1 -mindepth 1 -type d -not -name '.*' 2>/dev/null | sort | head -50)

        # Build options: directories + navigation actions.
        # Guard the iteration: bash 3.2 (macOS) errors on empty-array expansion under `set -u`.
        local options=()
        if [ "${#dirs[@]}" -gt 0 ]; then
            for d in "${dirs[@]}"; do
                local name="$(basename "$d")"
                local subcount
                subcount=$(find "$d" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
                if [ "$subcount" -eq 1 ]; then
                    options+=("${name}/  (1 folder)")
                elif [ "$subcount" -gt 0 ]; then
                    options+=("${name}/  (${subcount} folders)")
                else
                    options+=("${name}/")
                fi
            done
        fi
        local dir_count=${#dirs[@]}
        options+=("--- Select THIS folder (${short}/) ---")
        options+=("--- Up one level ---")
        options+=("--- Cancel ---")

        prompt_choice "Browsing: ${short}/" "${options[@]}"
        local idx=$CHOICE_IDX

        if [ "$idx" -eq "$dir_count" ]; then
            # Select this folder
            PROJECTS_DIR="$current"
            return
        elif [ "$idx" -eq $((dir_count + 1)) ]; then
            # Up one level
            current="$(dirname "$current")"
        elif [ "$idx" -eq $((dir_count + 2)) ]; then
            # Cancel
            echo -e "  ${DIM}Aborting.${RESET}"
            exit 0
        elif [ "$idx" -lt "$dir_count" ]; then
            # Navigate into selected directory
            current="${dirs[$idx]}"
        fi
    done
}

print_structure_explainer() {
    local short
    short=$(short_path "$PROJECTS_DIR")
    echo ""
    # Split into sentence + indented path. With long typed paths,
    # interpolating ${short} on the same line blows past 80 cols and the
    # awk wrap drops the path on its own flush-left line - the sentence
    # then looks like it got truncated. Hanging-indent the path explicitly.
    typeit "Got it. Your doctors will live in:"
    typeit "${short}/" 0.008 "    "
    echo ""
    typeit "Here's how thedoc works:"
    typeit "- This framework (thedoc) stays where you cloned it"
    # Use a generic example to keep this bullet short. Inlining ${short}
    # blew past 80 cols when the user typed a long absolute path - the
    # awk wrap continued flush-left at the typeit-prefix level, breaking
    # the bullet visually. The "Got it. Your doctors will live in <X>/"
    # line above already echoes the chosen path.
    typeit "- Each doctor gets its own folder (e.g. claude-code-doctor/)"
    typeit "- The doctor folder has a CLAUDE.md (your personal config)"
    # typeit's awk word-wrap splits on whitespace and squashes empty tokens,
    # so leading spaces inside the message get stripped. Use the prefix arg
    # to get a 4-space hanging indent that survives the wrap.
    typeit "and a DOCTOR.md (shared diagnostic instructions)" 0.008 "    "
    typeit "- You update thedoc with 'thedoc update' - your configs are never overwritten"
    echo ""
    echo -e "  ${DIM}Press any key to continue (space to skip animations)...${RESET}"
    # IFS= so space is captured (see tricorder_scan note).
    IFS= read -rsn1 key
    echo ""
    # Gap-after-action heuristic: a deliberate space-to-skip needs visible
    # ack, otherwise the user can't tell whether their keystroke registered
    # as "skip" or just "continue" - and might mash space again at the next
    # prompt thinking it didn't work.
    if [[ "$key" == " " ]]; then
        SKIP_TYPING=1
        echo -e "  ${DIM}Animations disabled.${RESET}"
        echo ""
    fi
}

# ── Doctor types ────────────────────────────────────────────────────
DOCTOR_TYPES=("Claude Code" "OpenClaw" "Gemini CLI (not yet supported)")
DOCTOR_SLUGS=("claude-code" "openclaw" "gemini")

# ── Engine types ────────────────────────────────────────────────────
ENGINE_TYPES=("Claude Code" "OpenClaw (not yet supported)" "Gemini CLI (not yet supported)")
ENGINE_SLUGS=("claude-code" "openclaw" "gemini")

# ── Setup modes ─────────────────────────────────────────────────────
SETUP_MODES=("Quick - generate a starter config, refine later" "Full - interactive audit of your current setup")
SETUP_SLUGS=("quick" "full")

# ── Main ────────────────────────────────────────────────────────────

# Always detect platform
detect_platform

# Load saved state (if returning user)
load_state

# Re-bootstrap shortcut: a user who pastes the bootstrap one-liner again
# (THEDOC_BOOTSTRAP_DIR set + state file already exists) should get the
# framework UPDATED in place, not orphaned in $TMPDIR. The pre-iter-100
# behavior gated the entire bootstrap branch on `is_first_run`, so on
# re-paste the clone stayed in TMP and nothing visible happened.
#
# Two sub-cases for "returning user pastes bootstrap again":
#   1. installed framework at $PROJECTS_DIR/thedoc still exists - update in place
#   2. user deleted the framework dir but state still points at the projects
#      dir - re-install (move temp -> projects/thedoc) instead of orphaning
# Both exit 0 before the wizard runs (the user pasted to update/re-install,
# not to create another instance).
if [ -n "${THEDOC_BOOTSTRAP_DIR:-}" ] && [ -d "${THEDOC_BOOTSTRAP_DIR:-}" ] && \
   ! is_first_run && [ -n "${PROJECTS_DIR:-}" ] && [ -d "$PROJECTS_DIR" ]; then
    THEDOC_FINAL="$PROJECTS_DIR/thedoc"
    echo ""
    if [ -d "$THEDOC_FINAL" ]; then
        echo "  Updating thedoc at $(short_path "$THEDOC_FINAL")..."
        cp -rf "$THEDOC_BOOTSTRAP_DIR/"* "$THEDOC_FINAL/" 2>/dev/null || true
        cp -rf "$THEDOC_BOOTSTRAP_DIR/".[!.]* "$THEDOC_FINAL/" 2>/dev/null || true
        rm -rf "$THEDOC_BOOTSTRAP_DIR" 2>/dev/null || true
        echo -e "  ${GREEN}Updated${RESET} thedoc."
    else
        echo "  Re-installing thedoc at $(short_path "$THEDOC_FINAL")..."
        # cross-fs-safe move (same as first-run bootstrap branch below)
        if ! mv "$THEDOC_BOOTSTRAP_DIR" "$THEDOC_FINAL" 2>/dev/null; then
            mkdir -p "$THEDOC_FINAL"
            cp -rf "$THEDOC_BOOTSTRAP_DIR/"* "$THEDOC_FINAL/" 2>/dev/null || true
            cp -rf "$THEDOC_BOOTSTRAP_DIR/".[!.]* "$THEDOC_FINAL/" 2>/dev/null || true
            rm -rf "$THEDOC_BOOTSTRAP_DIR" 2>/dev/null || true
        fi
        echo -e "  ${GREEN}Installed${RESET} thedoc."
    fi
    echo ""
    echo -e "  ${DIM}Run 'thedoc' to create another instance, or 'thedoc open <name>' to resume.${RESET}"
    echo ""
    exit 0
fi

# Greeting
print_greeting

# First-run onboarding
if is_first_run; then
    FIRST_RUN_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Step 1: Tricorder scan
    tricorder_scan

    # Step 2: Find projects folder
    prompt_projects_dir

    # Step 3: If launched from bootstrap, move thedoc from temp to projects folder
    if [ -n "${THEDOC_BOOTSTRAP_DIR:-}" ] && [ -d "${THEDOC_BOOTSTRAP_DIR:-}" ]; then
        THEDOC_FINAL="$PROJECTS_DIR/thedoc"
        echo ""
        typeit "Moving thedoc to your projects folder..."
        if [ -d "$THEDOC_FINAL" ]; then
            echo -e "  ${YELLOW}$(short_path "$THEDOC_FINAL") already exists - updating...${RESET}"
            cp -rf "$THEDOC_BOOTSTRAP_DIR/"* "$THEDOC_FINAL/" 2>/dev/null || true
            cp -rf "$THEDOC_BOOTSTRAP_DIR/".[!.]* "$THEDOC_FINAL/" 2>/dev/null || true
            # Mirror the re-bootstrap update branch and the mv-fallback below:
            # purge $THEDOC_BOOTSTRAP_DIR after the copy. Otherwise a clone
            # of the entire framework sits in /tmp until reboot or manual
            # cleanup. The mv branch below renames the dir so no leak there.
            rm -rf "$THEDOC_BOOTSTRAP_DIR" 2>/dev/null || true
        else
            # mv can fail across filesystems (tmp -> Windows drive), fall back to cp
            if ! mv "$THEDOC_BOOTSTRAP_DIR" "$THEDOC_FINAL" 2>/dev/null; then
                mkdir -p "$THEDOC_FINAL"
                cp -rf "$THEDOC_BOOTSTRAP_DIR/"* "$THEDOC_FINAL/" 2>/dev/null || true
                cp -rf "$THEDOC_BOOTSTRAP_DIR/".[!.]* "$THEDOC_FINAL/" 2>/dev/null || true
                rm -rf "$THEDOC_BOOTSTRAP_DIR" 2>/dev/null || true
            fi
        fi
        echo -e "  ${GREEN}Installed${RESET} thedoc to $(short_path "$THEDOC_FINAL")"
        SCRIPT_DIR="$THEDOC_FINAL"

        # Set up PATH in shell rc
        SHELL_RC="$HOME/.bashrc"
        if [ "$(basename "${SHELL:-}")" = "zsh" ]; then
            SHELL_RC="$HOME/.zshrc"
        fi

        # Idempotency by signature: match the install path itself (not the
        # word "thedoc" anywhere in the rc - the substring check used to
        # false-positive on unrelated lines like 'alias thedocify=...'
        # or a path containing 'thedoc' from another project).
        THEDOC_PATH_LINE="export PATH=\"$THEDOC_FINAL:\$PATH\""
        _path_added=no
        if ! grep -qF "$THEDOC_FINAL" "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# thedoc - Emergency Medical Hologram framework" >> "$SHELL_RC"
            echo "$THEDOC_PATH_LINE" >> "$SHELL_RC"
            echo -e "  ${GREEN}Added${RESET} thedoc to PATH in $(basename "$SHELL_RC")"
            _path_added=yes
        else
            # On re-bootstrap, tell the user the PATH is fine. Otherwise the
            # bootstrap branch ends abruptly after "Installed thedoc to ..."
            # and they can't tell if shell-rc wiring already worked or got
            # silently skipped.
            echo -e "  ${DIM}thedoc already on PATH in $(basename "$SHELL_RC")${RESET}"
        fi

        # Match the actual source expression rather than '.secrets' - the
        # loose substring matched harmless comments like '# my secrets'
        # or unrelated files like '.secrets.json' in other lines.
        SECRETS_LINE='[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"'
        if ! grep -qF 'source "$HOME/.secrets"' "$SHELL_RC" 2>/dev/null; then
            # When PATH wasn't added in THIS run (already there from a
            # prior bootstrap), the secrets line would otherwise jam
            # against whatever unrelated content sits at the end of the
            # rc file. Emit our own separator + comment so the user can
            # see where the line came from. When PATH WAS just added,
            # the secrets line sits naturally under the thedoc block
            # header that the PATH branch above wrote - no duplicate
            # comment needed. Mirrors setup.ps1 line 1022's behavior.
            if [ "$_path_added" = "no" ]; then
                echo "" >> "$SHELL_RC"
                echo "# thedoc - load llm-secrets" >> "$SHELL_RC"
            fi
            echo "$SECRETS_LINE" >> "$SHELL_RC"
            echo -e "  ${GREEN}Added${RESET} secrets sourcing to $(basename "$SHELL_RC")"
        else
            echo -e "  ${DIM}secrets sourcing already wired in $(basename "$SHELL_RC")${RESET}"
        fi
        unset _path_added

        export PATH="$THEDOC_FINAL:$PATH"
        echo ""
    fi

    # Step 4: Explain the structure
    print_structure_explainer
else
    # Returning user - use saved projects dir, fall back to parent of script.
    # Note the stale case explicitly so the user sees WHERE the new instance
    # will land (iter 102/103 made list/open surface this; doing the same
    # for setup so the wizard doesn't silently create an instance in the
    # wrong projects folder when state points at a deleted directory).
    _saved_projects="${PROJECTS_DIR:-}"
    if [ -z "$_saved_projects" ] || [ ! -d "$_saved_projects" ]; then
        PROJECTS_DIR="$(dirname "$SCRIPT_DIR")"
        if [ -n "$_saved_projects" ] && [ ! -d "$_saved_projects" ]; then
            echo ""
            echo -e "  ${YELLOW}Note: state's projects_dir ($(short_path "$_saved_projects")) is missing.${RESET}"
            echo -e "  ${DIM}New instances will be created in $(short_path "$PROJECTS_DIR")/ for this run.${RESET}"
            echo ""
        fi
    fi
    unset _saved_projects
fi

# ── Doctor setup flow ──────────────────────────────────────────────

prompt_choice "What is this doctor for? (which LLM harness are you looking to configure or fix?)" "${DOCTOR_TYPES[@]}"
doctor_idx=$CHOICE_IDX
doctor_slug="${DOCTOR_SLUGS[$doctor_idx]}"
doctor_name="${DOCTOR_TYPES[$doctor_idx]}"

# Check if doctor type is supported. Stub DOCTOR.md files (committed to
# reserve the slot, e.g. doctors/gemini/DOCTOR.md) carry the marker that
# is_stub() looks for - otherwise the user would be dropped into Claude
# with a useless "this doctor isn't supported yet" brain.
if is_stub "$SCRIPT_DIR/doctors/${doctor_slug}/DOCTOR.md"; then
    # Strip the "(not yet supported)" suffix from the menu name when used
    # in the status message - otherwise it reads redundantly as
    # "Gemini CLI (not yet supported) doctor templates are coming soon."
    display_name="${doctor_name% (not yet supported)}"
    echo ""
    echo -e "  ${YELLOW}${display_name} doctor templates are coming soon.${RESET}"
    echo -e "  The framework is here - contributions welcome!"
    echo -e "  See ${DIM}doctors/${doctor_slug}/${RESET} to help build it."
    echo ""
    exit 0
fi

echo ""

prompt_choice "Which LLM engine will power this doctor?" "${ENGINE_TYPES[@]}"
engine_idx=$CHOICE_IDX
engine_slug="${ENGINE_SLUGS[$engine_idx]}"
engine_name="${ENGINE_TYPES[$engine_idx]}"

# Check if the engine is actually implemented. Catches missing launchers
# AND stub launchers marked "not yet supported" via the shared is_stub()
# helper. Catching this here (before the instance directory and CLAUDE.md
# get created) avoids orphan half-instances if the user picks "no" on the
# fallback.
if is_stub "$SCRIPT_DIR/engines/${engine_slug}.sh"; then
    # Strip the "(not yet supported)" suffix - same reason as the doctor-
    # type stub branch above. "OpenClaw engine support is coming soon" reads
    # cleaner than "OpenClaw (not yet supported) engine support...".
    display_engine_name="${engine_name% (not yet supported)}"
    echo ""
    echo -e "  ${YELLOW}${display_engine_name} engine support is coming soon.${RESET}"
    echo ""
    read -rp "  Run with Claude Code instead? [Y/n] " fallback
    if [[ "$fallback" =~ ^[Nn] ]]; then
        echo -e "  ${DIM}No worries. Check back later or help build it: engines/${engine_slug}.sh${RESET}"
        exit 0
    fi
    engine_slug="claude-code"
    engine_name="Claude Code"
    # Acknowledge the swap so the next prompt ("Setup mode?") doesn't
    # come out of nowhere - the previous flow silently jumped after
    # the [Y/n] without confirming which engine got selected.
    echo -e "  ${DIM}OK - using Claude Code instead.${RESET}"
fi

echo ""

prompt_choice "Setup mode?" "${SETUP_MODES[@]}"
mode_idx=$CHOICE_IDX
setup_mode="${SETUP_SLUGS[$mode_idx]}"

echo ""

# Instance name. Validate to prevent path traversal (slashes), hidden dirs
# (leading dot), and whitespace-only nonsense that would make a valid-but-weird
# folder. Re-prompt on bad input rather than aborting.
default_instance="${doctor_slug}-doctor"
echo -e "  ${BOLD}Name for your doctor instance folder?${RESET}"
# Drop the inline path here - the structure-explainer two screens up
# already showed it on its own indented line. Inlining $(short_path) blew
# past 80 cols on long typed paths and the terminal wrapped mid-word.
echo -e "  ${DIM}Press Enter for default.${RESET}"
while true; do
    echo ""
    # IFS= prevents 'read' from stripping leading/trailing whitespace, which
    # would otherwise turn "   " input into "" - and then the ${:-default}
    # below would silently substitute the default, bypassing the empty-name
    # rejection entirely. Caught via --keep-logs on the empty-name smoke
    # scenario showing "claude-code-doctor" got created when the test
    # thought it sent whitespace and expected re-prompt.
    IFS= read -rp "  [$default_instance] > " instance_name
    instance_name="${instance_name:-$default_instance}"
    instance_name="$(echo "$instance_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$instance_name" ]; then
        echo -e "  ${YELLOW}Name can't be empty or whitespace.${RESET}"
        continue
    fi
    if [[ "$instance_name" == */* ]]; then
        echo -e "  ${YELLOW}Name can't contain '/'. Use just the folder name.${RESET}"
        continue
    fi
    if [[ "$instance_name" == .* ]]; then
        echo -e "  ${YELLOW}Name can't start with '.' (would create a hidden folder).${RESET}"
        continue
    fi
    # If the target path already exists but isn't a thedoc instance (no
    # DOCTOR.md inside), refuse to use it - we'd otherwise mix doctor files
    # into someone's unrelated project. Re-prompt for a different name.
    target="$PROJECTS_DIR/$instance_name"
    if [ -d "$target" ] && [ ! -f "$target/DOCTOR.md" ]; then
        echo -e "  ${YELLOW}$(short_path "$target") exists but isn't a thedoc instance${RESET}"
        echo -e "  ${DIM}(no DOCTOR.md inside). Pick a different name.${RESET}"
        continue
    fi
    # If target IS an existing thedoc instance, give them a chance to open
    # it OR re-pick a name without re-running the whole wizard.
    if [ -d "$target" ]; then
        echo ""
        echo -e "  ${YELLOW}$(short_path "$target") already exists as a doctor instance.${RESET}"
        read -rp "  Open existing instance? [Y/n] " open_existing
        if [[ "$open_existing" =~ ^[Nn] ]]; then
            echo -e "  ${DIM}OK - pick a different name.${RESET}"
            continue
        fi
        # Acknowledge the open so the user sees confirmation between
        # their [Y/n] answer and "Ready to launch." Without this the
        # gap looks abrupt and the user can't tell whether their Y
        # registered. Matches iter 85's engine-fallback acknowledgment.
        echo -e "  ${DIM}OK - opening existing instance.${RESET}"
    fi
    break
done

INSTANCE_DIR="$PROJECTS_DIR/$instance_name"

# At this point INSTANCE_DIR is either an existing thedoc instance the user
# agreed to open, or a name we still need to create on disk.
if [ ! -d "$INSTANCE_DIR" ]; then
    # Create instance directory
    if ! mkdir -p "$INSTANCE_DIR" 2>/dev/null; then
        # WSL may need cmd.exe to create Windows folders
        if [ "$IS_WSL" = "yes" ]; then
            win_path=$(echo "$INSTANCE_DIR" | sed 's|^/mnt/\([a-z]\)/|\U\1:\\|; s|/|\\|g')
            cmd.exe /c "mkdir \"$win_path\"" 2>/dev/null || true
        fi
        if [ ! -d "$INSTANCE_DIR" ]; then
            echo -e "  ${RED}Failed to create $(short_path "$INSTANCE_DIR")${RESET}"
            echo -e "  ${DIM}Try creating it manually and re-running.${RESET}"
            exit 1
        fi
    fi
    echo -e "  ${GREEN}Created${RESET} $(short_path "$INSTANCE_DIR")"

    # Copy DOCTOR.md into instance
    cp "$SCRIPT_DIR/doctors/${doctor_slug}/DOCTOR.md" "$INSTANCE_DIR/DOCTOR.md"
    echo -e "  ${GREEN}Copied${RESET} DOCTOR.md (${doctor_name})"

    # Symlink to framework updates. The instance folder used to also get
    # an empty `updates/` directory (in the initial release), but nothing
    # in the doctor templates or the `thedoc update` flow ever referenced
    # it - dead since day one. Removed iter 189.
    ln -sf "$SCRIPT_DIR/doctors/${doctor_slug}/updates" "$INSTANCE_DIR/.framework-updates"
    echo -e "  ${GREEN}Linked${RESET} framework updates"

    # Generate initial CLAUDE.md
    OS_NAME="$(uname -s)"
    OS_RELEASE=""
    if [ -f /etc/os-release ]; then
        OS_RELEASE="$(. /etc/os-release && echo "$PRETTY_NAME")"
    fi

    cat > "$INSTANCE_DIR/CLAUDE.md" << CLAUDEMD
# ${doctor_name} Doctor

Read DOCTOR.md for your core instructions and personality.
Everything below is this instance's personal configuration.

## Setup Info

- **Doctor type:** ${doctor_name}
- **Engine:** ${engine_name}
- **Setup mode:** ${setup_mode}
- **Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- **Framework:** ${SCRIPT_DIR}

## System

- **OS:** ${OS_NAME} ${OS_RELEASE}
- **Platform:** ${PLATFORM}
- **Shell:** ${SHELL_NAME}
- **WSL:** ${IS_WSL}
- **Home:** ${HOME}
- **Projects dir:** ${PROJECTS_DIR}

## Known Issues & Fixes

| Issue | Cause | Fix |
|---|---|---|

## Where to Save New Learnings

Add new issues and fixes to the Known Issues & Fixes table above.
CLAUDEMD

    echo -e "  ${GREEN}Generated${RESET} CLAUDE.md"

    # Create .applied-updates tracker
    touch "$INSTANCE_DIR/.applied-updates"

    # Create instance .gitignore
    cat > "$INSTANCE_DIR/.gitignore" << 'GITIGNORE'
# Framework link (local path, not portable)
.framework-updates

# Update tracker (per-user state)
.applied-updates

# Private configs
.private/
GITIGNORE

    echo -e "  ${GREEN}Created${RESET} .gitignore"
fi

echo ""
echo -e "  ${BOLD}Ready to launch.${RESET}"
echo ""

# Save state
save_state

# Test hook: when THEDOC_NO_LAUNCH is set, exit before exec'ing the engine.
# Lets automated E2E tests verify the full setup flow without spawning a real
# Claude Code (or other engine) session. The instance directory is left behind
# so the test can inspect what was created.
if [ -n "${THEDOC_NO_LAUNCH:-}" ]; then
    echo -e "  ${DIM}THEDOC_NO_LAUNCH set - skipping engine launch (test mode).${RESET}"
    echo -e "  ${DIM}Instance ready at $(short_path "$INSTANCE_DIR")${RESET}"
    echo ""
    exit 0
fi

# Launch the engine
exec "$SCRIPT_DIR/engines/${engine_slug}.sh" "$INSTANCE_DIR" "$setup_mode" "$doctor_slug"
