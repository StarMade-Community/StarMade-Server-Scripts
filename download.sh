#!/bin/bash
# Downloads a fresh StarMade server and optionally starts it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

BRANCH=${1:-${UPDATE_BRANCH:-release}}
TEMP_DIR="/tmp/starmade-download"

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
mkdir -p "$TEMP_DIR"

LATEST=$(wget -q "$BUILD_URL/" -O - | grep -oP 'href="starmade-build_[^"]+\.zip"' | sed 's/href="//;s/"//' | sort | tail -1)

if [ -z "$LATEST" ]; then
    echo "Could not find latest build at $BUILD_URL"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Latest build: $LATEST"
wget -q --show-progress "$BUILD_URL/$LATEST" -O "$TEMP_DIR/starmade.zip"

if [ $? -ne 0 ]; then
    echo "Download failed!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "[2/3] Extracting to $STARMADE_DIR..."
unzip -qo "$TEMP_DIR/starmade.zip" -d "$STARMADE_DIR"
rm -rf "$TEMP_DIR"

echo "$BRANCH" > "$STARMADE_DIR/.current_branch"

echo "[3/3] Done!"
echo ""
echo "  Server files: $STARMADE_DIR"
echo "  Branch:       $BRANCH"

if [ -f "$STARMADE_DIR/StarMade.jar" ]; then
    SIZE=$(du -sh "$STARMADE_DIR" | cut -f1)
    echo "  Size:         $SIZE"
    echo ""
    read -rp "Start the server now? (y/n): " START_NOW
    if [ "$START_NOW" == "y" ]; then
        exec "$SCRIPT_DIR/start.sh"
    fi
else
    echo ""
    echo "Warning: StarMade.jar was not found after extraction."
    echo "The archive structure may have changed — check $STARMADE_DIR manually."
fi
