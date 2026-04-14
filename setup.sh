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
    echo -e "  ${BOLD}${greeting}${RESET}"
    echo ""

    if is_first_run; then
        echo -e "  ${DIM}...${RESET}"
        echo ""
        echo -e "  No emergency? Just a checkup? That's fine too."
        echo -e "  Contrary to my name, I handle everything from routine"
        echo -e "  configuration to catastrophic meltdowns."
        echo ""
        echo -e "  Let's get started."
        echo ""
    else
        local quip
        quip=$(pick_random "${QUIPS[@]}")
        echo -e "  ${DIM}${quip}${RESET}"
        echo ""
    fi
}

prompt_choice() {
    local prompt_text="$1"
    shift
    local options=("$@")

    echo -e "  ${BOLD}${prompt_text}${RESET}"
    echo ""

    local i=1
    for opt in "${options[@]}"; do
        echo -e "    ${GREEN}[${i}]${RESET} ${opt}"
        ((i++))
    done
    echo ""

    local choice
    while true; do
        read -rp "  > " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            return $((choice - 1))
        fi
        echo -e "  ${RED}Pick a number between 1 and ${#options[@]}.${RESET}"
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
        # Git Bash or MSYS on Windows
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

print_platform_info() {
    echo -e "  ${DIM}Scanning your system...${RESET}"
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

    echo -e "  Platform:    ${BOLD}${platform_display}${RESET}"
    echo -e "  Shell:       ${BOLD}${SHELL_NAME}${RESET}"

    if [ "$HAS_TMUX" = "yes" ]; then
        echo -e "  tmux:        ${GREEN}installed${RESET} (${TMUX_VER})"
    else
        echo -e "  tmux:        ${YELLOW}not found${RESET}"
    fi

    if [ "$HAS_GIT" = "yes" ]; then
        echo -e "  git:         ${GREEN}installed${RESET}"
    else
        echo -e "  git:         ${RED}not found${RESET} (required)"
    fi

    if [ "$HAS_CLAUDE" = "yes" ]; then
        echo -e "  claude:      ${GREEN}installed${RESET}"
    else
        echo -e "  claude:      ${YELLOW}not found${RESET}"
    fi

    echo ""
}

# ── Projects folder detection ──────────────────────────────────────
detect_projects_dirs() {
    CANDIDATE_DIRS=()
    CANDIDATE_COUNTS=()

    local search_paths=(
        "$HOME/GitHub"
        "$HOME/projects"
        "$HOME/repos"
        "$HOME/Claude Projects"
        "$HOME/code"
        "$HOME/workspace"
        "$HOME/dev"
    )

    for dir in "${search_paths[@]}"; do
        if [ -d "$dir" ]; then
            local count
            count=$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            CANDIDATE_DIRS+=("$dir")
            CANDIDATE_COUNTS+=("$count")
        fi
    done
}

prompt_projects_dir() {
    echo -e "  ${BOLD}Where do you keep your AI projects?${RESET}"
    echo ""
    echo -e "  ${DIM}Most people have a folder where each subfolder is a separate${RESET}"
    echo -e "  ${DIM}project or agent workspace. Some call it \"GitHub\", others${RESET}"
    echo -e "  ${DIM}call it \"Claude Projects\" or just \"projects\".${RESET}"
    echo ""

    detect_projects_dirs

    local options=()
    for i in "${!CANDIDATE_DIRS[@]}"; do
        local dir="${CANDIDATE_DIRS[$i]}"
        local count="${CANDIDATE_COUNTS[$i]}"
        local short
        short=$(echo "$dir" | sed "s|^$HOME|~|")
        if [ "$count" -eq 1 ]; then
            options+=("${short}/  (${count} folder found)")
        else
            options+=("${short}/  (${count} folders found)")
        fi
    done
    options+=("Enter a custom path")

    echo -e "  ${DIM}I found these on your system:${RESET}"
    echo ""

    local i=1
    for opt in "${options[@]}"; do
        echo -e "    ${GREEN}[${i}]${RESET} ${opt}"
        ((i++))
    done
    echo ""

    local choice
    while true; do
        read -rp "  > " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            break
        fi
        echo -e "  ${RED}Pick a number between 1 and ${#options[@]}.${RESET}"
    done

    local idx=$((choice - 1))

    # Custom path
    if [ "$idx" -eq "${#CANDIDATE_DIRS[@]}" ]; then
        echo ""
        read -rp "  Enter the full path: " custom_path
        # Expand ~ if present
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
    else
        PROJECTS_DIR="${CANDIDATE_DIRS[$idx]}"
    fi

    echo ""
}

print_structure_explainer() {
    local short
    short=$(echo "$PROJECTS_DIR" | sed "s|^$HOME|~|")
    echo -e "  ${GREEN}Got it.${RESET} Your doctors will live in ${BOLD}${short}/${RESET}"
    echo ""
    echo -e "  ${DIM}Here's how thedoc works:${RESET}"
    echo -e "  - This framework (thedoc) stays where you cloned it"
    echo -e "  - Each doctor gets its own folder, like ${short}/claude-doctor/"
    echo -e "  - The doctor folder has a CLAUDE.md (your personal config)"
    echo -e "    and a DOCTOR.md (shared diagnostic instructions)"
    echo -e "  - You update thedoc with 'git pull' - your configs are never overwritten"
    echo ""
    read -rp "  Press Enter to continue... "
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

    # Step 1: Show what we detected
    print_platform_info

    # Step 2: Where are your projects?
    prompt_projects_dir

    # Step 3: Explain the structure
    print_structure_explainer
else
    # Returning user - use saved projects dir, fall back to parent of script
    if [ -z "${PROJECTS_DIR:-}" ] || [ ! -d "${PROJECTS_DIR:-}" ]; then
        PROJECTS_DIR="$(dirname "$SCRIPT_DIR")"
    fi
fi

# ── Existing doctor setup flow ─────────────────────────────────────

# Step 4: What is this doctor for?
prompt_choice "What is this doctor for?" "${DOCTOR_TYPES[@]}"
doctor_idx=$?
doctor_slug="${DOCTOR_SLUGS[$doctor_idx]}"
doctor_name="${DOCTOR_TYPES[$doctor_idx]}"

# Check if doctor type is supported (has a DOCTOR.md)
if [ ! -f "$SCRIPT_DIR/doctors/${doctor_slug}/DOCTOR.md" ]; then
    echo ""
    echo -e "  ${YELLOW}${doctor_name} doctor templates are coming soon.${RESET}"
    echo -e "  The framework is here - contributions welcome!"
    echo -e "  See ${DIM}doctors/${doctor_slug}/${RESET} to help build it."
    echo ""
    echo -e "  ${DIM}If you'd like to use Claude Code as the engine to build"
    echo -e "  this doctor type interactively, re-run and pick an available option.${RESET}"
    echo ""
    exit 0
fi

echo ""

# Step 5: Which LLM engine?
prompt_choice "Which LLM engine will power this doctor?" "${ENGINE_TYPES[@]}"
engine_idx=$?
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

# Step 6: Setup mode
prompt_choice "Setup mode?" "${SETUP_MODES[@]}"
mode_idx=$?
setup_mode="${SETUP_SLUGS[$mode_idx]}"

echo ""

# Step 7: Instance name
default_instance="${doctor_slug}-doctor"
echo -e "  ${BOLD}Name for your doctor instance folder?${RESET}"
echo -e "  ${DIM}This will be created in ${PROJECTS_DIR}/. Press Enter for default.${RESET}"
echo ""
read -rp "  [$default_instance] > " instance_name
instance_name="${instance_name:-$default_instance}"

INSTANCE_DIR="$PROJECTS_DIR/$instance_name"

# Check if instance already exists
if [ -d "$INSTANCE_DIR" ]; then
    echo ""
    echo -e "  ${YELLOW}$INSTANCE_DIR already exists.${RESET}"
    read -rp "  Open existing instance? [Y/n] " open_existing
    if [[ "$open_existing" =~ ^[Nn] ]]; then
        echo -e "  ${DIM}Aborting.${RESET}"
        exit 0
    fi
else
    # Create instance directory
    mkdir -p "$INSTANCE_DIR"
    echo -e "  ${GREEN}Created${RESET} $INSTANCE_DIR"

    # Copy DOCTOR.md into instance
    cp "$SCRIPT_DIR/doctors/${doctor_slug}/DOCTOR.md" "$INSTANCE_DIR/DOCTOR.md"
    echo -e "  ${GREEN}Copied${RESET} DOCTOR.md (${doctor_name})"

    # Create updates dir in instance
    mkdir -p "$INSTANCE_DIR/updates"

    # Symlink back to framework updates so git pull brings new ones
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

# Save state (first run or update)
save_state

# Launch the engine
exec "$SCRIPT_DIR/engines/${engine_slug}.sh" "$INSTANCE_DIR" "$setup_mode" "$doctor_slug"
