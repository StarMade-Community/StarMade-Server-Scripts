# StarMade Server Scripts

A collection of bash scripts for managing a StarMade dedicated server. Handles starting, stopping, backing up, restoring, updating, and scheduled restarts.

Runs via **Docker** (recommended, all platforms) or **natively** on Linux with systemd and tmux.

## Prerequisites

- A StarMade server installation (`StarMade.jar` in your server directory)
- **Docker setup (recommended):**
  - macOS / Windows: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  - Headless Linux: the installer will install Docker Engine automatically via `get.docker.com`
- **Native Linux setup:** Linux with `sudo` access — the installer handles everything else

## Setup

### Option A: Automated installer (recommended)

Paste this single command into your terminal. It will download the scripts and walk you through setup interactively — choose Docker or native Linux when prompted:

```bash
curl -fsSL https://raw.githubusercontent.com/StarMade-Community/StarMade-Server-Scripts/main/bootstrap.sh | bash
```

Or with `wget` if you don't have `curl`:

```bash
wget -qO- https://raw.githubusercontent.com/StarMade-Community/StarMade-Server-Scripts/main/bootstrap.sh | bash
```

The bootstrap script will:
1. Install `git` if it isn't already present
2. Ask where to clone the scripts (default: `~/starmade-scripts`)
3. Clone the repository
4. Launch `install.sh`, which prompts for Docker (default) or native Linux setup

