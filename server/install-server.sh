#!/usr/bin/env bash
#
# Install the Todo Widget sync server on Ubuntu/Debian as a systemd service.
#
#   sudo ./server/install-server.sh
#
# Idempotent: run it again to upgrade in place. It never touches the database
# or the environment file once they exist, so an upgrade cannot lose data or
# silently reset your Keycloak settings.
#
# What it does, and why each part is here:
#
#   - Installs Node if it is missing. Ubuntu's own package is often too old for
#     `node --test` and global fetch, so it uses NodeSource when apt's is < 20.
#   - Creates a `todosync` system user with no login shell. The service must
#     not run as root: it speaks HTTP to the internet, and better-sqlite3 is
#     native code.
#   - Copies the server *out of* wherever you cloned it, to /opt/todo-sync.
#     Running a service out of a working tree means the next `git pull` swaps
#     the code under a live process - the same reason install-windows.ps1
#     copies out of app\build\.
#   - Keeps state in /var/lib/todo-sync, which is not in the install directory,
#     so reinstalling never touches the database.
#
# Configuration afterwards lives in /etc/todo-sync.env. See DEPLOY.md.

set -euo pipefail

APP_USER=todosync
INSTALL_DIR=/opt/todo-sync
DATA_DIR=/var/lib/todo-sync
ENV_FILE=/etc/todo-sync.env
UNIT=/etc/systemd/system/todo-sync.service
NODE_MIN=20

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"

# The repo root is the parent of this script's directory, however it was invoked.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO/server/index.js" ]] || die "cannot find server/index.js next to this script"

# ------------------------------------------------------------------ node

install_node() {
  say "Installing Node ${NODE_MIN}.x from NodeSource"
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MIN}.x" | bash -
  apt-get install -y -qq nodejs
}

if command -v node >/dev/null 2>&1; then
  current="$(node -p 'process.versions.node.split(".")[0]')"
  if (( current < NODE_MIN )); then
    warn "Node $current is older than $NODE_MIN"
    install_node
  else
    say "Node $(node -v) is already installed"
  fi
else
  install_node
fi

# better-sqlite3 is native. A prebuilt binary usually covers it, but if npm has
# to compile, these are what it needs - and the failure without them is a wall
# of node-gyp output that says nothing useful.
say "Ensuring build tools for native modules"
apt-get install -y -qq python3 make g++ >/dev/null

# ------------------------------------------------------------------ user

if id "$APP_USER" >/dev/null 2>&1; then
  say "User $APP_USER already exists"
else
  say "Creating system user $APP_USER"
  useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

# ------------------------------------------------------------------ files

say "Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
# Only the server and its manifest. The Flutter app, the dead Tauri tree and
# the git history have no business on a server.
rm -rf "$INSTALL_DIR/server"
cp -r "$REPO/server" "$INSTALL_DIR/server"
cp "$REPO/package.json" "$INSTALL_DIR/package.json"
[[ -f "$REPO/package-lock.json" ]] && cp "$REPO/package-lock.json" "$INSTALL_DIR/"

# The server's own tests and any local database from a dev run must not ship.
rm -f "$INSTALL_DIR"/server/*.test.js
rm -rf "$INSTALL_DIR/server/data"

say "Installing production dependencies"
cd "$INSTALL_DIR"
# --omit=dev so express and better-sqlite3 arrive without vite, typescript and
# the Tauri CLI, none of which a server has any use for.
if [[ -f package-lock.json ]]; then
  npm ci --omit=dev --no-audit --no-fund
else
  npm install --omit=dev --no-audit --no-fund
fi

mkdir -p "$DATA_DIR"
chown -R "$APP_USER:$APP_USER" "$DATA_DIR"
chmod 700 "$DATA_DIR"

# ------------------------------------------------------------------ config

if [[ -f "$ENV_FILE" ]]; then
  say "Keeping existing $ENV_FILE"
else
  say "Writing $ENV_FILE"
  cat > "$ENV_FILE" <<EOF
# Todo Widget sync server. Restart after editing:
#   sudo systemctl restart todo-sync

TODO_SYNC_PORT=8787

# 127.0.0.1 is the right answer when a reverse proxy terminates TLS in front of
# this, which it should if the server is reachable from the internet. Use
# 0.0.0.0 only for a LAN-only box.
TODO_SYNC_HOST=127.0.0.1

TODO_SYNC_DB=$DATA_DIR/sync.db

# --- Single sign-on (Keycloak). Leave unset to use device tokens only. -------
# TODO_OIDC_ISSUER=https://keycloak.example.com/realms/home
# TODO_OIDC_CLIENT_ID=todo-widget
# TODO_OIDC_ADMIN_ROLE=todo-admin
EOF
  chmod 600 "$ENV_FILE"
fi

# ------------------------------------------------------------------ service

say "Installing systemd unit"
cat > "$UNIT" <<EOF
[Unit]
Description=Todo Widget sync server
Documentation=https://github.com/rosinusserrano/todo-app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $INSTALL_DIR/server/index.js
Restart=on-failure
RestartSec=5

# The service needs one writable directory and nothing else. Everything below
# is the difference between "a bug in a sync server" and "a bug in a sync
# server that could read /etc/shadow".
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
# AF_NETLINK is not a network the server can speak to - it is how Linux answers
# "which interfaces does this machine have", which the startup banner asks when
# bound to anything other than loopback. Without it os.networkInterfaces()
# throws EAFNOSUPPORT.
RestrictAddressFamilies=AF_INET AF_INET6 AF_NETLINK
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=false
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now todo-sync

sleep 1
if systemctl is-active --quiet todo-sync; then
  say "todo-sync is running"
else
  warn "todo-sync did not start. Recent log:"
  journalctl -u todo-sync -n 30 --no-pager || true
  exit 1
fi

# ------------------------------------------------------------------ next steps

PORT="$(grep -oP '^TODO_SYNC_PORT=\K.*' "$ENV_FILE" || echo 8787)"
BIND="$(grep -oP '^TODO_SYNC_HOST=\K.*' "$ENV_FILE" || echo 127.0.0.1)"

cat <<EOF

$(say 'Done.')

  Config    $ENV_FILE
  Database  $DATA_DIR/sync.db
  Logs      sudo journalctl -u todo-sync -f
  Restart   sudo systemctl restart todo-sync

The bootstrap token was written to $DATA_DIR/secret.txt and printed to the log:

  sudo journalctl -u todo-sync -n 40 --no-pager | grep -i token

Issue a token for a device:

  sudo -u $APP_USER TODO_SYNC_DB=$DATA_DIR/sync.db \\
    node $INSTALL_DIR/server/tokens.js add "Marco's phone"

EOF

if [[ "$BIND" == "127.0.0.1" ]]; then
  cat <<EOF
Listening on 127.0.0.1:$PORT, so nothing outside this machine can reach it yet.
Put a reverse proxy with TLS in front of it - see server/DEPLOY.md. Bearer
tokens over plain HTTP are readable by anything on the path.

EOF
else
  cat <<EOF
Listening on $BIND:$PORT. If a firewall is enabled:

  sudo ufw allow $PORT/tcp

EOF
fi
