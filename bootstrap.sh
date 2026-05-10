#!/usr/bin/env bash
# thedoc bootstrap - one-liner installer
# bash <(curl -fsSL https://raw.githubusercontent.com/iamfoehammer/thedoc/main/bootstrap.sh)
set -euo pipefail

case "${1:-}" in
    --help|-h|help)
        cat <<'EOF'
thedoc bootstrap

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/iamfoehammer/thedoc/main/bootstrap.sh)

What it does:
  1. Clones the thedoc repo to a temp directory.
  2. Runs setup.sh from there. The wizard moves the repo to
     wherever you point it at (typically ~/GitHub/thedoc).
  3. Adds thedoc to your PATH and sources ~/.secrets in your
     shell rc, so 'thedoc' just works in new terminals.

Requirements:
  - git on PATH
  - bash 3.2+ (macOS default; any modern Linux is 4+/5+)

Manual install (no curl pipe):
  git clone https://github.com/iamfoehammer/thedoc.git ~/GitHub/thedoc
  echo 'export PATH="$HOME/GitHub/thedoc:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  thedoc
EOF
        exit 0
        ;;
esac

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
