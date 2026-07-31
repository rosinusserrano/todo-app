#!/usr/bin/env bash
# Start the sync server on Linux (and macOS).
#
#   ./server/start-server.sh
#   ./server/start-server.sh --port 9000
#   ./server/start-server.sh --local-only
#
# The server itself already prints the token and the addresses to type into the
# app. What this adds is everything around that: it can be run from anywhere,
# installs dependencies on first use, and points at the firewall when that is
# the reason a phone cannot reach a server that is definitely running.

set -euo pipefail

PORT="${TODO_SYNC_PORT:-8787}"
LOCAL_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --port)       PORT="$2"; shift 2 ;;
    --port=*)     PORT="${1#*=}"; shift ;;
    --local-only) LOCAL_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Try --help." >&2
      exit 1 ;;
  esac
done

# The repo root is the parent of the directory holding this script, so this
# works from any working directory (including a symlink to it).
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
root="$(dirname "$here")"
cd "$root"

cyan() { printf '\033[36m%s\033[0m\n' "$1"; }
grey() { printf '\033[90m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

# --------------------------------------------------------------- prerequisites

if ! command -v node >/dev/null 2>&1; then
  echo "node was not found on PATH." >&2
  echo "Install Node.js (LTS), then run this again:" >&2
  echo "  Debian/Ubuntu:  sudo apt install nodejs npm" >&2
  echo "  Fedora:         sudo dnf install nodejs" >&2
  echo "  Arch:           sudo pacman -S nodejs npm" >&2
  echo "  macOS:          brew install node" >&2
  exit 1
fi
grey "node $(node --version) - $(command -v node)"

if [ ! -d node_modules ]; then
  echo
  cyan "First run: installing dependencies (this takes a minute)"
  # better-sqlite3 is a native module, so this may compile. On a bare Debian
  # that needs build-essential and python3.
  if ! npm install; then
    echo "npm install failed - see the output above." >&2
    echo "If it failed building better-sqlite3, you are missing a toolchain:" >&2
    echo "  sudo apt install build-essential python3" >&2
    exit 1
  fi
fi

# ------------------------------------------------------------------- firewall

# Only ever reports. Opening a port is a change to the machine, and a start
# script should not be making it without being asked.
if [ "$LOCAL_ONLY" -eq 0 ]; then
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    if ! ufw status | grep -q "$PORT"; then
      echo
      cyan "Firewall"
      echo "  ufw is active and does not mention port $PORT. If your phone cannot"
      echo "  reach the address below, allow it on your local network only:"
      echo
      yellow "    sudo ufw allow from 192.168.0.0/16 to any port $PORT proto tcp"
      echo
      echo "  Adjust the subnet if your LAN is not 192.168.x.x."
    fi
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    if ! firewall-cmd --list-ports 2>/dev/null | grep -q "$PORT/tcp"; then
      echo
      cyan "Firewall"
      echo "  firewalld is running and port $PORT is not open. If your phone cannot"
      echo "  reach the address below:"
      echo
      yellow "    sudo firewall-cmd --zone=home --add-port=$PORT/tcp --permanent"
      yellow "    sudo firewall-cmd --reload"
    fi
  fi
fi

# ---------------------------------------------------------------------- start

export TODO_SYNC_PORT="$PORT"
[ "$LOCAL_ONLY" -eq 1 ] && export TODO_SYNC_HOST=127.0.0.1

echo
cyan "Starting - Ctrl+C to stop"
grey "  The phone and this machine have to be on the same network."
grey "  Enter the address and token below in the app under the gear icon."

exec npm run server
