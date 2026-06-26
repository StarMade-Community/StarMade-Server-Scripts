#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

EXCLUDES_FILE="$STARMADE_DIR/update-excludes.txt"
DATE=$(date +%Y%m%d_%H%M%S)
BRANCH=${1:-${UPDATE_BRANCH:-dev}}
TEMP_DIR="$(mktemp -d)"

# --- helpers for delta updates ---------------------------------------------
# SHA1 tool: GNU coreutils on the server, shasum as a portable fallback.
if command -v sha1sum >/dev/null 2>&1; then
    SHA1="sha1sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA1="shasum -a 1"
else
    SHA1=""
fi

# URL-encode a path, leaving '/' intact so the directory structure is preserved.
urlencode() {
    local s="$1" out="" i c
    for (( i=0; i<${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~/-]) out+="$c" ;;
            *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

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

echo "[1/6] Warning players..."
send_command '/start_countdown 60 "Server restarting for updates!"'
send_command '/server_message_broadcast warning "Server will restart for updates in 60 seconds!"'
sleep 60

echo "[2/6] Stopping server..."
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

echo "[3/6] Backing up current installation..."
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

echo "[4/6] Checking for changed files..."
mkdir -p "$TEMP_DIR"

# Each build folder ships a per-file manifest ("checksums": "<path> <size> <sha1>")
# and every file is individually downloadable. We hash the local install against
# that manifest and fetch only the files that are missing or different.
LATEST_DIR=$(curl -fsSL "$BUILD_URL/" | grep -o 'href="starmade-build_[^"]*/"' | sed 's/href="//;s#/"##' | sort | tail -1)

DELTA_DONE=0
UPDATED=0
DELETED=0

# Build a normalized excludes list (relative to STARMADE_DIR, no leading "./").
EXCLUDES_NORM="$TEMP_DIR/excludes.norm"
if [ -f "$EXCLUDES_FILE" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$EXCLUDES_FILE" | sed 's#^\./##; s/[[:space:]]*$//' | sort -u > "$EXCLUDES_NORM"
else
    : > "$EXCLUDES_NORM"
fi

if [ -n "$LATEST_DIR" ] && [ -n "$SHA1" ] && \
   curl -fsSL "$BUILD_URL/$LATEST_DIR/checksums" -o "$TEMP_DIR/checksums" && [ -s "$TEMP_DIR/checksums" ]; then
    BUILD_DIR_URL="$BUILD_URL/$LATEST_DIR"
    echo "Latest build: $LATEST_DIR"

    # Manifest -> "<sha1>  <path>" check file. The path is taken as everything
    # before the trailing " <size> <sha1>", so internal spaces are preserved.
    awk 'match($0, / [0-9]+ [0-9a-fA-F]+$/) { p=substr($0,1,RSTART-1); split(substr($0,RSTART+1),a," "); print a[2]"  "p }' \
        "$TEMP_DIR/checksums" > "$TEMP_DIR/sha1.check"

    # Manifest path set (relative, no "./"), sorted — used for stale-file detection.
    awk 'match($0, / [0-9]+ [0-9a-fA-F]+$/) { print substr($0,1,RSTART-1) }' "$TEMP_DIR/checksums" \
        | sed 's#^\./##' | sort -u > "$TEMP_DIR/manifest.paths"

    # List the local files that live under the build-managed top-level paths once;
    # it's reused for both "what's missing/changed" and "what's now stale".
    awk -F/ '{print $1}' "$TEMP_DIR/manifest.paths" | sort -u > "$TEMP_DIR/managed.tops"
    MANAGED=()
    while IFS= read -r t; do
        [ -n "$t" ] && [ -e "$STARMADE_DIR/$t" ] && MANAGED+=("$t")
    done < "$TEMP_DIR/managed.tops"
    if [ ${#MANAGED[@]} -gt 0 ]; then
        ( cd "$STARMADE_DIR" && find "${MANAGED[@]}" -type f 2>/dev/null ) | sed 's#^\./##' | sort -u > "$TEMP_DIR/local.paths"
    else
        : > "$TEMP_DIR/local.paths"
    fi

    echo "  Verifying local files against manifest ($(wc -l < "$TEMP_DIR/manifest.paths" | tr -d ' ') tracked)..."
    # Missing files: in the manifest but not on disk (portable set-difference — does
    # not rely on sha1sum's missing-file output, which differs across implementations).
    comm -13 "$TEMP_DIR/local.paths" "$TEMP_DIR/manifest.paths" > "$TEMP_DIR/need.missing"
    # Changed files: present locally but the hash differs (sha1sum -c reports "FAILED").
    ( cd "$STARMADE_DIR" && $SHA1 -c "$TEMP_DIR/sha1.check" 2>/dev/null ) \
        | grep ': FAILED' | sed 's/: FAILED.*$//; s#^\./##' | sort -u > "$TEMP_DIR/need.changed"
    sort -u "$TEMP_DIR/need.missing" "$TEMP_DIR/need.changed" > "$TEMP_DIR/need.all"

    # Never overwrite preserved files.
    comm -23 "$TEMP_DIR/need.all" "$EXCLUDES_NORM" > "$TEMP_DIR/need.final"
    NEED_COUNT=$(wc -l < "$TEMP_DIR/need.final" | tr -d ' ')

    STAGE="$TEMP_DIR/stage"
    if [ "$NEED_COUNT" -gt 0 ]; then
        echo "  $NEED_COUNT file(s) changed — downloading only those..."
        mkdir -p "$STAGE"
        if command -v aria2c >/dev/null 2>&1; then
            # One input file feeds aria2; -j runs many small files in parallel and
            # -x/-s split the few big ones (StarMade.jar, data/) across connections.
            while IFS= read -r p; do
                printf '%s\n  dir=%s\n  out=%s\n' "$BUILD_DIR_URL/$(urlencode "$p")" "$STAGE" "$p"
            done < "$TEMP_DIR/need.final" > "$TEMP_DIR/aria.input"
            aria2c -i "$TEMP_DIR/aria.input" -j 16 -x 8 -s 8 \
                --connect-timeout=30 --max-tries=3 --retry-wait=5 \
                --auto-file-renaming=false --allow-overwrite=true --console-log-level=warn
            DL_RC=$?
        else
            echo "  (tip: install 'aria2' for much faster parallel downloads)"
            DL_RC=0
            while IFS= read -r p; do
                mkdir -p "$STAGE/$(dirname "$p")"
                if ! curl -fsSL "$BUILD_DIR_URL/$(urlencode "$p")" -o "$STAGE/$p"; then
                    echo "  Failed to download: $p"; DL_RC=1; break
                fi
            done < "$TEMP_DIR/need.final"
        fi

        if [ "$DL_RC" -ne 0 ]; then
            echo "Delta download failed! Restarting existing version..."
            [ "$SERVER_MODE" = "tmux" ] && sudo systemctl start "$SYSTEMCTL_SERVICE"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        rsync -a "$STAGE/" "$STARMADE_DIR/"
        UPDATED=$NEED_COUNT
    else
        echo "  Already up to date — nothing to download."
    fi

    echo "[5/6] Removing stale files..."
    # Delete local files under manifest-managed top-level paths that no longer exist
    # in the new build (and aren't preserved), so removed libs/assets don't linger.
    if [ ${#MANAGED[@]} -gt 0 ]; then
        comm -23 "$TEMP_DIR/local.paths" "$TEMP_DIR/manifest.paths" > "$TEMP_DIR/stale.all"
        comm -23 "$TEMP_DIR/stale.all" "$EXCLUDES_NORM" > "$TEMP_DIR/stale.final"
        while IFS= read -r p; do
            [ -n "$p" ] && rm -f "$STARMADE_DIR/$p" && DELETED=$((DELETED + 1))
        done < "$TEMP_DIR/stale.final"
        ( cd "$STARMADE_DIR" && find "${MANAGED[@]}" -type d -empty -delete 2>/dev/null )
    fi

    GAME_VERSION=$(curl -fsSL "$BUILD_DIR_URL/version.txt" 2>/dev/null | head -1 | cut -d'#' -f1 | tr -d '[:space:]')
    [ -n "$GAME_VERSION" ] && echo "$GAME_VERSION" > "$STARMADE_DIR/.game_version"
    echo "$BRANCH" > "$STARMADE_DIR/.current_branch"
    echo "  Delta applied: $UPDATED updated, $DELETED removed."
    DELTA_DONE=1
fi

if [ "$DELTA_DONE" -ne 1 ]; then
    echo "  Delta update unavailable (no manifest or no sha1 tool) — falling back to full download."
    LATEST=$(curl -fsSL "$BUILD_URL/" | grep -o 'href="starmade-build_[^"]*\.zip"' | sed 's/href="//;s/"//' | sort | tail -1)

    if [ -z "$LATEST" ]; then
        echo "Could not find latest build! Aborting..."
        sudo systemctl start "$SYSTEMCTL_SERVICE"
        exit 1
    fi

    echo "Latest build: $LATEST"
    if command -v aria2c >/dev/null 2>&1; then
        # Multi-connection download — the build server caps per-connection (~9 MB/s)
        # but not per-IP, so parallel splits are several times faster.
        aria2c -x 8 -s 8 -k 25M \
            --connect-timeout=30 --max-tries=3 --retry-wait=5 \
            --console-log-level=warn --summary-interval=5 \
            -d "$TEMP_DIR" -o update.zip "$BUILD_URL/$LATEST"
    else
        echo "  (tip: install 'aria2' for much faster multi-connection downloads)"
        curl -fL --progress-bar \
            --connect-timeout 30 \
            --retry 3 --retry-delay 5 \
            --speed-time 60 --speed-limit 1024 \
            "$BUILD_URL/$LATEST" -o "$TEMP_DIR/update.zip"
    fi

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
    echo "$BRANCH" > "$STARMADE_DIR/.current_branch"
fi

rm -rf "$TEMP_DIR"

echo "[6/6] Restarting server..."
case "$SERVER_MODE" in
    "tmux") sudo systemctl start "$SYSTEMCTL_SERVICE"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

echo "=== Update complete at: $(date) ==="
echo "Now running: $BRANCH branch"
