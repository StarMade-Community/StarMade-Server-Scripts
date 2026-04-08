#!/bin/bash
# StarMade Server Scripts — Installer
# Installs dependencies, writes config.sh, creates a systemd service,
# and sets up passwordless sudo for service management.

set -e

# Reconnect stdin to the terminal in case this script was reached via a pipe
# (e.g. curl ... | bash → exec install.sh). Keeps all read prompts interactive.
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    else
        echo "[ERROR] No interactive terminal available. Run install.sh directly." >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helpers ---

print_header() {
    echo ""
    echo "=========================================="
    echo "  StarMade Server Scripts — Installer"
    echo "=========================================="
    echo ""
}

info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

prompt() {
    # prompt <variable_name> <display_label> <default_value>
    local var="$1" label="$2" default="$3"
    read -rp "  $label [$default]: " input
    eval "$var=\"${input:-$default}\""
}

prompt_nodefault() {
    local var="$1" label="$2"
    local input=""
    while [ -z "$input" ]; do
        read -rp "  $label: " input
        [ -z "$input" ] && echo "  This field is required."
    done
    eval "$var=\"$input\""
}

get_java_major_version() {
    if ! command -v java &>/dev/null; then echo 0; return; fi
    local raw major
    raw=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+')
    major=$(echo "$raw" | cut -d. -f1)
    [ "$major" -eq 1 ] && major=$(echo "$raw" | cut -d. -f2)
    echo "$major"
}

install_java() {
    local required="$1"
    info "Attempting to install Java $required via system package manager..."

    local installed=false
    case "$PKG_MANAGER" in
        apt)
            local pkg="openjdk-${required}-jre-headless"
            if sudo apt-get install -y "$pkg" 2>/dev/null; then
                installed=true
            fi
            ;;
        dnf)
            local pkg="java-${required}-openjdk-headless"
            if sudo dnf install -y "$pkg" 2>/dev/null; then
                installed=true
            fi
            ;;
        yum)
            local pkg="java-${required}-openjdk-headless"
            if sudo yum install -y "$pkg" 2>/dev/null; then
                installed=true
            fi
            ;;
        pacman)
            # Arch tracks the latest JRE as jre-openjdk; version-specific packages are jreXX-openjdk
            local pkg="jre${required}-openjdk-headless"
            if sudo pacman -S --noconfirm "$pkg" 2>/dev/null; then
                installed=true
            fi
            ;;
        zypper)
            local pkg="java-${required}-openjdk-headless"
            if sudo zypper install -y "$pkg" 2>/dev/null; then
                installed=true
            fi
            ;;
    esac

    if $installed; then
        success "Java $required installed via package manager"
        return 0
    fi

    # Fall back to SDKMAN (works on any Linux distro)
    info "Package not found in system repos — falling back to SDKMAN..."

    if ! command -v sdk &>/dev/null; then
        info "Installing SDKMAN..."
        curl -s "https://get.sdkman.io" | bash
        # shellcheck source=/dev/null
        source "$HOME/.sdkman/bin/sdkman-init.sh"
    fi

    sdk install java "${required}-tem"   # Eclipse Temurin build
    # Make the installed java available in the current session
    # shellcheck source=/dev/null
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk use java "${required}-tem"
    success "Java $required installed via SDKMAN (Eclipse Temurin)"
}

# --- Preflight checks ---

print_header

if [ "$EUID" -eq 0 ]; then
    error "Do not run this installer as root. Run it as the user who will own the server."
fi

# --- Choose setup method ---

echo "How would you like to run the server?"
echo ""
echo "  [1] Docker (recommended — works on Linux, macOS, and Windows)"
echo "  [2] Native Linux (systemd + tmux, Linux only)"
echo ""
read -rp "  Choice [1]: " SETUP_METHOD
SETUP_METHOD="${SETUP_METHOD:-1}"

echo ""

