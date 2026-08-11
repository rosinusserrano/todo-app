# Todo Widget

A small, always-on-top desktop **todo widget** — a checklist-capable
replacement for Sticky Notes — that also runs on iOS and Android. Add tasks,
check them off (they animate away), and every completed item is logged to a
local SQLite database, so a history of what you got done survives restarts.

Beyond the list it has a calendar you can plan tasks into, a focus mode, an
encrypted journal, attachments, concentration noise, reminders (including
recurring ones), and optional sync across your devices through a small
self-hosted server.

Built with **Flutter** (Dart) for every platform, plus a **Node + Express**
sync server you run yourself.

> **Note on layout:** `src/` and `src-tauri/` are the original Tauri v2 +
> TypeScript build. They were superseded by `app/` in 0.7.0 and are kept only
> as a reference for the port and the legacy-database importer. They are not
> built and not shipped — don't edit them.

---

## Running the app

Prerequisites: the [Flutter SDK](https://docs.flutter.dev/get-started/install)
on your `PATH`. On Windows you also need the MSVC C++ build tools.

```sh
cd app
flutter run -d windows     # or -d macos, -d linux, -d ios, -d android
```

Other commands, all from `app/`:

| Task | Command |
| --- | --- |
| Analyze (lint + type-check) | `flutter analyze` |
| Test | `flutter test` |
| Test one file | `flutter test test/noise_test.dart` |
| Release build | `flutter build windows` |

> **`flutter run` opens your real database.** The dev build shares the same
> `todo.db` as the installed app, with your actual tasks in it.

### Installing it for daily use (Windows)

```powershell
.\install-windows.ps1
```

This builds, then copies the bundle **out of the working tree** to
`%LOCALAPPDATA%\Programs\Todo Widget` and makes a shortcut. That matters:
running the daily driver straight out of `app\build\` means the next
`flutter build` overwrites the exe underneath it. Your database lives in
`%APPDATA%\com.marco\todo_widget` and is never touched by reinstalling.

---

## The sync server

Sync is **optional**. The app is fully functional without it — every device
reads and writes its own local SQLite first, and the server only reconciles.
If you never configure one, nothing phones home.

When you do run one, it holds **several accounts in one database**, so it can
serve you and other people from a single deployment.

### Quick start (any machine, for a LAN)

From the repo root:

```sh
npm install
npm run server
```

It prints the address and a bootstrap token on first run:

```
Todo sync server listening on http://0.0.0.0:8787
  LAN address:  http://192.168.2.184:8787
  Token:        s3cr3t-bootstrap-token-printed-once
```

Helper scripts that also handle first-run setup and firewall hints:

| Platform | Script |
| --- | --- |
| Windows | `server\start-server.ps1` |
| macOS / Linux (dev) | `server/start-server.sh` |
| Ubuntu server (systemd) | `server/install-server.sh` — see below |

### Deploying on an Ubuntu VM

```sh
sudo ./server/install-server.sh
```

Installs Node if missing, creates a `todosync` service user, copies the server
to `/opt/todo-sync`, writes `/etc/todo-sync.env`, and installs and starts a
systemd unit. Then:

```sh
sudo systemctl status todo-sync
sudo journalctl -u todo-sync -f
```

Configuration lives in `/etc/todo-sync.env`. See
[server/DEPLOY.md](./server/DEPLOY.md) for TLS, reverse proxying and Keycloak.

> Put it behind a reverse proxy with TLS if it is reachable from the internet.
> Bearer tokens over plain HTTP are readable by anything on the path.

### Configuration

All optional:

| Variable | Default | Meaning |
| --- | --- | --- |
| `TODO_SYNC_PORT` | `8787` | Port to listen on |
| `TODO_SYNC_HOST` | `0.0.0.0` | Set `127.0.0.1` to refuse LAN clients |
| `TODO_SYNC_DB` | `server/data/sync.db` | Database file |
| `TODO_SYNC_SECRET` | generated into `secret.txt` beside the database | Bootstrap token |
| `TODO_OIDC_ISSUER` | — | Keycloak realm URL; enables SSO (see below) |
| `TODO_OIDC_CLIENT_ID` | `todo-widget` | The public client devices log in with |
| `TODO_OIDC_ADMIN_ROLE` | `todo-admin` | Realm role granting admin |

### Accounts and tokens

```sh
npm run token -- list
npm run token -- add "Marco's phone"     # prints the token once
npm run token -- revoke <id>
```

Tokens are stored as a SHA-256, never in the clear, which is why one is
**printed exactly once**. Lose it and you issue another and revoke the old —
a two-second operation. Both the CLI and the in-app admin panel work against a
running server; no restart is needed for an issue or a revoke.

The bootstrap secret is not a special code path: it is *adopted into* the
tokens table at startup as the token of the user `local`, which is the id every
row written before multi-user already carries. So there is exactly one way to
authenticate, and a revoked token is genuinely revoked.

---

## Connecting the app to your server

In the app: **title bar → ⚙ Settings → Sync**.

1. **Server address** — `todo.example.com`, or `192.168.2.184:8787`. The scheme
   is optional and defaults to `http://` for a bare host:port.
2. **Connect** — the app asks the server how it wants you to sign in, and shows
   the right thing next. A wrong address reports itself as a wrong address here
   rather than later as an auth failure.
3. Then either:
   - **Sign in with your account** — if the server uses SSO. Your browser
     opens at your own login page; approve it and the app takes over. Nobody
     has to issue you anything.
   - **Token** — if it does not. Paste what the server printed, then
     **Save & sync**.

The UI never waits on sync. Conflicts resolve last-edit-wins per row, and the
offline queue is just the `dirty` column, so a crash or an unreachable server
leaves work **queued, not lost** — the title bar's sync indicator says how many
rows are waiting.

### Signing in with Keycloak (SSO)

If the server is configured with `TODO_OIDC_ISSUER`, pressing **Connect**
replaces the token field with **Sign in with your account**. Pressing it opens
your browser at your identity provider's own login page — Google, or whatever
the realm brokers — and after you approve, the app picks the session up and
refreshes it on its own from then on.

**No token has to be issued for a new person.** Their account on the sync
server is created the first time they sign in. The admin's only job is running
the server and deciding, in Keycloak, who is allowed to reach it.

Under the hood it is the OAuth 2.0 Device Authorization Grant, which is why the
dialog also shows a short code: the browser is opened for you at a URL that
already contains it, but if the browser cannot be opened — or you would rather
approve on your phone — the code is the way to do that, and the app keeps
waiting either way.

Your Keycloak client needs to be **public** with **OAuth 2.0 Device
Authorization Grant** enabled. Full setup in
[server/DEPLOY.md](./server/DEPLOY.md#keycloak).

---

## Where things live

| Path | What |
| --- | --- |
| `app/` | **The client.** Flutter, all platforms. |
| `app/lib/main.dart` | The window shell: title bar, tray, overlays, focus flight |
| `app/lib/app_state.dart` | Single source of UI state |
| `app/lib/sync/` | Local SQLite store, models, sync client/service |
| `app/lib/ui/` | Widgets, including `ui/calendar/` |
| `app/test/` | The test suite — run it |
| `server/` | The sync server. Node + Express + SQLite. |
| `src/`, `src-tauri/` | **Superseded.** Do not edit. |

Docs:

- **[FEATURES.md](./FEATURES.md)** — everything the app does, plus the
  changelog. The closest thing to a spec.
- **[ROADMAP.md](./ROADMAP.md)** — agreed and designed, not yet built.
- **[CLAUDE.md](./CLAUDE.md)** — architecture notes and the reasoning behind
  the decisions that are easy to undo by accident.
- **[server/DEPLOY.md](./server/DEPLOY.md)** — running the server for real.

## Tests

```sh
cd app && flutter test      # client
node --test server          # server
```

A schema change needs both: the client (`local_store.dart` `_create` *and*
`_upgrade`, plus the model) and the server (`db.js` schema, `addColumn`, and
the `TABLES` column list).
