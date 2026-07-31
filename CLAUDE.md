# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small, always-on-top desktop **todo widget** (a checklist-capable replacement
for Sticky Notes) that also runs on iOS and Android. You add tasks, check them
off — checked items animate away and are logged to a local SQLite database so a
history of completed work survives restarts.

Built with **Flutter** (Dart), plus a small **Node + Express** self-hosted sync
server.

## Where the code lives — read this first

| Path | Status |
| --- | --- |
| `app/` | **The client. All work goes here.** Flutter, all platforms. |
| `server/` | The self-hosted sync server. Node + Express + SQLite. |
| `src/`, `src-tauri/`, `index.html`, `vite.config.ts`, `package.json` | **Superseded. Do not edit.** |

`src/` + `src-tauri/` are the original Tauri v2 + TypeScript build, replaced by
`app/` in 0.7.0. They are kept only as a reference for the port and for the
legacy-database importer; they are not built, not shipped, and changing them has
no effect on the app. `git log -- src` shows nothing since the rewrite landed.

`FEATURES.md` is the running description of everything the app does, with a
changelog at the bottom. **Keep it updated whenever behaviour changes** — it is
the closest thing to a spec.

## Commands

Run from `app/` unless noted. The Flutter SDK must be on `PATH`.

| Task | Command |
| --- | --- |
| Run the app | `flutter run -d windows` |
| Analyze (lint + type-check) | `flutter analyze` |
| Test | `flutter test` |
| Test one file | `flutter test test/noise_test.dart` |
| Build a Windows release | `flutter build windows` |
| Add a dependency | `flutter pub add <pkg>` |
| Run the sync server (repo root) | `npm run server` |

There **is** a test suite — `app/test/` covers the local store, the sync merge,
the legacy import, reminders, parked groups, attachments, the encrypted journal,
notification scheduling, the tray and the noise synthesis. Run it. The server
has its own: `node --test
server/sync.test.js`, and a schema change on either side needs both.

**The dev build shares the real database.** `flutter run` opens the actual
`todo.db`, with real tasks in it. Don't script clicks against real rows.

## Architecture

### State

`AppState` (`app/lib/app_state.dart`) is a `ChangeNotifier` and the single
source of UI state. The shape is deliberately: *mutate the store, reload,
notify*. Reads are cheap (local SQLite, small lists) and it keeps the UI a pure
function of the database — which is what makes focus mode survive restarts.

`WidgetShell` in `app/lib/main.dart` is the one stateful shell; it owns the
window, the focus flight, the tray and the overlays.

### Data model — SQLite is the source of truth

`LocalStore` (`app/lib/sync/local_store.dart`) owns six tables: `workspaces`,
`parked_groups`, `tasks`, `attachments`, `side_thoughts`, `journal_entries`,
plus a key/value `settings` table used for UI prefs (last workspace, nudge,
sound volume).

Rows are keyed by **UUID**, not autoincrement — two devices offline at once used
to collide. Every row carries `updated_at` and `deleted_at`; deletes are
**tombstones**, so a removal actually propagates instead of looking like a row
the peer never saw.

State flags rather than separate tables:

- `completed_at IS NULL` → active task; non-null → done (shown in History).
- `in_progress` is the focus flag, and it is **exclusive and global**: setting it
  clears every other row, so at most one task is ever flagged.
- `resolved_at` on a side thought. Thoughts are *never* hard-deleted.
- `group_uuid` on a task is the parked flag: non-null means shelved in a
  `parked_groups` row, and shelved rows are excluded from `activeTasks`,
  `inProgressTask` and the reminder sweep. One nullable column rather than a
  second table, so parking keeps the row's uuid, history and reminder.

Two scopes that are easy to confuse: **side thoughts are global** (one pile,
every workspace, no `workspace_uuid` column) while **parked groups and the
journal are per-workspace** (they carry `workspace_uuid` and are reloaded on
every switch). Switching workspace is deliberately *not* blocked by pending
thoughts — only closing is. See `_switchWorkspace` in `main.dart` for why.

