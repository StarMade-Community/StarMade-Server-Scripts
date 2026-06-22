#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Auto-detect version-specific JVM args for game versions >= 0.3
VERSION_ARGS=""
if game_needs_java21; then
    VERSION_ARGS="--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"
fi

case "$SERVER_MODE" in
    "tmux")
        cd "$STARMADE_DIR"
        tmux new-session -d -s "$TMUX_SESSION" \
            "java -Xms${JVM_MIN_HEAP} -Xmx${JVM_MAX_HEAP} \
            ${VERSION_ARGS} ${JVM_EXTRA_ARGS} \
            -javaagent:StarMade.jar -jar StarMade.jar -server -port:4242 -autoupdatemods"
    ;;
    "docker") sudo docker compose --project-directory "$SCRIPT_DIR" up -d
    ;;
esac

