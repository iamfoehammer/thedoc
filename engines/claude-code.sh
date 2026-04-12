#!/usr/bin/env bash
# Engine: Claude Code
# Launches a Claude Code session in the doctor instance directory.
set -euo pipefail

INSTANCE_DIR="$1"
SETUP_MODE="${2:-quick}"
DOCTOR_TYPE="${3:-claude-code}"

# Check that claude is installed
if ! command -v claude &>/dev/null; then
    echo ""
    echo "  Claude Code is not installed or not in PATH."
    echo "  Install it: npm install -g @anthropic-ai/claude-code"
    echo ""
    exit 1
fi

# Build the initial prompt based on setup mode
if [ "$SETUP_MODE" = "full" ]; then
    PROMPT="I just created this doctor instance. Run a full interactive audit of my system: check my shell, tmux config, SSH setup, existing aliases, installed tools, and current configuration. Show me what you find, compare it against the templates in DOCTOR.md, and walk me through each recommendation one at a time. Let me accept or reject each change."
else
    PROMPT="I just created this doctor instance. Do a quick scan of my system (OS, shell, tmux, SSH) and summarize what you find. Then ask me what I'd like to configure first."
fi

cd "$INSTANCE_DIR"
exec claude "$PROMPT"
