#!/usr/bin/env bash
#
# Update a running Todo Widget sync server to the current main.
#
#   cd ~/todo-app && sudo server/update-server.sh
#
# install-server.sh sets a deployment up; this is the one you run afterwards,
# every time. It does the same file dance in the same order and nothing else:
# pull, stop, back up (and verify it), copy, install deps, start, check.
#
# ---------------------------------------------------------------------------
# What this does NOT have to do, and why
#
# **There is no migration step, and there should never be one.** The schema
# lives in `init()` in server/db.js and runs on every boot: `CREATE TABLE IF NOT
# EXISTS` for tables, and `addColumn()` - which checks pragma_table_info first -
# for columns added later. Both are idempotent. So a database is migrated by
# *starting the new server on it*, which is exactly what a restart does.
#
# That is deliberate and it is worth keeping. A server that migrates itself at
# startup cannot be run against a database somebody forgot to migrate, and there
# is no second command whose absence is only discovered when a push starts
# failing with "no column named …".
#
# The backup below therefore is not there because the update is risky. It is
# there because *any* stop/start of a live database is the moment to have one,
# and because a restore is the only thing that helps if a future release does
# get a migration wrong.
#
# ---------------------------------------------------------------------------
# What it will NOT fix for you
#
# The reverse proxy. Instant sync (`GET /api/events`) is a response that never
# ends, and Caddy buffers proxied responses by default - so without
# `flush_interval -1` the stream is buffered into uselessness and every client
# quietly falls back to polling once a minute. That config is on the proxy host,
# which is not this machine. See DEPLOY.md. The check at the end of this script
# tests the server directly, so it passes whether or not the proxy is right.

set -euo pipefail

INSTALL_DIR=/opt/todo-sync
DATA_DIR=/var/lib/todo-sync
BACKUP_DIR="$DATA_DIR/backups"
SERVICE=todo-sync
APP_USER=todosync

