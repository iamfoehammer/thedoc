#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_DIR="$(dirname "$SCRIPT_DIR")"

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

# ── State file (tracks first-run) ──────────────────────────────────
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/doc"
STATE_FILE="$STATE_DIR/state"

is_first_run() {
    [ ! -f "$STATE_FILE" ]
}

mark_ran() {
    mkdir -p "$STATE_DIR"
    echo "first_run=$(date -Iseconds)" > "$STATE_FILE"
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

print_greeting

# Step 1: What is this doctor for?
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

# Step 2: Which LLM engine?
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

# Step 3: Setup mode
prompt_choice "Setup mode?" "${SETUP_MODES[@]}"
mode_idx=$?
setup_mode="${SETUP_SLUGS[$mode_idx]}"

echo ""

# Step 4: Instance name
default_instance="${doctor_slug}-doctor"
echo -e "  ${BOLD}Name for your doctor instance folder?${RESET}"
echo -e "  ${DIM}This will be created in $(dirname "$SCRIPT_DIR")/. Press Enter for default.${RESET}"
echo ""
read -rp "  [$default_instance] > " instance_name
instance_name="${instance_name:-$default_instance}"

INSTANCE_DIR="$GITHUB_DIR/$instance_name"

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
    SHELL_NAME="$(basename "$SHELL")"
    IS_WSL=""
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL="yes"
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
- **Shell:** ${SHELL_NAME}
- **WSL:** ${IS_WSL:-no}
- **Home:** ${HOME}
- **Projects dir:** ${GITHUB_DIR}

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

# Mark that we've run at least once
mark_ran

# Launch the engine
exec "$SCRIPT_DIR/engines/${engine_slug}.sh" "$INSTANCE_DIR" "$setup_mode" "$doctor_slug"
