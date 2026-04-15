#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$SERVER_MODE" in
    "tmux") echo 1
        tmux send-keys -t "$TMUX_SESSION" "/shutdown 0" Enter
        sleep 5
        tmux kill-session -t "$TMUX_SESSION"
    ;;
    "docker") docker_stop_server
    ;;
esac
