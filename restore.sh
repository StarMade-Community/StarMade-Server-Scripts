#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "=== StarMade Restore Script ==="
echo ""

if [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
    echo "No backups found in $BACKUP_DIR"
    exit 1
fi

echo "Available backups:"
echo ""
backups=()
i=1
while IFS= read -r backup; do
    SIZE=$(du -sh "$backup" | cut -f1)
    DATE=$(echo "$backup" | grep -oE '[[:digit:]]{8}_[[:digit:]]{6}')
    FORMATTED_DATE=$(date -d "${DATE:0:4}-${DATE:4:2}-${DATE:6:2} ${DATE:9:2}:${DATE:11:2}:${DATE:13:2}" "+%B %d %Y at %H:%M:%S" 2>/dev/null || echo "$DATE")
    TYPE=$(echo "$backup" | grep -oE '(preupdate|prerestore|backup)')
    echo "  [$i] $FORMATTED_DATE ($SIZE) - $TYPE"
    backups+=("$backup")
    ((i++))
done < <(ls -t "$BACKUP_DIR"/*.tar.gz)

echo ""
read -p "Enter the number of the backup to restore (or 'q' to quit): " CHOICE

if [ "$CHOICE" == "q" ]; then
    echo "Aborting restore."
    exit 0
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#backups[@]}" ]; then
    echo "Invalid selection."
    exit 1
fi

SELECTED="${backups[$((CHOICE-1))]}"
echo ""
echo "You selected: $SELECTED"
read -p "Are you sure? This will overwrite current server files. (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "Aborting restore."
    exit 0
fi

echo ""
echo "[1/4] Snapshotting current state..."
SNAPSHOT_FILE="$BACKUP_DIR/starmade_prerestore_$(date +%Y%m%d_%H%M%S).tar.gz"
tar --exclude="./logs" \
    --exclude="./tmp" \
    --exclude="./backups" \
    --exclude="./*.log" \
    -czf "$SNAPSHOT_FILE" \
    -C "$STARMADE_DIR" .
echo "Snapshot saved: $SNAPSHOT_FILE"

echo "[2/4] Warning players..."
send_command '/start_countdown 60 "Server restarting to restore a backup!"'
send_command '/server_message_broadcast warning "Server will restore a backup in 60 seconds!"'
sleep 60

echo "[3/4] Stopping server and restoring..."
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

tar -xzf "$SELECTED" -C "$STARMADE_DIR"

if [ $? -eq 0 ]; then
    echo "Restore successful!"
else
    echo "Restore failed! Recovering from snapshot..."
    tar -xzf "$SNAPSHOT_FILE" -C "$STARMADE_DIR"
    echo "Recovered from snapshot."
fi

echo "[4/4] Restarting server..."
case "$SERVER_MODE" in
    "tmux") sudo systemctl start "$SYSTEMCTL_SERVICE"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

echo "=== Restore complete at: $(date) ==="
