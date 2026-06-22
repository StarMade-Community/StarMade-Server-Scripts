#!/bin/bash
set -e

if [ ! -f /starmade/StarMade.jar ]; then
    echo "[ERROR] StarMade.jar not found in /starmade."
    echo "        Mount your server directory as a volume at /starmade and make sure StarMade.jar is present."
    exit 1
fi

# Auto-detect version-specific JVM args for game versions >= 0.3
VERSION_ARGS=""
if [ -f /starmade/.game_version ]; then
    GAME_MINOR=$(cut -d. -f2 < /starmade/.game_version)
    if [ "${GAME_MINOR:-0}" -ge 300 ] 2>/dev/null; then
        VERSION_ARGS="--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"
    fi
fi

# Allow scripts to catch and stop the container before it auto-restarts
sleep 1

exec java \
    -Xms${JVM_MIN_HEAP} \
    -Xmx${JVM_MAX_HEAP} \
    ${VERSION_ARGS} ${JVM_EXTRA_ARGS} \
    -jar /starmade/StarMade.jar \
    -server \
    -port:4242 \
    -autoupdatemods
