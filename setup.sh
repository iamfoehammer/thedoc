#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

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
first_run=${FIRST_RUN_DATE:-$(date -Iseconds)}
projects_dir=${PROJECTS_DIR}
platform=${PLATFORM}
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        FIRST_RUN_DATE=$(grep -oP '(?<=^first_run=).+' "$STATE_FILE" 2>/dev/null || echo "")
        PROJECTS_DIR=$(grep -oP '(?<=^projects_dir=).+' "$STATE_FILE" 2>/dev/null || echo "")
        PLATFORM=$(grep -oP '(?<=^platform=).+' "$STATE_FILE" 2>/dev/null || echo "")
    fi
}

# ── Helpers ─────────────────────────────────────────────────────────
pick_random() {
    local arr=("$@")
    echo "${arr[$((RANDOM % ${#arr[@]}))]}"
}

# Typing effect - prints text character by character
# Press space at the "press any key" prompts to skip all future typing
SKIP_TYPING=0
typeit() {
    local text="$1"
    local delay="${2:-0.02}"
    local prefix="${3:-  }"
    printf '%s' "$prefix"
    if [ "$SKIP_TYPING" -eq 1 ]; then
        printf '%s\n' "$text"
        return
    fi
    for ((i=0; i<${#text}; i++)); do
        printf '%s' "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# Short path display
short_path() {
    echo "$1" | sed "s|^$HOME|~|"
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
        typeit "$greeting" 0.04
        echo ""
        sleep 0.5
        typeit "..." 0.3
        echo ""
        typeit "No emergency? Just a checkup? That's fine too."
        typeit "Contrary to my name, I handle everything from routine"
        typeit "configuration to catastrophic meltdowns."
        echo ""
        typeit "I'm going to need to scan your system first." 0.02
        typeit "Think of it as a routine physical." 0.02
        echo ""
        echo -e "  ${DIM}Press Enter to continue, or ${BOLD}i${RESET}${DIM} to see an image of${RESET}"
        echo -e "  ${DIM}my holographic form here in your terminal.${RESET}"
        echo ""
        read -rsn1 show_image
        if [[ "$show_image" == "i" || "$show_image" == "I" ]]; then
            echo ""
            if [ -f "$SCRIPT_DIR/thedoc.txt" ]; then
                echo -e "  ${CYAN}"
                cat "$SCRIPT_DIR/thedoc.txt"
                echo -e "  ${RESET}"
                echo ""
                echo -e "  ${DIM}The Emergency Medical Hologram, reporting for duty.${RESET}"
                echo ""
                echo -e "  ${DIM}Press any key to continue...${RESET}"
                read -rsn1
            fi
        fi
        echo ""
    else
        local quip
        quip=$(pick_random "${QUIPS[@]}")
        typeit "$quip" 0.02
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
        TMUX_VER="$(tmux -V 2>/dev/null | grep -oP '[\d.]+' || echo "unknown")"
    fi

    HAS_GIT="no"
    if command -v git &>/dev/null; then
        HAS_GIT="yes"
    fi

    HAS_CLAUDE="no"
    if command -v claude &>/dev/null; then
        HAS_CLAUDE="yes"
    fi
}

tricorder_scan() {
    echo -e "  ${DIM}Press any key to begin the scan (space to skip animations)...${RESET}"
    read -rsn1 key
    [[ "$key" == " " ]] && SKIP_TYPING=1
    echo ""

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
    sleep 0.3
    echo -e " ${BOLD}${platform_display}${RESET}"

    echo -ne "${scan_prefix}Shell..."
    sleep 0.2
    echo -e " ${BOLD}${SHELL_NAME}${RESET}"

    echo -ne "${scan_prefix}tmux..."
    sleep 0.2
    if [ "$HAS_TMUX" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET} (${TMUX_VER})"
    else
        echo -e " ${YELLOW}not found${RESET}"
    fi

    echo -ne "${scan_prefix}git..."
    sleep 0.2
    if [ "$HAS_GIT" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET}"
    else
        echo -e " ${RED}not found${RESET} (required)"
    fi

    echo -ne "${scan_prefix}claude..."
    sleep 0.2
    if [ "$HAS_CLAUDE" = "yes" ]; then
        echo -e " ${GREEN}installed${RESET}"
    else
        echo -e " ${YELLOW}not found${RESET}"
    fi

    echo ""
    sleep 0.3
    typeit "Good. Vitals look stable." 0.02
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
            count=$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            # Skip empty folders
            [ "$count" -eq 0 ] && continue
            CANDIDATE_DIRS+=("$dir")
            CANDIDATE_COUNTS+=("$count")
            local short
            short=$(short_path "$dir")
            echo -e "${scan_prefix}Found ${BOLD}${short}/${RESET} (${count} folders)"
            sleep 0.15
        fi
    done
}

prompt_projects_dir() {
    echo ""
    typeit "Now I need to find where you keep your projects." 0.02
    echo ""
    typeit "Most people have a folder where each subfolder is a" 0.02
    typeit "separate project or agent workspace." 0.02
    typeit "Some call it \"GitHub\", others call it" 0.02
    typeit "\"Claude Projects\" or just \"projects\"." 0.02
    echo ""
    typeit "Let me scan your drives..." 0.02
    echo ""

    detect_projects_dirs

    if [ ${#CANDIDATE_DIRS[@]} -eq 0 ]; then
        echo -e "  ${CYAN}[scan]${RESET} ${YELLOW}No project folders found.${RESET}"
    fi

    echo ""
    sleep 0.3
    typeit "Scan complete." 0.02
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

    # Type a path
    if [ "$idx" -eq "$custom_idx" ]; then
        echo ""
        read -rp "  Enter the full path: " custom_path
        custom_path="${custom_path/#\~/$HOME}"
        if [ ! -d "$custom_path" ]; then
            echo ""
            read -rp "  That folder doesn't exist. Create it? [Y/n] " create_it
            if [[ "$create_it" =~ ^[Nn] ]]; then
                echo -e "  ${DIM}Aborting.${RESET}"
                exit 0
            fi
            mkdir -p "$custom_path"
            echo -e "  ${GREEN}Created${RESET} $custom_path"
        fi
        PROJECTS_DIR="$custom_path"
        return
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

        # List subdirectories (only readable ones, skip hidden)
        local dirs=()
        while IFS= read -r d; do
            [ -n "$d" ] && dirs+=("$d")
        done < <(find "$current" -maxdepth 1 -mindepth 1 -type d -readable -not -name '.*' 2>/dev/null | sort | head -50)

        # Build options: directories + navigation actions
        local options=()
        for d in "${dirs[@]}"; do
            local name="$(basename "$d")"
            local subcount
            subcount=$(find "$d" -maxdepth 1 -mindepth 1 -type d -readable 2>/dev/null | wc -l)
            if [ "$subcount" -gt 0 ]; then
                options+=("${name}/  (${subcount} folders)")
            else
                options+=("${name}/")
            fi
        done
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
    typeit "Got it. Your doctors will live in ${short}/" 0.02
    echo ""
    typeit "Here's how thedoc works:" 0.02
    typeit "- This framework (thedoc) stays where you cloned it" 0.015
    typeit "- Each doctor gets its own folder, like ${short}/claude-doctor/" 0.015
    typeit "- The doctor folder has a CLAUDE.md (your personal config)" 0.015
    typeit "  and a DOCTOR.md (shared diagnostic instructions)" 0.015
    typeit "- You update thedoc with 'git pull' - your configs are never overwritten" 0.015
    echo ""
    echo -e "  ${DIM}Press any key to continue (space to skip animations)...${RESET}"
    read -rsn1 key
    [[ "$key" == " " ]] && SKIP_TYPING=1
    echo ""
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

# Greeting
print_greeting

# First-run onboarding
if is_first_run; then
    FIRST_RUN_DATE="$(date -Iseconds)"

    # Step 1: Tricorder scan
    tricorder_scan

    # Step 2: Find projects folder
    prompt_projects_dir

    # Step 3: If launched from bootstrap, move thedoc from temp to projects folder
    if [ -n "${THEDOC_BOOTSTRAP_DIR:-}" ] && [ -d "${THEDOC_BOOTSTRAP_DIR:-}" ]; then
        THEDOC_FINAL="$PROJECTS_DIR/thedoc"
        echo ""
        typeit "Moving thedoc to your projects folder..." 0.02
        if [ -d "$THEDOC_FINAL" ]; then
            echo -e "  ${YELLOW}$(short_path "$THEDOC_FINAL") already exists - updating...${RESET}"
            cp -rf "$THEDOC_BOOTSTRAP_DIR/"* "$THEDOC_FINAL/" 2>/dev/null || true
            cp -rf "$THEDOC_BOOTSTRAP_DIR/".[!.]* "$THEDOC_FINAL/" 2>/dev/null || true
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

        THEDOC_PATH_LINE="export PATH=\"$THEDOC_FINAL:\$PATH\""
        if ! grep -qF "thedoc" "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# thedoc - Emergency Medical Hologram framework" >> "$SHELL_RC"
            echo "$THEDOC_PATH_LINE" >> "$SHELL_RC"
            echo -e "  ${GREEN}Added${RESET} thedoc to PATH in $(basename "$SHELL_RC")"
        fi

        if ! grep -qF ".secrets" "$SHELL_RC" 2>/dev/null; then
            echo '[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"' >> "$SHELL_RC"
            echo -e "  ${GREEN}Added${RESET} secrets sourcing to $(basename "$SHELL_RC")"
        fi

        export PATH="$THEDOC_FINAL:$PATH"
        echo ""
    fi

    # Step 4: Explain the structure
    print_structure_explainer
else
    # Returning user - use saved projects dir, fall back to parent of script
    if [ -z "${PROJECTS_DIR:-}" ] || [ ! -d "${PROJECTS_DIR:-}" ]; then
        PROJECTS_DIR="$(dirname "$SCRIPT_DIR")"
    fi
fi

# ── Doctor setup flow ──────────────────────────────────────────────

prompt_choice "What is this doctor for? (which LLM harness are you looking to configure or fix?)" "${DOCTOR_TYPES[@]}"
doctor_idx=$CHOICE_IDX
doctor_slug="${DOCTOR_SLUGS[$doctor_idx]}"
doctor_name="${DOCTOR_TYPES[$doctor_idx]}"

# Check if doctor type is supported
if [ ! -f "$SCRIPT_DIR/doctors/${doctor_slug}/DOCTOR.md" ]; then
    echo ""
    echo -e "  ${YELLOW}${doctor_name} doctor templates are coming soon.${RESET}"
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

# Check if engine is supported
if [ ! -f "$SCRIPT_DIR/engines/${engine_slug}.sh" ]; then
    echo ""
    echo -e "  ${YELLOW}${engine_name} engine support is coming soon.${RESET}"
    echo ""
    read -rp "  Run with Claude Code instead? [Y/n] " fallback
    if [[ "$fallback" =~ ^[Nn] ]]; then
        echo -e "  ${DIM}No worries. Check back later or help build it: engines/${engine_slug}.sh${RESET}"
        exit 0
    fi
    engine_slug="claude-code"
    engine_name="Claude Code"
fi

echo ""

prompt_choice "Setup mode?" "${SETUP_MODES[@]}"
mode_idx=$CHOICE_IDX
setup_mode="${SETUP_SLUGS[$mode_idx]}"

echo ""

# Instance name
default_instance="${doctor_slug}-doctor"
echo -e "  ${BOLD}Name for your doctor instance folder?${RESET}"
echo -e "  ${DIM}This will be created in $(short_path "$PROJECTS_DIR")/. Press Enter for default.${RESET}"
echo ""
read -rp "  [$default_instance] > " instance_name
instance_name="${instance_name:-$default_instance}"

INSTANCE_DIR="$PROJECTS_DIR/$instance_name"

# Check if instance already exists
if [ -d "$INSTANCE_DIR" ]; then
    echo ""
    echo -e "  ${YELLOW}$(short_path "$INSTANCE_DIR") already exists.${RESET}"
    read -rp "  Open existing instance? [Y/n] " open_existing
    if [[ "$open_existing" =~ ^[Nn] ]]; then
        echo -e "  ${DIM}Aborting.${RESET}"
        exit 0
    fi
else
    # Create instance directory
    if ! mkdir -p "$INSTANCE_DIR" 2>/dev/null; then
        # WSL may need cmd.exe to create Windows folders
        if [ "$IS_WSL" = "yes" ]; then
            local win_path
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

    # Create updates dir in instance
    mkdir -p "$INSTANCE_DIR/updates"

    # Symlink back to framework updates
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
- **Created:** $(date -Iseconds)
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

# Launch the engine
exec "$SCRIPT_DIR/engines/${engine_slug}.sh" "$INSTANCE_DIR" "$setup_mode" "$doctor_slug"
