#!/usr/bin/env bash
#
# A second, throwaway copy of the whole thing, for trying a design out on a
# phone without touching the real one.
#
#   sudo server/setup-dev.sh todo-dev.example.com              # set up
#   sudo server/setup-dev.sh todo-dev.example.com --reset-data # re-copy the data
#
# What it makes:
#
#   - `todo-sync-dev.service`: this checkout's server, run as whoever owns the
#     checkout, on 127.0.0.1:8791. Run from the working tree on purpose - the
#     opposite of install-server.sh - because the point of a dev server is to
#     run the code being worked on. Restart it after changing server code:
#     `sudo systemctl restart todo-sync-dev`.
#   - /var/lib/todo-sync-dev: a **snapshot** of the live database, taken with
#     SQLite's online backup so the live server need not stop. Your usual token
#     therefore works on the dev site and the real tasks are on it - but it is a
#     copy, and nothing done there ever reaches the live server. Two things are
#     One thing is taken out of the copy, because it reaches outside it: push
#     subscriptions (and the VAPID keys they were made against), or the dev
#     server would send every reminder to your phone a second time. push.js
#     recreates the tables empty. Calendar feeds stay; they are only *read*.
#     The bootstrap secret is copied with it: the server adopts whatever secret
#     it finds, and a different one would revoke the copied token for `local`.
#   - /srv/todo-dev-web, owned by you, which the dev server serves. Publish to
#     it with `server/build-web.sh /srv/todo-dev-web` - no sudo.
#   - A Caddy site for the domain, proxying to the dev server.
#
# Idempotent. The data is copied only the first time, or with --reset-data.
# The browser keeps its own database per origin, so the dev site and the real
# one never share local state either.

set -euo pipefail

DOMAIN="${1:-}"
RESET=0
[[ "${2:-}" == "--reset-data" ]] && RESET=1

SERVICE=todo-sync-dev
PORT=8791
DATA_DIR=/var/lib/todo-sync-dev
WEB_DIR=/srv/todo-dev-web
LIVE_DB=/var/lib/todo-sync/sync.db
LIVE_ENV=/etc/todo-sync.env
ENV_FILE=/etc/todo-sync-dev.env
UNIT=/etc/systemd/system/$SERVICE.service
CADDYFILE=/etc/caddy/Caddyfile

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!! \033[0m%s\n' "$*"; }
die()  { printf '\n\033[1;31mxx \033[0m%s\n\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this with sudo."
[[ -n "$DOMAIN" ]] || die "Usage: sudo $0 <domain> [--reset-data]"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="$(stat -c '%U' "$REPO")"
[[ -f "$REPO/server/index.js" ]] || die "cannot find server/index.js next to this script"
[[ -d "$REPO/node_modules/better-sqlite3" ]] ||
  die "Install the server's dependencies first, as $OWNER: (cd $REPO && npm ci)"
command -v sqlite3 >/dev/null || die "sqlite3 is needed for the snapshot (apt install sqlite3)"

# ----------------------------------------------------------------- dirs

say "Directories"
mkdir -p "$DATA_DIR" "$WEB_DIR"
chown "$OWNER:$OWNER" "$DATA_DIR" "$WEB_DIR"
chmod 700 "$DATA_DIR"

# ----------------------------------------------------------------- data

if [[ $RESET -eq 1 || ! -f "$DATA_DIR/sync.db" ]]; then
  [[ -f "$LIVE_DB" ]] || die "no live database at $LIVE_DB"
  say "Snapshotting $LIVE_DB"
  systemctl stop "$SERVICE" 2>/dev/null || true
  rm -f "$DATA_DIR"/sync.db "$DATA_DIR"/sync.db-wal "$DATA_DIR"/sync.db-shm
  sqlite3 "$LIVE_DB" ".backup '$DATA_DIR/sync.db'"
  sqlite3 "$DATA_DIR/sync.db" <<'SQL'
DROP TABLE IF EXISTS push_subscriptions;
DROP TABLE IF EXISTS push_sent;
DELETE FROM meta WHERE key IN ('vapid_public', 'vapid_private');
SQL
  [[ -f /var/lib/todo-sync/secret.txt ]] &&
    cp /var/lib/todo-sync/secret.txt "$DATA_DIR/secret.txt"
  chown -R "$OWNER:$OWNER" "$DATA_DIR"
  chmod 600 "$DATA_DIR"/*
else
  say "Keeping the existing dev data (pass --reset-data to re-copy)"
fi

# ----------------------------------------------------------------- config

say "Writing $ENV_FILE"
{
  echo "# Dev copy of the Todo Widget sync server. Written by setup-dev.sh."
  echo "TODO_SYNC_PORT=$PORT"
  echo "TODO_SYNC_HOST=127.0.0.1"
  echo "TODO_SYNC_DB=$DATA_DIR/sync.db"
  echo "TODO_SYNC_WEB=$WEB_DIR"
  # Single sign-on, if the live server has it: the device grant needs no
  # redirect URI, so the same Keycloak client works from the dev site too.
  [[ -f "$LIVE_ENV" ]] && grep -E '^TODO_OIDC_' "$LIVE_ENV" || true
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ----------------------------------------------------------------- service

say "Installing $SERVICE"
cat > "$UNIT" <<EOF
[Unit]
Description=Todo Widget sync server (dev copy, $DOMAIN)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$OWNER
Group=$OWNER
WorkingDirectory=$REPO
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/node $REPO/server/index.js
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$DATA_DIR
RestrictAddressFamilies=AF_INET AF_INET6 AF_NETLINK

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1
systemctl restart "$SERVICE"

sleep 1
systemctl is-active --quiet "$SERVICE" || {
  journalctl -u "$SERVICE" -n 30 --no-pager || true
  die "$SERVICE did not start"
}

# ----------------------------------------------------------------- caddy

if grep -qE "^${DOMAIN//./\\.}[[:space:]]*\{" "$CADDYFILE"; then
  say "Caddy already has $DOMAIN"
else
  say "Adding $DOMAIN to $CADDYFILE"
  cp "$CADDYFILE" "$CADDYFILE.bak.$(date +%Y%m%d%H%M%S)"
  cat >> "$CADDYFILE" <<EOF

# Dev copy of todo, written by todo-app/server/setup-dev.sh.
$DOMAIN {
	reverse_proxy /api/events localhost:$PORT {
		flush_interval -1
	}
	reverse_proxy localhost:$PORT
}
EOF
  caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null ||
    die "Caddy rejected the config - the backup is beside it"
  systemctl reload caddy
fi

say "Done"
echo "   https://$DOMAIN  (empty until a web build is published:"
echo "   server/build-web.sh $WEB_DIR)"