# Where the clone is: the parent of the directory holding this script.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m!! \033[0m%s\n' "$*"; }
die()  { printf '\n\033[1;31mxx \033[0m%s\n\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this with sudo."
[[ -d "$INSTALL_DIR" ]] || die "$INSTALL_DIR does not exist - run install-server.sh first."

PORT="$(grep -oP '(?<=^TODO_SYNC_PORT=)\d+' /etc/todo-sync.env 2>/dev/null || echo 8787)"
DB="$(grep -oP '(?<=^TODO_SYNC_DB=).*' /etc/todo-sync.env 2>/dev/null || echo "$DATA_DIR/sync.db")"

# ----------------------------------------------------------------- pull

say "Pulling $REPO"
cd "$REPO"
if [[ -n "$(git status --porcelain)" ]]; then
  warn "The clone has local changes. Pulling anyway; they are not deployed"
  warn "unless they are committed - this script copies the working tree."
fi
# Run as whoever owns the clone, not as root, or the next plain `git pull` in
# that directory fails on files root just rewrote.
sudo -u "$(stat -c '%U' "$REPO")" git pull --ff-only

BEFORE="$(git rev-parse --short HEAD)"
say "Now at $BEFORE — $(git log -1 --pretty=%s)"

# ----------------------------------------------------------------- stop

say "Stopping $SERVICE"
systemctl stop "$SERVICE"

# ----------------------------------------------------------------- backup
#
# *After* the stop, deliberately. The online backup API below can snapshot a
# live database, so this is not strictly required - but a snapshot taken with
# nothing writing is one fewer thing to reason about when you are restoring it
# at two in the morning, and the stop costs nothing here because it has to
# happen anyway.

if [[ -f "$DB" ]]; then
  mkdir -p "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  SNAPSHOT="$BACKUP_DIR/sync-$STAMP.db"
  say "Backing up to $SNAPSHOT"

  # **One self-contained file**, always. This used to `cp` the three WAL files
  # side by side when sqlite3 was missing, and that was a trap rather than a
  # backup: this database runs in WAL mode and does not checkpoint on its own,
  # so `sync.db` was 4KB of header while `sync.db-wal` held all 3MB of real
  # data. The snapshot .db on its own did not even have the tables in it - and
  # the restore line this script prints copies exactly that one file back. A
  # backup you cannot restore from is worse than none, because you rely on it.
  #
  # better-sqlite3's `.backup()` runs SQLite's online backup API, which walks
  # the *logical* contents and so folds the WAL in. It needs no new package:
  # it is the server's own dependency, sitting in $INSTALL_DIR/node_modules,
  # and a machine where it is missing is a machine where the server cannot run.
  if node -e '
      const Database = require(process.argv[1] + "/node_modules/better-sqlite3");
      const db = new Database(process.argv[2], { readonly: true });
      db.backup(process.argv[3])
        .then(() => { db.close(); process.exit(0); })
        .catch((e) => { console.error(String(e)); process.exit(1); });
    ' "$INSTALL_DIR" "$DB" "$SNAPSHOT"; then
    :
  elif command -v sqlite3 >/dev/null 2>&1; then
    warn "node backup failed; falling back to the sqlite3 CLI."
    sqlite3 "$DB" ".backup '$SNAPSHOT'"
  else
    die "Could not take a consistent backup, and refusing to update without one.
     Install sqlite3 (sudo apt install sqlite3) and run this again."
  fi

  # Prove it before trusting it. A snapshot that opens but has no tables is
  # exactly the failure this whole block exists to prevent, so it is worth the
  # one query it costs to find out now rather than during a restore.
  ROWS="$(node -e '
      const Database = require(process.argv[1] + "/node_modules/better-sqlite3");
      const db = new Database(process.argv[2], { readonly: true });
      process.stdout.write(String(db.prepare("SELECT COUNT(*) n FROM tasks").get().n));
    ' "$INSTALL_DIR" "$SNAPSHOT" 2>/dev/null || echo "")"
  [[ -n "$ROWS" ]] || die "The snapshot is not a readable database. Aborting."
  echo "  snapshot holds $ROWS task rows"
  chown -R "$APP_USER:$APP_USER" "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  # Keep the last ten. A daily-ish update and a database this size means that
  # is weeks of history for a few megabytes.
  ls -1t "$BACKUP_DIR"/sync-*.db 2>/dev/null | tail -n +11 | xargs -r rm -f
else
  warn "No database at $DB yet - nothing to back up."
fi

# ----------------------------------------------------------------- files
#
# Same shape as install-server.sh: the server is copied *out of* the clone, so
# a later `git pull` cannot swap code under a live process. Only the server and
# its manifest - the Flutter app, the dead Tauri tree and the git history have
# no business here.

say "Installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR/server"
cp -r "$REPO/server" "$INSTALL_DIR/server"
cp "$REPO/package.json" "$INSTALL_DIR/package.json"
[[ -f "$REPO/package-lock.json" ]] && cp "$REPO/package-lock.json" "$INSTALL_DIR/"

# Tests and any local dev database must not ship. `server/data` in particular:
# copying it over would put a *developer's* sync.db on the server, and the real
# one is in DATA_DIR precisely so this cannot reach it - but there is no reason
# to leave a stray copy lying about either.
rm -f "$INSTALL_DIR"/server/*.test.js
rm -rf "$INSTALL_DIR/server/data"
rm -f "$INSTALL_DIR"/server/update-server.sh "$INSTALL_DIR"/server/install-server.sh

say "Installing production dependencies"
cd "$INSTALL_DIR"
if [[ -f package-lock.json ]]; then
  npm ci --omit=dev --no-audit --no-fund
else
  npm install --omit=dev --no-audit --no-fund
fi

chown -R root:root "$INSTALL_DIR"

# ----------------------------------------------------------------- start

say "Starting $SERVICE"
systemctl start "$SERVICE"

# systemd returns as soon as the process is spawned; the schema work and the
# port bind happen just after. Give it a moment before calling it broken.
for _ in $(seq 1 20); do
  systemctl is-active --quiet "$SERVICE" && break
  sleep 0.5
done

if ! systemctl is-active --quiet "$SERVICE"; then
  warn "$SERVICE did not come up. Recent log:"
  journalctl -u "$SERVICE" -n 40 --no-pager || true
  die "Update failed. The database is untouched; restore from $BACKUP_DIR if needed."
fi

# ----------------------------------------------------------------- check

say "Checking the server answers"

# Polled, not asked once. `systemctl is-active` goes true the moment the process
# is *spawned* - a Type=simple unit says nothing about whether Express has bound
# the port yet - so a single curl here raced the startup and reported a
# perfectly healthy deploy as a failure. That is the worst kind of false alarm:
# it sends you looking for a problem that is not there while the update it just
# performed is actually fine.
HEALTH=""
for _ in $(seq 1 30); do
  HEALTH="$(curl -fsS --max-time 3 "http://127.0.0.1:$PORT/api/health" 2>/dev/null || true)"
  [[ "$HEALTH" == *'"service":"todo-widget-sync"'* ]] && break
  sleep 0.5
done

if [[ "$HEALTH" != *'"service":"todo-widget-sync"'* ]]; then
  warn "No answer on 127.0.0.1:$PORT after 15s. Recent log:"
  journalctl -u "$SERVICE" -n 40 --no-pager || true
  die "Health check failed. The database is untouched; restore from $BACKUP_DIR if needed."
fi
echo "  health   $HEALTH"

# The instant-sync route. Unauthenticated it must answer 401 - that is proof
# the route *exists* and is behind auth, which is exactly what wants checking
# after an update that added it. A 404 here means the new code is not running.
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  "http://127.0.0.1:$PORT/api/events" || true)"
case "$CODE" in
  401|403) echo "  events   $CODE (route present, behind auth — correct)" ;;
  404)     warn "  events   404 — the running code predates instant sync." ;;
  *)       warn "  events   $CODE — unexpected; check the log." ;;
esac

cat <<EOF

  Updated to $BEFORE.

  Logs      sudo journalctl -u $SERVICE -f
  Backups   $BACKUP_DIR
  Restore   sudo systemctl stop $SERVICE
            sudo -u $APP_USER cp $BACKUP_DIR/<snapshot>.db $DB
            sudo -u $APP_USER rm -f $DB-wal $DB-shm
            sudo systemctl start $SERVICE

            The rm is not optional. A restored .db next to the *old* write-ahead
            log is not the database you restored - SQLite replays that log over
            the top of it, and you get the state you were trying to get rid of.

  If instant sync still does not reach your devices, it is the reverse proxy:
  Caddy needs 'flush_interval -1' inside the reverse_proxy block. See DEPLOY.md.

EOF
