#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "$(date) - Starting scheduled daily restart..." >> "$LOG_DIR/restart.log"

send_command '/start_countdown 60 "Server restarting for daily maintenance!"'
send_command '/server_message_broadcast warning "Server will restart for daily maintenance in 60 seconds!"'
sleep 60

send_command "/shutdown 0"
# Docker will restart on its own with restart: unless-stopped
if [[ "$SERVER_MODE" != "docker" ]]; then
    sleep 5
    sudo systemctl restart "$SYSTEMCTL_SERVICE"
fi

echo "$(date) - Daily restart complete." >> "$LOG_DIR/restart.log"
