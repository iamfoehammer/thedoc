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
    PROMPT="Start by reading DOCTOR.md in this directory - it has your personality, instructions, and the full audit checklist. Then read CLAUDE.md to get the framework path and system info. Follow the Full Audit Checklist in DOCTOR.md step by step. Present each recommendation and let me accept or reject it."
else
    PROMPT="Start by reading DOCTOR.md in this directory - it has your personality, instructions, and setup checklist. Then read CLAUDE.md to get the framework path and system info. Follow the Quick Setup instructions in DOCTOR.md - scan everything and show me a summary, then ask what I want to configure first."
fi

cd "$INSTANCE_DIR"
exec claude "$PROMPT"