Skip to the [Scripts](#scripts) section when done.

---

### Option B: Manual setup (Docker)

#### 1. Clone the scripts

```bash
git clone <repo-url> /path/to/scripts
cd /path/to/scripts
chmod +x *.sh
```

#### 2. Configure

Copy `.env.example` to `.env` and edit it:

```bash
cp .env.example .env
nano .env
```

| Variable            | Used by        | Description                                                  | Default                |
|---------------------|----------------|--------------------------------------------------------------|------------------------|
| `STARMADE_DIR`      | Both           | Absolute path to your StarMade server directory              | *(must be set)*        |
| `UPDATE_BRANCH`     | Both           | `release`, `dev`, or `pre`                                   | `dev`                  |
| `JVM_MIN_HEAP`      | Both           | Minimum JVM heap (e.g. `4g`)                                 | `4g`                   |
| `JVM_MAX_HEAP`      | Both           | Maximum JVM heap (e.g. `8g`)                                 | `16g`                  |
| `JVM_EXTRA_ARGS`    | Both           | Extra JVM args — required for `pre` branch                   | *(empty)*              |
| `JAVA_VERSION`      | Docker         | Java version for the image — auto-detected (`8` for < 0.3, `21` for >= 0.3) | `21`                   |
| `SERVER_PORT`       | Both           | Game port — sets host **and** in-container port; use a unique value per instance | `4242`                 |
| `TMUX_SESSION`      | Native Linux   | tmux session name                                            | `StarMade`             |
| `BACKUP_DIR`        | Native Linux   | Where backup archives are stored                             | `$STARMADE_DIR/backups` |
| `LOG_DIR`           | Native Linux   | Where log files live                                         | `$STARMADE_DIR/logs`   |
| `SYSTEMCTL_SERVICE` | Native Linux   | systemd service unit name                                    | `starmade`             |
| `MAX_BACKUPS`       | Native Linux   | How many backups to keep before pruning                      | `3`                    |

> **Note:** Game versions >= 0.3 require **Java 21** and additional `--add-opens` JVM flags. Both are detected and set automatically based on the installed game version.

#### 3. Install Java

- Game versions < 0.3: **Java 8** or later
- Game versions >= 0.3: **Java 21** or later

```bash
# Ubuntu/Debian — Java 8
sudo apt-get install openjdk-8-jre-headless

# Ubuntu/Debian — Java 8
sudo apt-get install openjdk-8-jre-headless

# Fedora/RHEL — Java 8
sudo dnf install java-8-openjdk-headless
```

If your distro doesn't carry the required version, install it via [SDKMAN](https://sdkman.io):

```bash
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 21-tem   # Eclipse Temurin 21 (for game versions >= 0.3)
```

#### 4. Create a systemd service

The backup, restore, update, and scheduled-restart scripts use `systemctl` to stop and start the server. Create a service unit that calls `start.sh`:

```ini
# /etc/systemd/system/starmade.service
[Unit]
Description=StarMade Game Server
After=network.target

[Service]
Type=forking
User=YOUR_USER
ExecStart=/path/to/scripts/start.sh
ExecStop=/path/to/scripts/stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable starmade
sudo systemctl start starmade
```

#### 5. Grant passwordless sudo for systemctl (optional but recommended)

So scripts can restart the service without prompting for a password, add a sudoers entry:

```bash
sudo visudo -f /etc/sudoers.d/starmade
```

```
YOUR_USER ALL=(ALL) NOPASSWD: /bin/systemctl start starmade, /bin/systemctl stop starmade, /bin/systemctl restart starmade
```

---

## Scripts

### `download.sh`

Downloads the latest StarMade build and extracts it to `STARMADE_DIR`. Asks before overwriting an existing installation. Offers to start the server when done.

```bash
./download.sh          # uses UPDATE_BRANCH from .env
./download.sh release  # force release branch
./download.sh dev      # force dev branch
./download.sh pre      # force pre branch
```

The installer calls this automatically if `StarMade.jar` is not found in your server directory.

### `start.sh`

Starts the server in a detached tmux session.

```bash
./start.sh
```

### `stop.sh`

Sends the in-game `/shutdown` command then kills the tmux session.

```bash
./stop.sh
```

### `backup.sh`

Warns online players, stops the server, creates a timestamped `.tar.gz` archive of the server directory, then restarts. Automatically prunes archives older than `MAX_BACKUPS`.

```bash
./backup.sh
```

Excludes `logs/`, `tmp/`, `backups/`, and `*.log` files from the archive.

### `restore.sh`

Lists available backups interactively, snapshots the current state first (so you can recover if the restore fails), then restores the selected archive.

```bash
./restore.sh
```

### `update.sh`

Downloads the latest build from the official StarMade build server, backs up the current installation, applies the update, and restarts. Uses `UPDATE_BRANCH` from `config.sh` by default; pass an argument to override.

```bash
./update.sh          # uses UPDATE_BRANCH from config.sh
./update.sh release  # force release branch
./update.sh dev      # force dev branch
./update.sh pre      # force pre branch
```

#### Preserving custom files during updates

`update.sh` supports an exclusions file that prevents specific files from being overwritten when a new build is applied. Before applying the update, each listed file is copied out of your installation and placed back over the freshly extracted build — so your version wins instead of the default.

Copy the provided example into your server directory and uncomment what you need:

```bash
cp update-excludes.example.txt /path/to/starmade/update-excludes.txt
nano /path/to/starmade/update-excludes.txt
```

Paths are relative to `STARMADE_DIR`, one per line. Lines beginning with `#` are ignored.

```
# server settings
server.cfg

# block configs
data/config/BlockTypes.properties
data/config/BlockConfig.xml

# mods
mods/MyMod/config.cfg
```

**Modded servers — block config preservation**

StarMade maps block names to numeric IDs locally in `data/config/BlockTypes.properties`. If an update overwrites this file with the vanilla defaults, every custom or modded block in your world loses its ID mapping and loaded chunks will be corrupted. **Always add at minimum these two lines to your exclusions file on a modded server:**

```
data/config/BlockTypes.properties
data/config/BlockConfig.xml
```

See `update-excludes.example.txt` in this repository for a fully annotated template covering server settings, block configs, mods, blueprints, and custom content.

### `scheduled-restart.sh`

Warns players, waits 60 seconds, then restarts the server. Logs activity to `$LOG_DIR/restart.log`. Intended to be run on a cron schedule.

```bash
./scheduled-restart.sh
```

#### Example cron entries

```cron
# Daily restart at 5:00 AM
0 5 * * * /path/to/scripts/scheduled-restart.sh

# Weekly backup every Sunday at 3:00 AM
0 3 * * 0 /path/to/scripts/backup.sh

# Check for updates every Monday at 4:00 AM
0 4 * * 1 /path/to/scripts/update.sh
```

---

## Docker (macOS / Windows)

The installer automatically configures Docker when run on a non-Linux OS. If you prefer to set it up manually:

```bash
# 1. Copy and edit the environment file
cp .env.example .env
nano .env

# 2. Build the image and start the server
docker compose up -d
```

| Command                        | Description                        |
|--------------------------------|------------------------------------|
| `docker compose up -d`         | Start the server in the background |
| `docker compose down`          | Stop and remove the container      |
| `docker compose restart`       | Restart the server                 |
| `docker compose logs -f`       | Stream server logs                 |

### Backups with Docker

The server data lives in the directory set as `STARMADE_DIR` in your `.env`. To back it up, stop the container and archive that directory:

```bash
docker compose down
tar -czf starmade_backup_$(date +%Y%m%d).tar.gz -C "$STARMADE_DIR" .
docker compose up -d
```

---

## Running multiple servers on one host

This repo's `docker-compose.yml` defines a **single** service, so running two servers
takes a little care. The pitfalls below are what make a second instance unstable.

1. **Give each instance its own `.env`** with distinct values:
   - `STARMADE_DIR` — separate server directory. Never share a world/install between
     live servers: the world database (HSQLDB) is single-writer and will corrupt if
     two processes open the same files.
   - `SERVER_PORT` — a distinct port (e.g. `4242` and `4243`). This now sets both the
     published host port **and** the in-container game port, so it behaves correctly
     under bridge *and* host networking.
   - `CONTAINER_NAME` — a distinct name so the management scripts target the right one.
   - `JVM_MAX_HEAP` — size so the **sum** across all instances leaves headroom for the
     OS. Two servers at `16g` each will starve a 16–32 GB host into constant GC/swap,
     which stalls the server tick loop and drops client connections. On a 16 GB box,
     try `6g` each.

2. **Launch them as separate Compose projects** (distinct `-p` names). Running `up`
   twice from the same folder makes Compose *reconcile* — it replaces the first server
   instead of adding a second:

   ```bash
   docker compose -p sm1 --env-file .env.server1 up -d
   docker compose -p sm2 --env-file .env.server2 up -d
   ```

3. **`network_mode: host` requires a unique `SERVER_PORT` per instance.** In host mode
   Docker's port mapping is ignored, so instances stay separated only because each one
   binds its own `SERVER_PORT` directly on the host. With the old hardcoded `4242` this
   was the classic failure: the second server couldn't bind and threw connection errors.

## Directory layout

```
scripts/
├── .env                   # Your configuration (gitignored — copy from .env.example)
├── .env.example           # Configuration template
├── Dockerfile
├── docker-compose.yml
├── docker-entrypoint.sh
├── install.sh
├── bootstrap.sh
├── download.sh
├── start.sh
├── stop.sh
├── backup.sh
├── restore.sh
├── update.sh
├── scheduled-restart.sh
└── README.md

starmade-server/           # STARMADE_DIR (mounted as /starmade in Docker)
├── StarMade.jar
├── server.cfg
├── update-excludes.txt    # optional — copy from update-excludes.example.txt
├── data/config/           # block ID configs — add to update-excludes.txt on modded servers
├── backups/               # created automatically (native Linux)
└── logs/
```
