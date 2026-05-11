#!/usr/bin/env bash
# Engine: Claude Code
# Launches a Claude Code session in the doctor instance directory.
#
# Usage:
#   engines/claude-code.sh <INSTANCE_DIR> [SETUP_MODE] [DOCTOR_TYPE]
#
# Normally invoked by setup.sh, not directly. Setup mode is 'quick' or
# 'full' (controls the launch prompt). DOCTOR_TYPE is the slug for
# logging only.
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "" >&2
    echo "  Usage: $(basename "$0") <INSTANCE_DIR> [SETUP_MODE] [DOCTOR_TYPE]" >&2
    echo "  This launcher is normally invoked by setup.sh, not directly." >&2
    echo "" >&2
    exit 2
fi

INSTANCE_DIR="$1"
SETUP_MODE="${2:-quick}"
DOCTOR_TYPE="${3:-claude-code}"

if [ ! -d "$INSTANCE_DIR" ]; then
    echo "" >&2
    echo "  Instance directory does not exist: $INSTANCE_DIR" >&2
    echo "" >&2
    exit 2
fi

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
