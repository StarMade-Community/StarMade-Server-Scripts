#!/bin/bash
# StarMade Server Scripts — Bootstrap
# Downloads the scripts and launches the installer.
# Run with:
#   curl -fsSL https://raw.githubusercontent.com/StarMade-Community/StarMade-Server-Scripts/main/bootstrap.sh | bash

set -e

# When piped through bash (curl ... | bash), stdin is the script content rather
# than the terminal. Reconnect stdin to the terminal so read prompts work.
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    else
        echo "[ERROR] No interactive terminal available. Run this script directly instead of piping it:" >&2
        echo "        bash <(curl -fsSL https://raw.githubusercontent.com/StarMade-Community/StarMade-Server-Scripts/main/bootstrap.sh)" >&2
        exit 1
    fi
fi

REPO_URL="https://github.com/StarMade-Community/StarMade-Server-Scripts.git"
DEFAULT_INSTALL_DIR="$HOME/starmade-scripts"

echo ""
echo "=========================================="
echo "  StarMade Server Scripts — Bootstrap"
echo "=========================================="
echo ""

# --- Install git if missing ---

if ! command -v git &>/dev/null; then
    echo "[INFO]  git is not installed. Attempting to install..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
    elif command -v yum &>/dev/null; then
        sudo yum install -y git
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm git
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y git
    else
        echo "[ERROR] Could not install git automatically. Please install git and re-run:" >&2
        echo "        curl -fsSL https://raw.githubusercontent.com/StarMade-Community/StarMade-Server-Scripts/main/bootstrap.sh | bash" >&2
        exit 1
    fi
fi

# --- Choose install location ---

read -rp "  Where should the scripts be installed? [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR </dev/tty
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "[INFO]  Directory already contains a git repo — pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    if [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
        echo "[ERROR] '$INSTALL_DIR' already exists and is not empty. Choose a different location." >&2
        exit 1
    fi
    echo "[INFO]  Cloning into $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# --- Hand off to the installer ---

chmod +x "$INSTALL_DIR/install.sh"
exec "$INSTALL_DIR/install.sh"