# ============================================================
# Docker setup
# ============================================================
if [ "$SETUP_METHOD" == "1" ]; then

    if ! command -v docker &>/dev/null; then
        # On macOS, Docker Desktop may be installed but not running (CLI symlinks
        # are only created once Docker Desktop starts for the first time).
        if [[ "$(uname -s)" == "Darwin" ]] && [ -d "/Applications/Docker.app" ]; then
            info "Docker Desktop is installed but the CLI is not in PATH. Starting Docker Desktop..."
            open -a Docker
            echo ""
            info "Waiting for Docker to start (this can take a minute)..."
            while ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; do
                sleep 2
            done
            success "Docker Desktop is running"
        elif [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
            info "Docker not found — installing Docker Desktop via Homebrew..."
            brew install --cask docker
            info "Starting Docker Desktop..."
            open -a Docker
            info "Waiting for Docker to start (this can take a minute)..."
            while ! command -v docker &>/dev/null || ! docker info &>/dev/null 2>&1; do
                sleep 2
            done
            success "Docker Desktop is running"
        elif [[ "$(uname -s)" == "Linux" ]]; then
            info "Docker not found — installing Docker Engine..."
            curl -fsSL https://get.docker.com | sudo sh
            sudo usermod -aG docker "$(whoami)"
            info "Docker installed. You may need to log out and back in for group membership to take effect."
            info "Starting Docker service..."
            sudo systemctl enable --now docker
        else
            error "Docker is not installed. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ then re-run this installer."
        fi
    fi
    success "Docker found: $(docker --version)"

    # Prefer the compose plugin, fall back to standalone docker-compose
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        if [[ "$(uname -s)" == "Linux" ]]; then
            info "Installing Docker Compose plugin..."
            install_pkg docker-compose-plugin 2>/dev/null || install_pkg docker-compose 2>/dev/null \
                || error "Could not install Docker Compose. Install it manually: https://docs.docker.com/compose/install/"
        else
            error "Docker Compose not found. It is bundled with Docker Desktop — make sure Docker Desktop is up to date."
        fi
        # Re-check after install attempt
        if docker compose version &>/dev/null 2>&1; then
            COMPOSE_CMD="docker compose"
        elif command -v docker-compose &>/dev/null; then
            COMPOSE_CMD="docker-compose"
        else
            error "Docker Compose still not found after install attempt. Install it manually: https://docs.docker.com/compose/install/"
        fi
    fi
    success "Docker Compose found"

    echo ""
    echo "--- Docker Configuration ---"
    echo ""
    echo "Press Enter to accept the value shown in brackets, or type a new one."
    echo ""

    prompt_nodefault STARMADE_DIR "Path to your StarMade server directory"

    if [ ! -d "$STARMADE_DIR" ]; then
        warn "Directory '$STARMADE_DIR' does not exist."
        read -rp "  Create it now? (y/n): " MKDIR_CONF
        if [ "$MKDIR_CONF" == "y" ]; then
            mkdir -p "$STARMADE_DIR"
            success "Created $STARMADE_DIR"
        else
            error "Server directory must exist before setup can continue."
        fi
    fi

    prompt UPDATE_BRANCH "Update branch (release / dev / pre)" "release"
    prompt JVM_MIN_HEAP  "JVM minimum heap (e.g. 4g)"          "4g"
    prompt JVM_MAX_HEAP  "JVM maximum heap (e.g. 8g)"          "8g"
    prompt SERVER_PORT   "Host port to expose"                  "4242"

    if [ "$UPDATE_BRANCH" == "pre" ]; then
        JAVA_VERSION=25
        JVM_EXTRA_ARGS="--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED"
    else
        JAVA_VERSION=8
        JVM_EXTRA_ARGS=""
    fi

    cat > "$SCRIPT_DIR/.env" <<EOF
# StarMade Docker Configuration
# Generated by install.sh on $(date)

JAVA_VERSION=$JAVA_VERSION
JVM_MIN_HEAP=$JVM_MIN_HEAP
JVM_MAX_HEAP=$JVM_MAX_HEAP
JVM_EXTRA_ARGS=$JVM_EXTRA_ARGS
STARMADE_DIR=$STARMADE_DIR
SERVER_PORT=$SERVER_PORT
EOF
    success ".env written"

    chmod +x "$SCRIPT_DIR"/*.sh

    # Offer to download StarMade if it isn't already present
    if [ ! -f "$STARMADE_DIR/StarMade.jar" ]; then
        echo ""
        read -rp "  StarMade.jar not found — download it now? (y/n): " DL_NOW
        if [ "$DL_NOW" == "y" ]; then
            "$SCRIPT_DIR/download.sh" "$UPDATE_BRANCH"
        fi
    fi

    echo ""
    read -rp "  Build and start the server now? (y/n): " START_NOW
    if [ "$START_NOW" == "y" ]; then
        cd "$SCRIPT_DIR"
        info "Building Docker image (this may take a minute)..."
        $COMPOSE_CMD build
        info "Starting server..."
        $COMPOSE_CMD up -d
        success "Server started"
    fi

    echo ""
    echo "=========================================="
    echo "  Docker setup complete!"
    echo "=========================================="
    echo ""
    echo "  Commands (run from anywhere):"
    echo "    cd $SCRIPT_DIR"
    echo "    docker compose up -d        # start"
    echo "    docker compose down          # stop"
    echo "    docker compose logs -f       # logs"
    echo "    docker compose restart       # restart"
    echo ""
    exit 0

# ============================================================
# Native Linux setup
# ============================================================
elif [ "$SETUP_METHOD" == "2" ]; then

    if [[ "$(uname -s)" != "Linux" ]]; then
        error "Native setup requires Linux. Choose option 1 (Docker) for macOS or Windows."
    fi

    if ! sudo -n true 2>/dev/null; then
        info "This installer needs sudo for a few steps (installing packages, creating a systemd service)."
        sudo -v || error "Could not obtain sudo access. Ask your system administrator."
    fi

else
    error "Invalid choice. Run the installer again and enter 1 or 2."
fi

# --- Package manager detection ---

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null;     then echo "dnf"
    elif command -v yum &>/dev/null;     then echo "yum"
    elif command -v pacman &>/dev/null;  then echo "pacman"
    elif command -v zypper &>/dev/null;  then echo "zypper"
    else echo "unknown"
    fi
}

install_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)    sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        yum)    sudo yum install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        zypper) sudo zypper install -y "$pkg" ;;
        *)      warn "Unknown package manager — please install '$pkg' manually." ;;
    esac
}

PKG_MANAGER=$(detect_pkg_manager)

# --- Step 1: Non-Java dependencies ---

echo "--- Step 1/6: Installing dependencies ---"
echo ""
info "Detected package manager: $PKG_MANAGER"

if [ "$PKG_MANAGER" == "apt" ]; then
    sudo apt-get update -qq
fi

for dep in tmux wget unzip rsync curl; do
    if command -v "$dep" &>/dev/null; then
        success "$dep already installed"
    else
        info "Installing $dep..."
        install_pkg "$dep"
        success "$dep installed"
    fi
done

echo ""

# --- Step 2: Configuration ---

echo "--- Step 2/6: Configuration ---"
echo ""
echo "Press Enter to accept the value shown in brackets, or type a new one."
echo ""

prompt_nodefault STARMADE_DIR   "Path to your StarMade server directory"

if [ ! -d "$STARMADE_DIR" ]; then
    warn "Directory '$STARMADE_DIR' does not exist."
    read -rp "  Create it now? (y/n): " MKDIR_CONF
    if [ "$MKDIR_CONF" == "y" ]; then
        mkdir -p "$STARMADE_DIR"
        success "Created $STARMADE_DIR"
    else
        error "Server directory must exist before setup can continue."
    fi
fi

prompt TMUX_SESSION      "tmux session name"                   "StarMade"
prompt BACKUP_DIR        "Backup directory"                    "$STARMADE_DIR/backups"
prompt LOG_DIR           "Log directory"                       "$STARMADE_DIR/logs"
prompt SYSTEMCTL_SERVICE "systemd service name"                "starmade"
prompt MAX_BACKUPS       "Number of backups to keep"           "3"
prompt UPDATE_BRANCH     "Update branch (release / dev / pre)" "release"
prompt JVM_MIN_HEAP      "JVM minimum heap (e.g. 4g)"          "4g"
prompt JVM_MAX_HEAP      "JVM maximum heap (e.g. 8g)"          "8g"

# Determine Java requirement and extra args from branch
if [ "$UPDATE_BRANCH" == "pre" ]; then
    REQUIRED_JAVA=25
    JVM_EXTRA_ARGS="--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED"
else
    REQUIRED_JAVA=8
    JVM_EXTRA_ARGS=""
fi

echo ""

# --- Step 3: Java ---

echo "--- Step 3/6: Java (required: $REQUIRED_JAVA) ---"
echo ""

JAVA_MAJOR=$(get_java_major_version)

if [ "$JAVA_MAJOR" -ge "$REQUIRED_JAVA" ]; then
    success "Java $JAVA_MAJOR already installed — meets requirement (Java $REQUIRED_JAVA)"
else
    if [ "$JAVA_MAJOR" -gt 0 ]; then
        info "Java $JAVA_MAJOR is installed but Java $REQUIRED_JAVA is required. Installing..."
    else
        info "Java is not installed. Installing Java $REQUIRED_JAVA..."
    fi
    install_java "$REQUIRED_JAVA"

    # Verify
    JAVA_MAJOR=$(get_java_major_version)
    if [ "$JAVA_MAJOR" -ge "$REQUIRED_JAVA" ]; then
        success "Java $JAVA_MAJOR is ready"
    else
        warn "Could not verify Java $REQUIRED_JAVA installation."
        warn "Please install it manually before starting the server, then re-run this installer."
        read -rp "  Continue anyway? (y/n): " JAVA_CONT
        [ "$JAVA_CONT" != "y" ] && exit 1
    fi
fi

echo ""

# --- Write .env ---

cat > "$SCRIPT_DIR/.env" <<EOF
# StarMade Server Configuration — generated by install.sh on $(date)
# Edit this file to change settings, then restart the server.

STARMADE_DIR=$STARMADE_DIR
TMUX_SESSION=$TMUX_SESSION
BACKUP_DIR=$STARMADE_DIR/backups
LOG_DIR=$STARMADE_DIR/logs
SYSTEMCTL_SERVICE=$SYSTEMCTL_SERVICE
MAX_BACKUPS=$MAX_BACKUPS
UPDATE_BRANCH=$UPDATE_BRANCH
JVM_MIN_HEAP=$JVM_MIN_HEAP
JVM_MAX_HEAP=$JVM_MAX_HEAP
JVM_EXTRA_ARGS=$JVM_EXTRA_ARGS
EOF

# --- Step 4: Make scripts executable ---

echo "--- Step 4/6: Setting permissions ---"
echo ""

chmod +x "$SCRIPT_DIR"/*.sh
success "All scripts are now executable"
success ".env written"

echo ""

# --- Step 5: Create systemd service ---

echo "--- Step 5/6: Creating systemd service ---"
echo ""

SERVICE_FILE="/etc/systemd/system/${SYSTEMCTL_SERVICE}.service"
CURRENT_USER="$(whoami)"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=StarMade Game Server
After=network.target

[Service]
Type=forking
User=$CURRENT_USER
ExecStart=$SCRIPT_DIR/start.sh
ExecStop=$SCRIPT_DIR/stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SYSTEMCTL_SERVICE"
success "Service '$SYSTEMCTL_SERVICE' created and enabled"

echo ""

# --- Step 6: Passwordless sudo for systemctl ---

echo "--- Step 6/6: Configuring passwordless sudo ---"
echo ""

SUDOERS_FILE="/etc/sudoers.d/starmade-scripts"

sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Allow $CURRENT_USER to manage the StarMade service without a password
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl start $SYSTEMCTL_SERVICE, /bin/systemctl stop $SYSTEMCTL_SERVICE, /bin/systemctl restart $SYSTEMCTL_SERVICE
EOF

sudo chmod 440 "$SUDOERS_FILE"
success "Sudoers entry written to $SUDOERS_FILE"

# --- Download StarMade if needed ---

if [ ! -f "$STARMADE_DIR/StarMade.jar" ]; then
    echo ""
    read -rp "StarMade.jar not found — download it now? (y/n): " DL_NOW
    if [ "$DL_NOW" == "y" ]; then
        "$SCRIPT_DIR/download.sh" "$UPDATE_BRANCH"
    fi
fi

# --- Done ---

echo ""
echo "=========================================="
echo "  Setup complete!"
echo "=========================================="
echo ""
echo "  Start the server:    ./start.sh"
echo "  Stop the server:     ./stop.sh"
echo "  Backup:              ./backup.sh"
echo "  Restore:             ./restore.sh"
echo "  Update:              ./update.sh"
echo "  Download:            ./download.sh"
echo "  Scheduled restart:   ./scheduled-restart.sh"
echo ""
echo "  To set up a scheduled restart via cron:"
echo "    crontab -e"
echo "    # Daily restart at 5 AM:"
echo "    0 5 * * * $SCRIPT_DIR/scheduled-restart.sh"
echo ""