The **journal** is a per-workspace log of titled, timestamped notes
(`journal_entries`), with **optional** encryption. Plaintext by default; setting
a password turns it on. Each row's `encrypted` flag says whether its `title`/`text`
are **AES-256-GCM ciphertext** or plain UTF-8 — this per-row flag is what keeps
mixed and synced state honest (a device without the password shows an encrypted
row it cannot read as a `JournalItem.locked` placeholder, and can still keep its
own plaintext notes). `JournalCrypto` (`app/lib/journal_crypto.dart`) derives a
key from the password with PBKDF2 and holds it in memory only while unlocked; the
store, model and server see only the stored strings + flag. Enabling encryption
re-encrypts every existing row; removing it decrypts them back — both walk
`allJournalEntries()` (all workspaces: the vault is one password for the whole
journal). `AppState` builds `JournalItem`s (`journal`, held only while open and
not locked) for the UI. The salt/verifier are device-local `settings`
(`journal:*`), so they do **not** sync — a second device needs its own setup with
the same password. Entries sort on `created_at` (newest first); an edit moves
only `updated_at`. Deleting a workspace cascades to its journal (raw rows, no key
needed). `ui/journal_panel.dart` → `JournalView` owns the plaintext/setup/unlock/
list/editor states and intercepts Esc to back out of the editor before the shell
closes the pane.

**Per-workspace views live on the workspace bar, not the title bar.** Notes,
Parked and History are opened from the ▾ `_ViewsMenu` in `ui/workspace_bar.dart`
(they are about the current workspace); the title bar (`ui/title_bar.dart`) is
only window/global controls (sync, sound, pin, minimize, close). They are still
three mutually-exclusive content views alongside thoughts, driven by
`showHistory` / `showParked` / `showJournal` on `AppState`. Note the workspace
bar is hidden during focus mode, so those views are not reachable while focused —
that is fine, they are not things you reach for mid-focus.

A schema change here is still the **three edits** — but note the journal table
has version-specific splits in `local_store.dart` (`_journalTableV5` for the
v4→v5 upgrade path, `_journalTable` for a fresh current schema, plus `from < 6`
and `from < 7` ALTERs that add `title` and `encrypted`): when a table gains a
column in a later version, `_create` must build the final shape directly so it
does not collide with the migration that adds the column.

### Attachments: rows sync, bytes don't

`AttachmentStore` (`app/lib/sync/attachment_store.dart`) owns an
`attachments/` directory beside `todo.db`, with files named by the **SHA-256 of
their contents**, not by filename — that gives dedup for free, keeps a
user-supplied name out of a path, and makes the digest the address a future
`/blob/:sha256` endpoint would serve from.

The `attachments` row syncs; the file does not. **A device holding a row whose
bytes it has never seen is a supported state, not a bug** — the UI shows "not on
this device" rather than hiding it or failing. Two consequences worth keeping:

- Content addressing means two rows can share one file. Deleting a row must
  check `isBlobReferenced` before touching the bytes.
- A row tombstoned on another device arrives as a *merge*, so the local delete
  path never runs. `AppState.sweepAttachments()` at startup is the only thing
  that ever collects those bytes.

### Reminders fire differently per platform

`ReminderService` polls the database and surfaces the window — that is the whole
alert on desktop, and it needs no permissions. It does not carry to a phone,
which suspends timers in the background and never lets an app raise itself, so
`NotificationService` (`app/lib/notifications.dart`, mobile only) hands the OS
the armed reminders in advance. It **reconciles from a query** rather than
hooking the writes: `AppState.refreshTasks` rebuilds the whole schedule, which
is the only way a reminder merged in by sync gets scheduled at all. The poll
keeps running alongside it.

### Focus mode

▶ on a task hides everything but the title bar and flies the row into a tile in
the middle of the window.

- The flight is a FLIP in `_startFocus` / `_exitFocus` / `_flyingTile`. It
  interpolates the **box** (`Rect.lerp`) rather than applying a scale transform —
  a non-uniform scale would stretch the text.
