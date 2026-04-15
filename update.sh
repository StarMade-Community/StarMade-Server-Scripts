#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

EXCLUDES_FILE="$STARMADE_DIR/update-excludes.txt"
DATE=$(date +%Y%m%d_%H%M%S)
BRANCH=${1:-${UPDATE_BRANCH:-dev}}
TEMP_DIR="/tmp/starmade-update"

if [ "$BRANCH" == "release" ]; then
    BUILD_URL="http://files-origin.star-made.org/build"
    echo "=== StarMade Update Script (Release Branch) ==="
elif [ "$BRANCH" == "dev" ]; then
    BUILD_URL="http://files-origin.star-made.org/build/dev"
    echo "=== StarMade Update Script (Dev Branch) ==="
elif [ "$BRANCH" == "pre" ]; then
    BUILD_URL="http://files-origin.star-made.org/build/pre"
    echo "=== StarMade Update Script (Pre Branch) ==="
else
    echo "Unknown branch '$BRANCH'. Use 'release', 'dev', or 'pre'."
    exit 1
fi

echo "Started at: $(date)"

echo "[1/6] Backing up current installation..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/starmade_preupdate_${BRANCH}_$DATE.tar.gz"

tar --exclude="./logs" \
    --exclude="./tmp" \
    --exclude="./backups" \
    --exclude="./*.log" \
    -czf "$BACKUP_FILE" \
    -C "$STARMADE_DIR" .

if [ $? -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "Backup saved: $BACKUP_FILE ($SIZE)"
else
    echo "Backup failed! Aborting update for safety."
    exit 1
fi

ls -t "$BACKUP_DIR"/starmade_preupdate_*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read old_backup; do
    echo "  Removing old backup: $old_backup"
    rm -f "$old_backup"
done

echo "[2/6] Warning players..."
send_command '/start_countdown 60 "Server restarting for updates!"'
send_command '/server_message_broadcast warning "Server will restart for updates in 60 seconds!"'
sleep 60

echo "[3/6] Stopping server..."
case "$SERVER_MODE" in
    "tmux")
        send_command "/shutdown 0"
        sleep 5
        sudo systemctl stop "$SYSTEMCTL_SERVICE"
        sleep 3
    ;;
    "docker") docker_stop_server
    ;;
esac

echo "[4/6] Downloading latest $BRANCH build..."
mkdir -p "$TEMP_DIR"

LATEST=$(curl -fsSL "$BUILD_URL/" | grep -o 'href="starmade-build_[^"]*\.zip"' | sed 's/href="//;s/"//' | sort | tail -1)

if [ -z "$LATEST" ]; then
    echo "Could not find latest build! Aborting..."
    sudo systemctl start "$SYSTEMCTL_SERVICE"
    exit 1
fi

echo "Latest build: $LATEST"
curl -fsSL "$BUILD_URL/$LATEST" -o "$TEMP_DIR/update.zip"

if [ $? -ne 0 ]; then
    echo "Download failed! Restarting existing version..."
    sudo systemctl start "$SYSTEMCTL_SERVICE"
    exit 1
fi

echo "Extracting update..."
unzip -q "$TEMP_DIR/update.zip" -d "$TEMP_DIR/raw"

# Strip top-level directory if the zip contains one (e.g. StarMade/)
INNER_DIR="$TEMP_DIR/raw"
ENTRIES=("$INNER_DIR"/*)
if [ ${#ENTRIES[@]} -eq 1 ] && [ -d "${ENTRIES[0]}" ]; then
    INNER_DIR="${ENTRIES[0]}"
fi
mv "$INNER_DIR" "$TEMP_DIR/extracted" 2>/dev/null || true

echo "[5/6] Applying update (respecting exclusions)..."
if [ -f "$EXCLUDES_FILE" ]; then
    while IFS= read -r excluded_file || [ -n "$excluded_file" ]; do
        [[ -z "$excluded_file" || "$excluded_file" == \#* ]] && continue
        echo "  Preserving: $excluded_file"
        if [ -f "$STARMADE_DIR/$excluded_file" ]; then
            cp "$STARMADE_DIR/$excluded_file" "$TEMP_DIR/extracted/$excluded_file" 2>/dev/null || true
        fi
    done < "$EXCLUDES_FILE"
else
    echo "  No exclusions file found, skipping..."
fi

rsync -a "$TEMP_DIR/extracted/" "$STARMADE_DIR/"

rm -rf "$TEMP_DIR"
echo "$BRANCH" > "$STARMADE_DIR/.current_branch"

echo "[6/6] Restarting server..."
case "$SERVER_MODE" in
    "tmux") sudo systemctl start "$SYSTEMCTL_SERVICE"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

echo "=== Update complete at: $(date) ==="
echo "Now running: $BRANCH branch"
