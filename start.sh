#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$SERVER_MODE" in
    "tmux")
        cd "$STARMADE_DIR"
        tmux new-session -d -s "$TMUX_SESSION" \
            "java -Xms${JVM_MIN_HEAP} -Xmx${JVM_MAX_HEAP} \
            ${JVM_EXTRA_ARGS} \
            -jar StarMade.jar -server -autoupdatemods"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

