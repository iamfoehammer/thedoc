#!/usr/bin/env bash
# thedoc bootstrap - one-liner installer
# bash <(curl -fsSL https://raw.githubusercontent.com/iamfoehammer/thedoc/main/bootstrap.sh)
set -euo pipefail

REPO="https://github.com/iamfoehammer/thedoc.git"
TMP_DIR="$(mktemp -d)/thedoc"

# Check requirements
if ! command -v git &>/dev/null; then
    echo "git is required but not installed."
    exit 1
fi

# Clone to temp
echo ""
echo "  Downloading thedoc..."
git clone --quiet "$REPO" "$TMP_DIR"
echo "  Done."
echo ""

# Hand off to setup.sh which handles everything
export THEDOC_BOOTSTRAP_DIR="$TMP_DIR"
exec "$TMP_DIR/setup.sh"