- `_restingTileRect` *computes* the landing box rather than measuring it. It and
  the resting layout both use `_tileMargin`; **if those two disagree the tile
  jumps sideways the instant the flight ends.**
- The panels underneath only fade (`AnimatedOpacity`) and **keep their layout** —
  that is what lets the tile fly back to its exact row on the way out.
- Anything that must stay reachable while focused belongs in `TitleBar`, which is
  last in the `Stack` and so on top.
- Paths that touch hidden UI (the add field, history, settings, the close
  guard's footer flash) call `_exitFocus()` / `_closeSound()` first — otherwise
  they'd act on, or flash, something behind an overlay.

### Sound (`app/lib/sound/`)

`SoundService` is a `ChangeNotifier` owning one `media_kit` `Player`. Every play
path goes through `_beginRequest`, which stops the previous source, claims a
sequence number and sets the status line — the sequence number is what stops a
slow archive.org lookup from landing after the user moved on.

- `noise.dart` is pure maths and is unit-tested. Its three tuned properties
  (loop-seam crossfade, level trims, stereo decorrelation) are documented in the
  file header and asserted in `test/noise_test.dart`. **Don't touch the
  coefficients without re-running that test** — every failure mode here is
  inaudible right up until it isn't.
- `sources.dart` talks to archive.org and Radio Browser. Both are key-free;
  Radio Browser's client requirements (user agent, mirror fallback, play
  reporting) are honoured there.
- Synthesis runs on a background isolate via `compute` — on the main isolate it
  drops frames.

### Sync

`SyncService` reconciles in the background; the UI **never waits on it**. The
app always reads and writes its own local database first. Conflicts are last-
edit-wins per row. A merge that brings rows in must refresh what's on screen —
that's the `onChangesApplied` callback wired up in `main()`.

The offline queue is not a queue — it's the `dirty` column, which is why it
survives a crash and needs no replay log. `pendingCount()` counts it and
`describe()` surfaces it, so an unreachable server reads as queued, not lost.

`SyncService.resume()` is called from `didChangeAppLifecycleState` on the shell,
and exists because a suspended phone runs no timers. It is **rate-limited on
purpose**: desktop reports a lifecycle resume on every window focus change, and
this widget is focused constantly — without the gap it would sync on every
alt-tab, and restarting the poll each time would keep pushing the periodic sync
out of reach so it never fired at all.

### Window / look

Configured in `main()` via `window_manager` + `flutter_acrylic`: 340×480,
frameless (`TitleBarStyle.hidden`), transparent, always-on-top, acrylic.

- `TitleBar` is the drag handle, via `DragToMoveArea`. It must **not** wrap the
  buttons themselves or it swallows their clicks.
- `setPreventClose(true)` routes every close path (our ✕, Alt+F4, the tray's
  Quit) through `onWindowClose` — the single close guard.
- Design tokens live in `theme.dart` (`T.*`), ported from the old CSS. Durations
  that used to be duplicated between CSS and JS now have exactly one copy each.
- `UiScale` draws the whole widget ~28% larger on phones rather than forking
  every padding per platform. Keep it that way — a second set of mobile sizes
  would drift from the desktop one literal at a time.

## Gotchas

- **Don't edit `src/` or `src-tauri/`.** See the table above.
- A schema change is **three** edits, not one: the client (`local_store.dart`
  `_create` *and* `_upgrade`, plus the model), and the server (`db.js` schema,
  `addColumn` for existing databases, and the `TABLES` column list — a field
  missing there syncs as silently null forever).
- `server/db.js` builds its schema inside a **JS template literal**. A backtick
  in a SQL comment there ends the string and the file stops parsing.
- `MediaKit.ensureInitialized()` must run before any `Player` is constructed —
  it's the first thing in `main()`.
- The close guard refuses to close while side thoughts are pending. That is
  deliberate, not a bug; it's the point of the feature.
- `flutter analyze` is expected to be completely clean. Keep it that way.
