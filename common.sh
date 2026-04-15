#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
else
    echo "No .env file found. Did you forget to copy .env.example to .env?"
    exit 1
fi

case "$SERVER_MODE" in
    "")
        if [[ -x "$(command -v tmux)" ]] && tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            echo "Detected server running in tmux"
            SERVER_MODE=tmux
        elif [[ -x "$(command -v docker)" ]] && docker inspect -f '{{.State.Status}}' $CONTAINER_NAME >/dev/null; then
            if ! [[ -x "$(command -v script)" ]]; then
                echo "script command not found, please install util-linux[-script]"
                exit 1
            fi
            echo "Detected server running in Docker"
            SERVER_MODE=docker
        else
            echo "No server detected in Docker or tmux"
            exit 1
        fi
        ;;
    "docker"|"tmux") ;;
    *)
        echo 'Invalid SERVER_MODE, must be "docker", "tmux", or empty'
        exit 1
    ;;
esac

send_command() {
    case "$SERVER_MODE" in
        "tmux")
            # Send the command to a running tmux session
            tmux send-keys -t "$TMUX_SESSION" "$1" Enter
        ;;
        "docker")
            # Send the command to a running docker container via docker attach. The script command simulates a tty.
            sudo bash -c "echo '$1' | script -E never -qef -c 'docker attach --detach-keys=ctrl-d $CONTAINER_NAME' /dev/null"
        ;;
        *)
            echo 'Invalid SERVER_MODE, must be "docker", "tmux", or empty'
            exit 1
        ;;
    esac
}

docker_stop_server() {
    # Send the shutdown command to the server, wait for it to stop, and then stop the container before the server restarts
    sudo docker wait "$CONTAINER_NAME" &
    SERVER_MODE=docker send_command '/shutdown 0'
    wait $!
    sudo docker compose --project-directory "$SCRIPT_DIR" stop -t 30
}
