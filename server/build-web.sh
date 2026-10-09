#!/usr/bin/env bash
#
# Build the web client, and publish it if a web root is given.
#
#   ./server/build-web.sh                 # build into app/build/web only
#   ./server/build-web.sh /srv/todo-web   # build, then publish there
#
# The sync server serves whatever is in TODO_SYNC_WEB (see WEB_ROOT in
# config.js) and reads it per request, so publishing is a copy: no restart, and
# no sudo once the directory belongs to whoever runs this. A phone picks the new
# build up on its next reload - every file is served `no-cache`.
#
# Two steps, and the first is the one that is easy to forget: `sqlite3.wasm` and
# `sqflite_sw.js` are fetched rather than committed (see .gitignore), and a
# build without them loads, paints, and then fails on the first database call
# with nothing useful in the console.
#
# Nothing is compiled in. The server is on the open internet, and a token in
# the bundle would be a token anyone can fetch; the sync screen prefills the
# page's own address, so the token is the only thing to type, once per browser.

set -euo pipefail

TARGET="${1:-}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$(cd "$here/.." && pwd)/app"

if ! command -v flutter >/dev/null 2>&1; then
  if [[ -x "$HOME/flutter/bin/flutter" ]]; then
    export PATH="$HOME/flutter/bin:$PATH"
  else
    echo "flutter is not on PATH, and not at ~/flutter/bin either." >&2
    exit 1
  fi
fi

cd "$app"

echo "==> Dependencies"
flutter pub get

# Version-matched to the sqlite3 package pub just resolved, which is why this
# runs on every build rather than once.
echo "==> SQLite WASM + shared worker"
dart run sqflite_common_ffi_web:setup

echo "==> Building"
flutter build web --release --no-wasm-dry-run

test -s build/web/sqlite3.wasm
test -s build/web/sqflite_sw.js
test -s build/web/main.dart.js

if [[ -z "$TARGET" ]]; then
  echo
  echo "Built $app/build/web (not published - pass a web root to publish)."
  exit 0
fi

echo "==> Publishing to $TARGET"
# index.html last: it is what names the build, so a browser that reloads in the
# middle of the copy gets the old one whole or the new one whole, never an
# index.html pointing at a main.dart.js that has not arrived yet.
rsync -a --delete --exclude index.html build/web/ "$TARGET/"
cp build/web/index.html "$TARGET/index.html.tmp"
mv "$TARGET/index.html.tmp" "$TARGET/index.html"

echo
echo "Published. Reload the page to get it."
