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
| Add a user / token to the server | `npm run token -- add "<name>"` (also `list`, `revoke <id>`) |
| Start the server with setup + firewall help | `server\start-server.ps1` / `server/start-server.sh` |
| Install the built app for daily use (repo root) | `install-windows.ps1` |

`install-windows.ps1` builds, then copies the bundle **out of the working tree**
to `%LOCALAPPDATA%\Programs\Todo Widget` and shortcuts it — running the daily
driver straight out of `app\build\` means the next `flutter build` overwrites the
exe under it, and the `HKCU\...\Run` entry "Start with Windows" wrote points into
a build directory. The install directory is mirrored on every run; the database
is not in it (`%APPDATA%\com.marco\todo_widget`), so reinstalling never touches
data.

There **is** a test suite — `app/test/` covers the local store, the sync merge,
the legacy import, reminders, parked groups, attachments, the encrypted journal,
the calendar, notification scheduling, the tray and the noise synthesis. Run it.

`test/noise_test.dart`'s "nothing clips" is **flaky and has been since before
the calendar landed**: `noise.dart` uses an unseeded `Random()`, and at the
documented ~0.19 RMS a peak of 1.0 is 5.26σ, so across the 2.6M samples in a
buffer you expect ~0.37 exceedances — roughly a third of runs have one sample
clamped. A single clamped sample in 2.6M is inaudible, but the invariant in the
file header does say "stays under 1.0 peak", so this is a real if minor
discrepancy rather than a bad assertion. Don't "fix" it by loosening the test. The server
has its own: `node --test
server/sync.test.js`, and a schema change on either side needs both.

**The dev build shares the real database.** `flutter run` opens the actual
`todo.db`, with real tasks in it. Don't script clicks against real rows.

**`test/sync_integration_test.dart` writes to whatever server you point it at.**
Every `device()` in it is a real client that pushes its rows into that account
and leaves them there. Point it at a scratch server
(`TODO_SYNC_DB=/tmp/scratch.db TODO_SYNC_PORT=8797 npm run server`), never the
one your devices use — running it against the live server is how six duplicate
"Tasks" workspaces and a stranded "hello from device A" got into a real account.

## Architecture

### State

`AppState` (`app/lib/app_state.dart`) is a `ChangeNotifier` and the single
source of UI state. The shape is deliberately: *mutate the store, reload,
notify*. Reads are cheap (local SQLite, small lists) and it keeps the UI a pure
function of the database — which is what makes focus mode survive restarts.

`WidgetShell` in `app/lib/main.dart` is the one stateful shell; it owns the
window, the focus flight, the tray and the overlays.

### Data model — SQLite is the source of truth

`LocalStore` (`app/lib/sync/local_store.dart`) owns eight tables: `workspaces`,
`parked_groups`, `tasks`, `attachments`, `side_thoughts`, `journal_entries`,
`calendars`, `calendar_events`, plus a key/value `settings` table used for UI
prefs (last workspace, nudge, sound volume, calendar mode/scope/hidden/block
target).

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
- `event_uuid` on a task is the **planned-into-a-block** pointer, and it follows
  `group_uuid`'s shape for the same reasons — except that it does **not** take
  the row off `activeTasks`. Planning says *when*, not "put this away"; a plan
  that hid its own contents would be a way to lose tasks. The cost of one column
  is that a task is in at most one block, which is the right trade ("do it
  twice" is two tasks) but is not negotiable afterwards without a join table.

**Ids that two devices must agree on are derived, never generated.** The seeded
default workspace is `LocalStore.defaultWorkspaceUuid`, a fixed constant, for
the same reason `Calendar.forWorkspace` derives its id: a generated one meant
every fresh database — a new phone, a reinstall, every in-memory store an
integration test opens — seeded a *different* row that happened to be named
"Tasks". Sync then behaved perfectly correctly and kept them all, because they
were not versions of one row, they were different rows; a real account
accumulated seven. Anything provisioned independently on two devices needs a
derived id or it can only ever merge as siblings. The v9 migration
(`_foldSeededDefaults`) folds the strays already out there onto the canonical
row — re-parenting their contents, tombstoning the husks, and marking both
dirty so the collapse propagates rather than having to be repeated per device.
It matches on name *and* colour, so a workspace the user renamed or recoloured
is theirs and is left alone.

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

A schema change here is still the **three edits** — but note the version-specific
table splits in `local_store.dart`. The journal has `_journalTableV5` for the
v4→v5 upgrade path and `_journalTable` for a fresh current schema, plus `from <
6` / `from < 7` ALTERs adding `title` and `encrypted`; attachments now have the
same shape, `_attachmentsTableV4` versus `_attachmentsTable`, with `from < 8`
adding `event_uuid`. When a table gains a column in a later version, `_create`
must build the final shape directly so it does not collide with the migration
that adds the column.

The migration tests build old databases by hand or by rolling a fresh one back
(`DROP TABLE` + `setVersion`). **A new table or column means updating those
fixtures** — they will otherwise either collide on something `_create` already
made, or fail in a later step that alters a table the fixture never created.
A rolled-back fixture has to give the *column* back too (`DROP INDEX` first;
SQLite refuses to drop a column an index is built on — see the v10 `event_uuid`
lines in `attachments_test`, `calendar_test` and `default_workspace_test`), and
a hand-built one has to contain every table a later step touches, which is why
`journal_test` carries `_v9Tasks` and `_v4Attachments` as scaffolding.

### The calendar

Two tables. `calendars` is a coloured container; `calendar_events` is a block of
time on one. The rules that are not obvious from the schema:

- **A workspace's calendar has the workspace's uuid.** `Calendar.forWorkspace`
  derives it rather than generating one. Rows are provisioned *lazily*
  (`ensureWorkspaceCalendars`, called on every calendar refresh) because sync
  can bring a workspace in from another device with no local write path running
  — and if two devices each provision while offline, deriving the id is what
  makes them produce the same row instead of two siblings sync can only merge
  as duplicates.
- A workspace calendar's **name and colour come from the workspace**, not from
  its own columns (`AppState.calendarName` / `calendarColor`). The columns exist
  for standalone calendars. A second place to edit them would be a second source
  of truth.
- `start_at`/`end_at` are **UTC instants** (`reminderStamp`), not wall-clock
  readings. `reminderStamp` truncates to milliseconds, and that is load-bearing:
  `eventsBetween` compares stamps **as strings** in SQL, and `toIso8601String`
  prints three fractional digits at zero microseconds and six otherwise — so
  `…00.000Z` would sort *after* `…00.000500Z`.
- `eventsBetween` tests **overlap** (`start_at < to AND end_at > from`), not
  containment. A query keyed on `start_at` alone silently drops exactly the
  multi-day events the spanning band exists for.
- `notify_minutes` on an event is a **three-state column**: null inherits the
  calendar's rule, `CalendarEvent.notifySilent` (-1) overrides it to quiet, any
  other value is a lead time. One column rather than a flag plus a value,
  because two columns can disagree after a merge. Note `copyWith` cannot tell
  "leave alone" from "set back to inherit" — that is what `clearNotify` is for.
- Notifications for tasks and events are rewritten in **one** call
  (`NotificationService.reschedule`), because the cancel is global; two calls
  would each wipe the other's work.
- The calendar is the one view that replaces the **whole window** rather than
  the content area. It lives on the *title* bar, not the workspace bar's views
  menu, because it can show every workspace at once. `_toggleCalendar` used to
  resize the window to 920×640 and centre it on the way in; it does **not** any
  more — see `layout.dart` below, and don't put it back.
- The week has two renderings and the mode has only one meaning: `TimeGridView`
  when `Layout.weekGridFits`, `AgendaView` when it does not. Day always uses the
  grid (one column fits anywhere) and the year reflows on its own, so this is
  one fallback rather than a parallel set of narrow views.
- **A phone gets the grid, not the agenda.** `TimeGridView` has a second,
  *compact* geometry it switches to when a day column falls under
  `kCompactColumn`: `kGutterCompact` (22px, hour labels as "9" not "09:00"),
  weekday initials, and title-only blocks — which is how a 393pt iPhone shows
  seven real columns of ~45px, the size every phone calendar draws one at. The
  view decides it once per build from its measured width and passes `gutter` +
  `compact` down; **nothing may read `kGutter` directly** or the painter, the
  labels and the hit maths end up drawing to different grids. `_pointToSlot`
  reads the `_gutter` recorded during build for the same reason `WidgetShell`
  keeps `_layout`: the drag runs from a pointer callback with no build context.
  `Layout.weekGridFits` measures against `kGutterCompact` because a week that
  narrow is drawn with the narrow gutter. The agenda is still what the 260px
  resize floor gets.
- Drag-to-create is split by input device in `time_grid.dart`: a mouse drag
  creates (Flutter's default `dragDevices` excludes the mouse, so it is not
  competing with the scroll view), while touch uses long-press-then-drag because
  a one-finger drag has to scroll. Both live *below* the event blocks in the
  grid's `Stack`, not around them — an ancestor is handed the pointer even when
  a child took it, so creating used to run on top of opening and a click on an
  event wrote a stray 15-minute block behind the editor.
- **Time-block mode is one nullable uuid**, `AppState.timeBlockCalendarUuid`,
  and it is resolved through `visibleCalendars` rather than `calendars` — the
  target can go away underneath the setting (unticked, scope narrowed, workspace
  deleted), and "off" is then what the strip on screen already says. It changes
  only what `_createEvent` in `main.dart` does with a finished drag: save
  directly, titled `calendarName(target)`, instead of opening the editor. The
  grid is not told about the mode, only about `blockTitle`/`blockColor` for the
  draft — the draft is the sole preview of what letting go will write.
- **The session ("Now") is derived, never stored.** `AppState.refreshSessions`
  asks the store which events cover this instant and what is planned into each;
  there is no "current session" row, so nothing can go stale or disagree with
  the clock. Three things about it:
  - It is driven by `ReminderService.onTick` as well as by `refreshTasks` /
    `refreshEvents`, because a block *starting* writes nothing to the database
    and only a clock can notice it. That callback exists so there is one poll,
    not two to keep in step.
  - It **ignores** `calendarScope` and `hiddenCalendars` on purpose — those are
    view filters, and they are also loaded lazily, so honouring them would make
    the banner depend on whether the calendar had been opened this run.
  - It notifies on every tick only while the view is open (the countdown is
    live); otherwise it compares a signature first, so a quiet poll does not
    rebuild the widget every 20 seconds.
- A **locally** deleted event releases its tasks (`_releaseEventTasks`, called
  from `deleteEvent` and the calendar cascade). One tombstoned on another device
  arrives as a merge and the local delete path never runs, so a dangling
  `event_uuid` is a supported state — the task is still on the list, it just
  never turns up in a session. Same shape as the attachment-row-without-bytes
  case, minus the sweep, because nothing is leaked by it.
- The year view's month tiles are **always six week rows** (`_weekRows`), padded
  with blanks. A month needs four to six depending on where its 1st falls, and
  sizing each tile to its own month left a `Wrap` run ragged. Don't make it
  adaptive again to save a row of pixels.

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
  the resting layout both take their width from `Layout.focusTileWidth` (which
  is capped, so a wide window gets a centred tile rather than a 1400px one);
  **if those two disagree the tile jumps sideways the instant the flight ends** —
  which is why neither works the width out for itself.
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

### Users on the server (`server/users.js`)

The server holds **several accounts in one database**, partitioned by the
`user_id` that was already on every row and in every query. There is no per-user
file: that would need its own connection, its own `meta.seq` and its own
migration run for isolation the `WHERE` clause already provides. The client is
unchanged — an account is just a different token in the same address+token
settings.

- `identify()` in `auth.js` is the **only** authority, and it consults the
  tokens table and nothing else. There is deliberately no "…or the configured
  secret" fallback: that branch would mean a revoked token is not revoked.
- The bootstrap secret (`secret.txt` / `TODO_SYNC_SECRET`) still works because
  `adoptBootstrapSecret()` writes it *into* that table at startup as the token
  of user `local` — which is the id every pre-multi-user row already carries, so
  the owner keeps their data. It is idempotent, and it **rotates**: changing the
  secret revokes the previously adopted one but never a device's token.
- Tokens are stored as a **SHA-256, never the token**. Hence the public `id`
  column — you cannot revoke what you cannot name — and hence "printed once".
  Lookup is by hash on a UNIQUE index, so there is no timing signal and no scan.
- **Cursors are per user** (`userCursor`), not `currentSeq`. `meta.seq` is one
  global counter (correct: it only has to be monotonic, and a user's rows can
  never land below a cursor they already hold), but handing that counter back
  would make every client resync every time *somebody else* wrote. `sync()`
  computes it inside the same transaction as the pull, for the same reason the
  pull is in there at all.
- **Admin is a role on an ordinary account** (`users.is_admin`), not a second
  credential — the token that syncs is the token that administers, so there is
  nothing extra to steal. `adoptBootstrapSecret` sets it on `local` **on every
  start**, not just at creation: holding the secret the server prints on its own
  console *is* being the operator, and a server left with no admin could only be
  fixed from the machine. `setAdmin` refuses to remove the last one.
- Administration has **two front ends over one model**: `server/tokens.js`
  (`npm run token`) and the `/api/admin/*` routes behind `adminOnly`, which is
  what the app's panel drives. The routes are not a second auth surface — they
  are a role check on the bearer token already in use — but the CLI is the one
  that still works when nobody can log in. Both run against a live server: WAL
  allows the second writer, and the server reads the tokens table per request
  rather than caching it, so issue and revoke take effect with no restart.
- Deleting an account is `purgeUser` in **db.js**, not users.js, because it
  means deleting rows and `TABLES` is what says which. It hard-deletes rather
  than tombstoning: tombstones exist so a *peer* learns of a removal, and the
  peers here are the devices being cut off at that same moment.
- `server/config.js` exists so the CLI and the server cannot disagree about
  which database file they mean. A CLI minting tokens into a different file than
  the server reads fails as "I made a token and it says invalid".

### Window / look

Configured in `main()` via `window_manager` + `flutter_acrylic`: 340×480,
frameless (`TitleBarStyle.hidden`), transparent, always-on-top, acrylic.

- `TitleBar` is the drag handle, via `DragToMoveArea`. It must **not** wrap the
  buttons themselves or it swallows their clicks.
- **Anything long-lived that covers the content area is a sheet in the shell's
  `Stack`, never a `showDialog` route.** A modal route's barrier covers the
  whole window — including the title bar — so an open dialog leaves the window
  undraggable, unpinnable and unclosable. `SoundSheet` and `SettingsSheet` both
  sit at `top: TitleBar.height` with the bar above them, and both scroll their
  own body (this window is 480px tall and resizable; a `Column` that merely
  overflows becomes an unusable smear). Transient prompts — confirmations, the
  one-time token display — stay dialogs on purpose: they are modal by nature and
  gone in seconds. A new sheet must be added to `_clearOverlays`, to the Esc
  ladder, and to the paths that clear the content area (`_toggleCalendar`,
  `_surfaceForCapture`, the close guard, `_openAttachments`).
- `setPreventClose(true)` routes every close path (our ✕, Alt+F4, the tray's
  Quit) through `onWindowClose` — the single close guard. Once the guard lets a
  close through it goes via `_closeNow`, which paints the `_closing` overlay,
  waits for that frame to land and *then* calls `destroy()`. The teardown is
  slow (engine + acrylic + mpv) and nothing here can make it quick; the overlay
  is what stops the wait reading as a hang, and `_closing` is what stops a
  second click starting a second teardown. The player stop in there is bounded
  by a timeout on purpose — a hung stop must not be why the app cannot quit.
- Design tokens live in `theme.dart` (`T.*`), ported from the old CSS. Durations
  that used to be duplicated between CSS and JS now have exactly one copy each.
- `UiScale` draws the whole widget larger on phones rather than forking every
  padding per platform. Keep it that way — a second set of mobile sizes would
  drift from the desktop one literal at a time. Two things about it are
  load-bearing and both were once wrong:
  - It must use **`OverflowBox`, not `SizedBox`**. The constraints coming down
    from `MaterialApp` are *tight*, and a `SizedBox` cannot defy a tight
    constraint — it was silently ignored, the subtree laid out at full screen
    width, and the transform then magnified that off the edge of the screen.
    Nothing catches this: a `Transform` does not report overflow, and because
    the `MediaQuery` *was* being shrunk, anything measuring itself from
    MediaQuery disagreed with its own box.
  - `T.mobileScale` is a **maximum, not a factor**. The zoom applied is
    `clamp(width / T.designWidth, 1.0, mobileScale)`, so the layout always gets
    at least the 340px it was designed against. A flat 1.28 left a 375pt phone
    293 points and squeezed the controls at the ends of the bars.

  `test/ui_scale_test.dart` pins both: the subtree fills the screen exactly, and
  never lays out below the design width.

### Adapting to the size (`app/lib/layout.dart`)

`Layout` is the **single place** any size-dependent decision is made. Every
threshold is a named getter on it; `WidgetShell` measures its own box in one
`LayoutBuilder` and publishes it as `LayoutScope`, so a descendant asks
`Layout.of(context)` rather than adding a `LayoutBuilder` and a number of its
own. Two rules hold everything together and both are load-bearing:

- **No size takes a feature away.** A view may change shape when it does not fit
  — the week grid becomes an agenda, the year stacks into one column, the
  workspace bar unrolls into `WorkspaceRail` — but nothing becomes unreachable.
  That is what separates this from a mobile/desktop fork, and it is why the fix
  for a cramped view is a fallback here, *not* a call to `windowManager.setSize`.
- **The design width is the floor, not the target.** Extra room buys more at
  once (a rail, a second pane), never a stretched copy of the same thing — hence
  `taskColumnMax` and `focusTileMax`.

Notes for changing it:

- The thresholds are worked backwards from **contents**, and the tests assert
  them that way: `weekGridFits` is "seven columns of at least `minDayColumn`",
  not a round number. Keep new ones in the same shape or `test/layout_test.dart`
  has nothing to check them against.
- Where a view has a compact shape, the threshold is measured against **that**
  shape. `minDayColumn` is 40 rather than 62 because the narrow week is drawn
  with the compact grid geometry; measuring the compact case against the roomy
  numbers is what had a 340px phone falling back to a list.
- `_layout` on the shell is assigned *during build* and read by the focus
  flight, which runs from a callback and has no builder context. It is a record
  of what layout just decided, so nothing notifies off it.
- The rail and the split pane are gated on **height** as well as width. A wide,
  short window (phone landscape, a widget squashed against the taskbar) keeps
  the bar — a rail whose own list has to scroll is worse than the menu it
  replaced.
- `WorkspaceRail` deliberately takes the same callbacks as `WorkspaceBar` and
  adds only `onShowTasks`: a list needs Tasks as a destination, where the ▾ menu
  closes a view by re-picking it. It is the same navigation with the popups
  taken off, not a second model — if the two ever disagree about what a click
  means, that is a bug.

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
