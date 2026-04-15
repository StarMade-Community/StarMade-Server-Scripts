#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/starmade_backup_$DATE.tar.gz"

echo "=== StarMade Backup Script ==="
echo "Started at: $(date)"

mkdir -p "$BACKUP_DIR"

echo "[1/4] Warning players..."
send_command '/start_countdown 60 "Server restarting for weekly backup!"'
send_command '/server_message_broadcast warning "Server will restart for backup in 60 seconds!"'
sleep 60

echo "[2/4] Stopping server..."
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

echo "[3/4] Creating backup..."
tar --exclude="./logs" \
    --exclude="./tmp" \
    --exclude="./backups" \
    --exclude="./*.log" \
    -czf "$BACKUP_FILE" \
    -C "$STARMADE_DIR" .

if [ $? -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
    echo "Backup created: $BACKUP_FILE ($SIZE)"
else
    echo "Backup failed!"
    case "$SERVER_MODE" in
        "tmux") sudo systemctl start "$SYSTEMCTL_SERVICE"
        ;;
        "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
        ;;
    esac
    exit 1
fi

echo "[4/4] Cleaning up old backups..."
ls -t "$BACKUP_DIR"/starmade_backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | while read old_backup; do
    echo "  Removing old backup: $old_backup"
    rm -f "$old_backup"
done

echo "Restarting server..."
case "$SERVER_MODE" in
    "tmux") sudo systemctl start "$SYSTEMCTL_SERVICE"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

echo "=== Backup complete at: $(date) ==="
