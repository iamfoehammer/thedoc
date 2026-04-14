#!/usr/bin/env bash
# thedoc bootstrap - one-liner installer
# curl -fsSL https://raw.githubusercontent.com/iamfoehammer/thedoc/main/bootstrap.sh | bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

REPO="https://github.com/iamfoehammer/thedoc.git"

short_path() {
    echo "$1" | sed "s|^$HOME|~|"
}

echo ""
echo -e "  ${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "  ${CYAN}║${RESET}  ${BOLD}thedoc - Emergency Medical Hologram${RESET}    ${CYAN}║${RESET}"
echo -e "  ${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${DIM}Setting up the doctor framework...${RESET}"
echo ""

# ── Check requirements ─────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    echo -e "  ${RED}git is required but not installed.${RESET}"
    echo -e "  Install it and try again."
    exit 1
fi

# ── Detect platform ────────────────────────────────────────────────
IS_WSL="no"
if grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL="yes"
fi

# ── Find projects folder ──────────────────────────────────────────
echo -e "  ${BOLD}Where do you keep your projects?${RESET}"
echo ""
echo -e "  ${DIM}This is the folder where each subfolder is a separate${RESET}"
echo -e "  ${DIM}project or agent workspace (GitHub, Claude Projects, etc.).${RESET}"
echo -e "  ${DIM}thedoc will be cloned here.${RESET}"
echo ""

# Build candidates
CANDIDATE_DIRS=()
CANDIDATE_COUNTS=()

search_paths=(
    "$HOME/GitHub"
    "$HOME/projects"
    "$HOME/repos"
    "$HOME/Claude Projects"
    "$HOME/code"
    "$HOME/workspace"
    "$HOME/dev"
)

# On WSL, scan Windows drives
if [ "$IS_WSL" = "yes" ]; then
    for drive in /mnt/[a-z]; do
        [ -d "$drive" ] || continue
        if [ -d "$drive/Users" ]; then
            for userdir in "$drive/Users"/*/; do
                [ -d "$userdir" ] || continue
                username="$(basename "$userdir")"
                [[ "$username" == "Public" || "$username" == "Default" || "$username" == "Default User" || "$username" == "All Users" ]] && continue
                search_paths+=(
                    "${userdir}GitHub"
                    "${userdir}projects"
                    "${userdir}repos"
                    "${userdir}Claude Projects"
                    "${userdir}code"
                    "${userdir}Documents/GitHub"
                )
            done
        fi
        search_paths+=("$drive/GitHub" "$drive/projects" "$drive/code")
    done
fi

for dir in "${search_paths[@]}"; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        [ "$count" -eq 0 ] && continue
        CANDIDATE_DIRS+=("$dir")
        CANDIDATE_COUNTS+=("$count")
        short=$(short_path "$dir")
        echo -e "  ${CYAN}[found]${RESET} ${BOLD}${short}/${RESET} (${count} folders)"
    fi
done

echo ""

# Build menu
options=()
for i in "${!CANDIDATE_DIRS[@]}"; do
    dir="${CANDIDATE_DIRS[$i]}"
    count="${CANDIDATE_COUNTS[$i]}"
    short=$(short_path "$dir")
    options+=("${short}/  (${count} folders)")
done
options+=("Type a different path")

echo -e "  ${BOLD}Where should I install thedoc?${RESET}"
echo ""

i=1
for opt in "${options[@]}"; do
    echo -e "    ${GREEN}[${i}]${RESET} ${opt}"
    i=$((i + 1))
done
echo ""

total=${#options[@]}
while true; do
    read -rp "  > " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
        break
    fi
    echo -e "  ${RED}Pick a number between 1 and ${total}.${RESET}"
done

idx=$((choice - 1))

if [ "$idx" -eq "${#CANDIDATE_DIRS[@]}" ]; then
    # Custom path
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
else
    PROJECTS_DIR="${CANDIDATE_DIRS[$idx]}"
fi

THEDOC_DIR="$PROJECTS_DIR/thedoc"

echo ""

# ── Clone ──────────────────────────────────────────────────────────
if [ -d "$THEDOC_DIR" ]; then
    echo -e "  ${YELLOW}$(short_path "$THEDOC_DIR") already exists.${RESET}"
    echo -e "  ${DIM}Pulling latest...${RESET}"
    git -C "$THEDOC_DIR" pull --quiet 2>/dev/null || true
else
    echo -e "  ${DIM}Cloning thedoc...${RESET}"
    git clone --quiet "$REPO" "$THEDOC_DIR"
    echo -e "  ${GREEN}Cloned to${RESET} $(short_path "$THEDOC_DIR")"
fi

# ── Set up PATH and secrets ────────────────────────────────────────
SHELL_RC="$HOME/.bashrc"
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Add PATH if not already there
THEDOC_PATH_LINE="export PATH=\"$THEDOC_DIR:\$PATH\""
if ! grep -qF "thedoc" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# thedoc - Emergency Medical Hologram framework" >> "$SHELL_RC"
    echo "$THEDOC_PATH_LINE" >> "$SHELL_RC"
    echo -e "  ${GREEN}Added${RESET} thedoc to PATH in $(basename "$SHELL_RC")"
else
    echo -e "  ${DIM}thedoc already in $(basename "$SHELL_RC")${RESET}"
fi

# Add secrets sourcing if not already there
if ! grep -qF ".secrets" "$SHELL_RC" 2>/dev/null; then
    echo '[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"' >> "$SHELL_RC"
    echo -e "  ${GREEN}Added${RESET} secrets sourcing to $(basename "$SHELL_RC")"
fi

echo ""

# ── Source and launch ──────────────────────────────────────────────
export PATH="$THEDOC_DIR:$PATH"
export THEDOC_PROJECTS_DIR="$PROJECTS_DIR"

echo -e "  ${BOLD}Installation complete.${RESET}"
echo ""
echo -e "  ${DIM}Launching the doctor...${RESET}"
echo ""
sleep 0.5

exec "$THEDOC_DIR/setup.sh"
