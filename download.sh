#!/bin/bash
# Downloads a fresh StarMade server and optionally starts it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load .env if present. During first-time install it may not exist yet, in which
# case STARMADE_DIR/UPDATE_BRANCH are expected to come from the environment.
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

BRANCH=${1:-${UPDATE_BRANCH:-release}}

if [ -z "$STARMADE_DIR" ]; then
    echo "STARMADE_DIR is not set. Copy .env.example to .env (or run install.sh) first."
    exit 1
fi

# Private temp dir — avoids permission clashes with a leftover shared /tmp path
TEMP_DIR="$(mktemp -d)"

if [ "$BRANCH" == "release" ]; then
    BUILD_URL="http://files-origin.star-made.org/build"
elif [ "$BRANCH" == "dev" ]; then
    BUILD_URL="http://files-origin.star-made.org/build/dev"
elif [ "$BRANCH" == "pre" ]; then
    BUILD_URL="http://files-origin.star-made.org/build/pre"
else
    echo "Unknown branch '$BRANCH'. Use 'release', 'dev', or 'pre'."
    exit 1
fi

echo "=== StarMade Download Script ($BRANCH branch) ==="
echo ""

# Guard against overwriting an existing installation
if [ -f "$STARMADE_DIR/StarMade.jar" ]; then
    echo "StarMade.jar already exists in $STARMADE_DIR"
    read -rp "Overwrite the existing installation? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Aborting."
        exit 0
    fi
fi

mkdir -p "$STARMADE_DIR"

echo "[1/3] Downloading latest $BRANCH build..."

# Fetch the build index and find the latest zip (portable: no wget, no grep -P)
LATEST=$(curl -fsSL "$BUILD_URL/" | grep -o 'href="starmade-build_[^"]*\.zip"' | sed 's/href="//;s/"//' | sort | tail -1)

if [ -z "$LATEST" ]; then
    echo "Could not find latest build at $BUILD_URL"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Latest build: $LATEST"
if command -v aria2c >/dev/null 2>&1; then
    # Multi-connection download — the build server caps per-connection (~9 MB/s)
    # but not per-IP, so parallel splits are several times faster.
    aria2c -x 8 -s 8 -k 25M \
        --connect-timeout=30 --max-tries=3 --retry-wait=5 \
        --console-log-level=warn --summary-interval=5 \
        -d "$TEMP_DIR" -o starmade.zip "$BUILD_URL/$LATEST"
else
    echo "  (tip: install 'aria2' for much faster multi-connection downloads)"
    curl -fL --progress-bar \
        --connect-timeout 30 \
        --retry 3 --retry-delay 5 \
        --speed-time 60 --speed-limit 1024 \
        "$BUILD_URL/$LATEST" -o "$TEMP_DIR/starmade.zip"
fi

if [ $? -ne 0 ]; then
    echo "Download failed!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "[2/3] Extracting to $STARMADE_DIR..."
unzip -qo "$TEMP_DIR/starmade.zip" -d "$TEMP_DIR/extracted"

# The zip may contain a top-level directory (e.g. StarMade/). If so, move its
# contents up so files land directly in STARMADE_DIR instead of a subfolder.
INNER_DIR="$TEMP_DIR/extracted"
ENTRIES=("$INNER_DIR"/*)
if [ ${#ENTRIES[@]} -eq 1 ] && [ -d "${ENTRIES[0]}" ]; then
    INNER_DIR="${ENTRIES[0]}"
fi

rsync -a "$INNER_DIR/" "$STARMADE_DIR/"
rm -rf "$TEMP_DIR"

echo "$BRANCH" > "$STARMADE_DIR/.current_branch"

# Save game version extracted from the build filename (e.g. starmade-build_0.199.651.zip → 0.199.651)
GAME_VERSION=$(echo "$LATEST" | sed 's/starmade-build_//;s/\.zip$//')
if [ -n "$GAME_VERSION" ]; then
    echo "$GAME_VERSION" > "$STARMADE_DIR/.game_version"
    echo "  Version:      $GAME_VERSION"
fi

echo "[3/3] Done!"
echo ""
echo "  Server files: $STARMADE_DIR"
echo "  Branch:       $BRANCH"

if [ -f "$STARMADE_DIR/StarMade.jar" ]; then
    SIZE=$(du -sh "$STARMADE_DIR" | cut -f1)
    echo "  Size:         $SIZE"
else
    echo ""
    echo "Warning: StarMade.jar was not found after extraction."
    echo "The archive structure may have changed — check $STARMADE_DIR manually."
fi
