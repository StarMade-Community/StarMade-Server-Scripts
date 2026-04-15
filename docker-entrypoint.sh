#!/bin/bash
set -e

if [ ! -f /starmade/StarMade.jar ]; then
    echo "[ERROR] StarMade.jar not found in /starmade."
    echo "        Mount your server directory as a volume at /starmade and make sure StarMade.jar is present."
    exit 1
fi

# Allow scripts to catch and stop the container before it auto-restarts
sleep 1

exec java \
    -Xms${JVM_MIN_HEAP} \
    -Xmx${JVM_MAX_HEAP} \
    ${JVM_EXTRA_ARGS} \
    -jar /starmade/StarMade.jar \
    -server \
    -autoupdatemods
