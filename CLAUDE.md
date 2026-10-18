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
| `package.json` | The server's dependencies and scripts, nothing else. |

The original Tauri v2 + TypeScript build (`src/`, `src-tauri/`, `index.html`,
`vite.config.ts`, `tsconfig.json`) was replaced by `app/` in 0.7.0 and was
**deleted** in 0.24.0, after seventeen releases as a reference nobody read. It
is still in the history, tagged **`legacy-tauri`** - `git show
legacy-tauri:src/main.ts`, or `git checkout legacy-tauri` - which is where to
look if the legacy importer ever has to be checked against the schema it reads.
The importer itself lives on in `app/lib/sync/legacy_import.dart` and reads the
old *database file* at its install path, not this source tree, so nothing about
the deletion touches it.

`FEATURES.md` is the running description of everything the app does, with a
changelog at the bottom. **Keep it updated whenever behaviour changes** — it is
the closest thing to a spec.

Three files hold the plan, and they are not interchangeable:

| File | Holds |
| --- | --- |
| `TODO.md` | **The work order.** What is being worked on now and what is next, in order, with enough detail per step to start it cold. |
| `ROADMAP.md` | The *design* behind work that is agreed but not built, and a one-line record of each item once it ships. |
| `FEATURES.md` | What the app does today, plus the *Ideas / backlog* list for wishes with no design behind them yet. |

**`TODO.md` must be kept current as work proceeds** — tick a step when it is
committed, and move a finished block to its *Done* section. It exists so a
session that ends mid-list can be resumed from that file alone, which only works
if it says what is actually true. New work agreed in conversation goes in there
in the order agreed; the reasoning for it goes in `ROADMAP.md`, not in `TODO.md`.

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
| Add a user / token to the server | `npm run token -- add "<name>"` (also `list`, `revoke <id>`, `notify <user-id>`) |
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
the calendar, notification scheduling, the tray, the Markdown dialect, the
journal pane's states and shortcuts, the parked panel's drag, activate, add and
review funnel, the content area's identity across the chrome moving, the
recurrence rules, template variables and the occurrence sweep, the ambience
cache's byte maths and eviction, and the noise synthesis. Run it.

`test/noise_test.dart` **pins the RNG seed** (`NoiseSynth.rng`), and that is
what makes it reproducible. Unseeded it failed about a third of runs: at the
documented ~0.19 RMS a peak of 1.0 is 5.26σ, so across the 2.6M samples in a
buffer you expect ~0.37 exceedances, and the encoder clamps them. A single
clamped sample in 2.6M is inaudible, so this was the test re-rolling dice
rather than a defect — but the fix is the seed, **not** a looser assertion, and
not a lower level trim either (at 0.17 RMS it still clips one run in a
hundred). The server has its own tests: `node --test server/`, and a schema
change on either side needs both.

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

`LocalStore` (`app/lib/sync/local_store.dart`) owns fourteen synced tables:
`workspaces`, `parked_groups`, `tasks`, `attachments`, `side_thoughts`,
`journal_entries`, `calendars`, `calendar_events`, `calendar_feeds` (v16),
`lists` and `list_items` (v17), `collections`, `collection_fields` and
`collection_entries` (v18), plus a key/value `settings` table used for UI
prefs (last workspace, nudge, sound volume, calendar mode/scope/hidden/block
target), and a device-local `blobs` table for voice notes' bytes (v20, see
*Voice notes*).

Rows are keyed by **UUID**, not autoincrement — two devices offline at once used
to collide. Every row carries `updated_at` and `deleted_at`; deletes are
**tombstones**, so a removal actually propagates instead of looking like a row
the peer never saw.

**`updated_at` is RFC 3339 *with an offset*, and the offset is the whole point.**
`nowStamp` builds it by hand (`stampOf`) because Dart will not:
`DateTime.now().toIso8601String()` appends `Z` for a UTC value and *nothing* for
a local one, so every stamp used to be a naive wall-clock reading that said
nothing about which clock read it. Last-write-wins then compared clock faces, and
a phone in New York editing at 09:30 (13:30 UTC) lost to a desktop in Madrid that
had edited half an hour *earlier* at 15:00 (13:00 UTC) — a silently dropped edit,
and exactly what `compareStamps` had been written to prevent; it just had no
offset to read. Two things follow:

- **The wall-clock part is unchanged**, which is what made this safe to start
  doing to a database full of the old naive stamps: text ordering of a new stamp
  against an old one is what it always was.
- **The server's merge parses instants only when *both* stamps carry a zone**
  (`compareStamps` in `db.js`), and falls back to text otherwise. It must: an
  offsetless stamp is resolved by `Date.parse` in the *server's* timezone, so on
  a UTC server an old `T15:00` row reads as 15:00Z and the same client's next
  edit at `T15:05+02:00` (13:05Z) looks two hours older and gets rejected — and
  the client clears `dirty` on push whatever the merge decided, so it would never
  be retried. Rows heal as they are rewritten.

State flags rather than separate tables:

- `completed_at IS NULL` → active task; non-null → done (shown in History).
- `in_progress` is the focus flag, and it is **exclusive and global**: setting it
  clears every other row, so at most one task is ever flagged.
- `resolved_at` on a side thought. Thoughts are *never* hard-deleted.
- `group_uuid` on a task is the parked flag: non-null means shelved in a
  `parked_groups` row, and shelved rows are excluded from `activeTasks`,
  `inProgressTask` and the reminder sweep. One nullable column rather than a
  second table, so parking keeps the row's uuid, history and reminder.
- `notes` and `priority` on a task are the two columns v11 added. Both are NOT
  NULL with a default that *is* what every older row means (`''` and `0`), so
  there is no third "unset" state to reason about and `copyWith` needs no
  `clear` flag for either. `priority` is an integer rather than a boolean
  because a second level is the obvious next request and a second column could
  disagree with the first after a merge.
- `recur` on a task is the repeat rule (v12), null for a one-off, and it carries
  the **period only** — the time of day is `remind_at`'s, which keeps its exact
  meaning of "the next time this nags". That is what kept the change small:
  `ReminderService`, `describeReminder`, the overdue styling and
  `NotificationService` all still read one instant and needed no changes.
  Completing a recurring task **spawns the next occurrence as a new row**
  (`Task.nextOccurrence`, called from `AppState.completeTask`) rather than
  re-arming this one, so History needed no changes either — the finished row
  lands there by having a `completed_at` like any other. Two things about it are
  load-bearing:
  - **The successor's uuid is derived** (uuid v5 over the parent's id and the
    occurrence instant), not generated. Spawning happens on a write, writes
    sync, so two devices that both see a completion both spawn; generated ids
    would make those siblings. Third instance of the rule, after
    `_foldSeededDefaults` and `Calendar.forWorkspace`.
  - **`Recur.next` is calendar arithmetic in local time**, not `Duration`
    addition. Adding 24 hours to an instant moves a 09:00 alarm to 08:00 across
    a DST boundary; building the next `DateTime` from its parts keeps the
    reading. Month-length overflow clamps rather than normalising, or a monthly
    task on the 31st would quietly move to the 1st.
- **`recur_from`, `recur_lead`, `recur_text` and `recur_notes` (v15) are the
  rest of a repeat**, and every default is what a pre-v15 row already meant, so
  the migration backfills nothing and a task that has always repeated goes on
  repeating in exactly the way it did.
  - **`recur_from`** is `RecurFrom.schedule` or `RecurFrom.completion`, and it
    is the whole of the second kind of repeat: an interval counted from when
    the task was *ticked* rather than from what it was due. Being late then
    moves the series instead of leaving you behind it, and such a task needs no
    reminder at all — `nextDueAt` measures from `completed_at`, at the
    reminder's time of day when there is one.
  - **`recur_lead`** is the three-state column, in the shape
    `CalendarEvent.notifyMinutes` uses and for the same reason (two columns can
    disagree after a merge): **null** writes the successor when this one is
    ticked — today's behaviour, and incapable of piling up because making the
    next needs finishing this one; **0** writes it when it falls due, ticked or
    not, which is the rule-based half of the feature; **n** writes it n minutes
    early with the due date still the rule's.
  - **`recur_text` / `recur_notes`** carry the unexpanded template. Expansion
    (`task_variables.dart`) happens **once, when the row is written**, against
    that occurrence's own due date — so the September row goes on saying
    September after October's exists, which is what makes History a record
    rather than a template that re-renders. Stored only when the text actually
    has a `$(...)` in it: null already means "the text is its own template".
  - **`recur_from` is nullable in both databases and non-null in the model.**
    The server's merge writes `row[field] ?? null` for every column in `TABLES`,
    and `applyRemote` inserts a server row verbatim, so a peer on an older build
    pushes a task with no `recur_from` — a NOT NULL would turn that into a
    constraint failure that rejects the *whole* push and aborts the *whole*
    merge, so one old device would stop every row moving. `Task.fromMap` reads
    null as `schedule`, which is what such a row means, so there is still no
    third state to reason about. Same rule `review_every_days` follows.
  - **One spawner, two callers, idempotent through the derived uuid.**
    `AppState._spawnOccurrences` runs from `completeTask` with the row that just
    changed and from the reminder poll with `LocalStore.recurringSeeds`
    (`sweepRecurrences`), because a rule-based repeat comes true *because time
    passed* and nothing is written when it does. `Task.dueOccurrences` walks the
    chain **in memory** and the caller then asks **one** batched question
    (`existingTaskUuids`, tombstones included) about which of them already
    exist — a lookup per candidate would be a query per series per 20-second
    tick for an answer that is almost always "nothing to do".
  - **Catch-up is capped at `Task.maxCatchUp`,** most-recent-first. A year off
    with a daily rule owes 365 occurrences nobody was going to do, and a list of
    365 of them is not a catch-up.
  - **New rule forms are for tasks only.** `Recur.monthLast`,
    `month-<ord>-<wd>` and `every-<n>-<unit>` are parsed rather than listed in
    `Recur.rules`, and `Recur.nth` does not expand them — a calendar block's
    occurrences come from `nth`, and nothing can give a block one of these. The
    first two exist because a due date cannot stand for them: `monthly` from the
    31st clamps to 28 February and then walks on from *there*, so one short
    month rewrites the rule for ever.
  - **History is the way out of a series with no open occurrence.** A
    completion-anchored task is invisible between being ticked and coming back;
    the ↻ on its History row names the rule and offers `stopRepeating`, which
    clears `recur` and leaves the completed row exactly as it is.
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

**`selectWorkspace` closes every view, thoughts included** (`_closeOtherViews()`
with no arguments). The per-workspace views could never have survived the
switch; the thought pile used to, on the grounds that it is global and so not a
fact about the workspace. That was the wrong question — picking a workspace is
asking *what is on this list*, and answering it with whatever panel happened to
be open answers a different one. Nothing is lost, because the footer's count and
the view bar both still say how many thoughts are waiting.

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
list/**reader**/editor states and intercepts Esc to walk back down that ladder
before the shell closes the pane. Two things there are load-bearing:

- **The reader renders from the editor's controllers**, not from `_editing`. What
  is on screen after a save is then exactly what was saved, with no second
  lookup that could disagree and nothing to re-resolve when `items` is rebuilt
  underneath.
- **`onSave` hands the saved item back**, which is why `AppState.addJournalEntry`
  and `editJournalEntry` return a `JournalItem?` rather than void. The panel
  adopts it as `_editing`, so a second Ctrl+S in one sitting rewrites the row the
  first one minted instead of writing a sibling. Null means nothing was saved
  (an entry cleared to nothing deletes), and the list is then the only honest
  place to land.
- The pane owns a `FocusNode` of its own. The editor never needed one — a text
  field inside it takes primary focus and key events bubble up through the
  `Focus` on their way out — but the reader has no field, so without it the pane
  is not on the focus path and Esc falls straight through to the shell, skipping
  the list rung. `test/journal_panel_test.dart` pins that rung.

**The workspace bar, the rail and the view bar are gone** - the dock (below)
replaced all three at every size, and the files were deleted once the wide
placement was settled as "keep the setting". What outlived them lives in
`ui/workspace_view.dart` (`WorkspaceView`, and `kViewOrder`, the order the
dock's second segment lists and **`_swipeView` in `main.dart`** walks - one
list, so the two cannot disagree) and `ui/workspace_form.dart` (the
create/edit form). The swipe is still safe to claim because the only other
horizontal gesture in the list is the task `Draggable`, which exists only when
there is something beside the list to drop onto - a window far wider than any
phone. `_selectView` is a *destination*, never a toggle: tapping Notes must
land on Notes whatever was showing.

Two things take the whole screen on touch and both are about what is
*incidentally* on display: `ThoughtSheet` (`ui/thought_sheet.dart`), because a
phone is held in front of people and the inline capture field left every task in
the workspace visible behind the keyboard; and an open journal entry, via
`_noteTakesScreen`, which hides the dock and the footer.
`JournalView` reports that through `onEntryOpen` rather than the shell inferring
it — `showJournal` says the pane is open, not which rung of its ladder you are
on. That callback is deferred to after the frame, because the shell reacts with
`setState` and doing that from inside another widget's build is a crash.

`ThoughtSheet` still stops at `TitleBar.height` like every other sheet, and the
"whole screen" is everything below the bar. It used to start at 0 and be drawn
*under* the title bar — which is last in the shell's `Stack` so the window stays
draggable — and the collision was exact: the pane's ✕ sat on the
concentration-sound button. Nothing is lost by stopping, because what it hides
is the workspace name and the tasks and both are below the bar.

**The dock is the whole side-thought control, and the footer draws nothing.**
Thoughts is a row of the dock's More, which carries the pile's count and its
escalation (`ThoughtPulse` in `ui/thought_pressure.dart`, one signal drawn
wherever the control is), and Add a thought is on its ＋. `ThoughtFooter` has
two flags, `showCaptureButton` and `showPressure`, both false wherever the dock
shows, so the bar takes no height at any pile size. It stays in the tree for
the close guard's refusal. **Every capture path opens `ThoughtSheet`**, on a
desktop too (`_jumpToAddThought`; focus mode keeps its own field): the hotkey
used to expand the footer's field in place, except on the full-window
calendar and the list, which have no footer, so one shortcut opened two
different things depending on the view. On a keyboard (`enterSaves`, passed
`!_layout.touch`) Enter saves and closes, Ctrl+Enter saves and stays, and
Shift+Enter is the newline; the pane's `FocusNode.onKeyEvent` takes Enter
before the field does, which is what keeps it from also inserting a line.
Esc closes it unsaved (the shell's Esc ladder, right after the update sheet).

**The dock is the navigation at every size** (`ui/dock.dart`): the workspace
bar, the rail, the view bar and the title bar's calendar / list / settings
buttons are not drawn anywhere. It runs along the bottom while the window is
narrow and, past `Layout.isWide`, along the edge `AppState.wideDock` names
(`DockEdge.top`, `left` or `bottom`, chosen in Settings, device-local) -
`_dockEdge` decides it. A top bar lists each menu the other way up (`_drawn`),
so the row nearest the bar is the same one a bottom bar puts nearest; a side
bar stands its labels up and places its menus with `_SideMenuLayout`, level
with the segment and pushed up to stay on screen. A top dock is not in `_body`
at all: it is `TitleBar.dock`, beside the name, at the title bar's height. With
a mouse a segment opens its menu on hover (`_enterSegment` after
`_hoverOpenDelay`, so crossing the bar opens nothing; `_viaHover`, no scrim)
and closes when the mouse has left both segment and menu; the timer re-reads
`_overSegment` / `_overMenu` rather than trusting enter/exit order. The things
about it that are load-bearing:

- **One pointer, one `Listener` per segment, no recognisers.** Pointer events
  go to whatever was hit at the press for the pointer's whole life, so the
  segment sees every move and asks the menu's `RenderBox` (`globalToLocal`)
  which row the finger is on. A `GestureDetector` would have to win an arena
  against nothing, and would lose the finger the moment it left the segment.
- **Geometry through `RenderBox` transforms only.** The menu is an
  `OverlayPortal` placed with `localToGlobal(ancestor: overlay)`; pointer
  positions are screen pixels and the overlay is in layout units, with
  `UiScale` between them.
- **The dock paints below its own box** (`Dock.underhang`, the bottom
  inset recorded in `build` before the SafeArea eats it), so its colours run
  under the home indicator. That only shows because `_shell`'s Stack is
  `Clip.none`; clip it again and the strip goes back to bare window.
- **`_body` is always a `Column` holding a `Row`, and the body is keyed in
  both** (`'body'`, `'content'`), so the dock appearing, disappearing
  (`_takesScreen`) or changing edge never reparents the body - the
  content_slot lesson again. The title bar's spacer lives there too, once,
  rather than at the top of each branch of `_bodyAbove`.
  Its rows are destinations (`_dockClear` then go), never toggles, and leaving
  the calendar goes through `_toggleCalendar` so pending blocks commit.

**A short tap or click is the segment's `onClick`**: the workspace goes to
its task list, the view to its top (`_dockToViewRoot`, which gives the
secondary view a fresh `GlobalKey` - a fresh State is each view's top rung,
and the journal saves an open draft in `dispose`), ＋ to the add card. More
has none, and a segment with none opens its menu on a tap and closes it on
the next (Marco, 2026-10-18). **A press opens nothing** until it has moved
past `kTouchSlop` or been held for `kLongPressTimeout` (a timer, `_held` -
test pointer events carry no time stamps); a held press let go still leaves
the menu up for a tap. The menu opened by a slide is not laid out yet, so
`_move` asks `_track` again after the frame or a fast finger lights no row.

**A row can carry a submenu** (`DockItem.children`): the workspace rows carry
their views. It is drawn in the same overlay Stack as the menu, beside it
(`_submenu`), and has to be in **both** of the dock's input paths - the
press-and-slide asks `_subRowAt` before `_rowAt` because the submenu is drawn
on top, and opens after `_holdForSub` on one row; the mouse opens it after
`_subDelay` from the row's hover and keeps it while `_overSub`, which
`_closeAfterHover` also has to respect or the menu closes under a pointer that
is in its submenu. A held-open menu has no hover, so there it is a long press.

**Quick actions wait for the first layout** (`_afterLayout` in `main.dart`).
iOS delivers the shortcut that launched the app as soon as the handler is
installed, which is in `initState`; until the first build `_layout` is the
desktop default, and "Park a thought" went looking for a footer field a phone
does not draw. And `_jumpToAddTask` clears everything that can stand where the
add field is drawn - the full-window calendar, a task that took the screen, a
selection, an open capture pane - or the field opens out of sight.

**Per-workspace views live on the dock's second segment, not the title
bar.** Notes, Parked, Collections and History are its rows (they are about the
current workspace); the title bar (`ui/title_bar.dart`) is only window/global
controls (sync, sound, pin, minimize, close). They are still mutually-exclusive
content views alongside thoughts, driven by `showHistory` / `showParked` /
`showJournal` / `showCollections` on `AppState`. The dock is part of the body,
which focus mode fades out, so none of this is reachable while focused - that
is fine, they are not things you reach for mid-focus.

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
and v11 `notes` / `priority` lines in `attachments_test`, `calendar_test` and
`default_workspace_test`; the v13 `recur` on `calendar_events` is the first
such column on a table other than `tasks`, so `recurrence_test` and
`default_workspace_test` roll that one back too), and a hand-built one has to
contain every table a later step touches, which is why `journal_test` carries
`_v9Tasks` and `_v4Attachments` as scaffolding.

### The shell's panes, and what survives them moving

- **The secondary view carries a `GlobalKey`** (`_secondaryKey` in
  `main.dart`). The same view is a child of the stacked column, the split row,
  or another row depending on the window size, and an unkeyed widget that
  changes *parent* is rebuilt from scratch - resizing across a breakpoint used
  to reset `JournalView` and throw away a note being written. `contentSlot`
  solves the sibling half of this; the GlobalKey is the parent half.
- **`JournalView` saves an open, changed draft in `dispose`**, because the
  workspace switch and the calendar both close every view. `onSave` is bound in
  the shell to the workspace the note was opened in (`journalWorkspace`), since
  by the time dispose runs `currentWorkspaceUuid` has already moved. A draft
  cleared to nothing is *not* saved: saving empty fields deletes.
- **`SplitPane` (`ui/split_pane.dart`) is every list-beside-something split** -
  the views past `splitMinWidth` and the calendar past
  `calendarSplitMinWidth`. The boundary is stored as a fraction per split
  (`AppState.splitFraction` / `calendarSplitFraction`) and the fold is one
  shared preference (`tasksPaneCollapsed`); all device-local `settings`. The
  row keeps three keyed slots whether folded or not, so folding never rebuilds
  the right pane.
- **The window drops the workspace tint while thoughts are open**
  (`_neutralChrome`), and every thought surface uses `T.thoughts`: the pile is
  global, and drawing it in one workspace's colour claimed otherwise.

### The add field is a card (`app/lib/ui/task_capture.dart`)

`_adding` on the shell, set by the dock's ＋ (*Add a task*), `N` on desktop, the
folded "Add a task" line at the head of the list (`_addPrompt`), and every
capture path (`_jumpToAddTask` calls `_openAdd`). Open, `TaskCapture` flies
from that line's rect (`_addPromptRect`, in the shell Stack's space) to a
centred column over a scrim, growing as it goes; closed, it flies back and
`onClosed` lets the line draw again (`_addCardShown`). The `N` handler checks
the focused node's ancestry for an `EditableTextState`, because a text field's
key events bubble through the shell's `Focus` too and an "n" typed into a note
must stay an "n". The things that are load-bearing:

- **The card is always in the shell's Stack** and draws nothing while closed:
  its State holds the draft's priority / reminder / workspace between
  openings, and an exit animation needs a widget still in the tree.
- **The flight is laid out, not scaled** (`_FlightLayout`, a
  `SingleChildLayoutDelegate` lerping from the line's box to the centred one),
  for focus mode's reason: a scale would stretch the text. The origin is read
  at the start of *each* flight, since the list can move in between.
- **The shell owns the controller (`KeywordController`), so closing keeps the
  draft** and the folded line shows it. Esc, the scrim and Enter on nothing
  all close; none of them throw away text.
- **Keywords are parsed, not consumed, while typing.** `parseTaskKeywords`
  (`task_keywords.dart`, pure, `now` injected, `test/task_keywords_test.dart`)
  runs per keystroke; the controller highlights its spans, the bar shows the
  values, and the stripped title is only produced on submit. A hand-picked
  setting switches its kind of keyword off, and the bar's × does the same for
  a recognised word, so there is always a way to keep a word in a title. The
  parser's guesses are tuned to *not* fire: a bare number is never a time,
  weekdays are full names, `1/2` is a fraction, and a title that would be left
  empty keeps its words.
- **A workspace keyword needs its `#`.** Bare names used to be read, and a
  workspace called Work ate the first word of "Work on the report". The `#`
  is also what makes **shortcuts** possible: `workspaces.shortcuts` (client
  v19, protocol 5, `COLUMN_SINCE` on the server) is a JSON array of other
  names, stored without the `#`, matched exactly like the name.
  `shortcutProblem` is the one check (one word, not another workspace's name
  or shortcut) and the card's `_ShortcutSheet` is the only way to add one;
  the workspace form only removes. v19 resets the sync cursor for v16's
  reason.
- **The shortcut pill is placed from the last layout.** `_placePill` runs
  after the frame, finds the `RenderEditable` under `_fieldKey` and asks
  `getBoxesForSelection` where the word is; hover reads the same boxes. It
  shows for the hovered word or the one the caret is in (touch has no
  hover), and it is a `TextFieldTapRegion` - without that, the press
  unfocuses the field, the caret span goes, and the pill disappears from
  under the finger before the tap lands.
- **Enter adds and closes, Ctrl+Enter adds and stays, Shift+Enter is a
  line** - ThoughtSheet's keys, taken by a `Focus` around the field
  (`_onKey`) so a handled Enter never reaches the text input. The field is
  multiline on a keyboard; on touch it is `TextInputType.text` with Done,
  which submits through `onSubmitted`. Closing after an add also forgets a
  hand-picked workspace; staying keeps it.
- `KeywordController.invalidate` does **not** notify: the card calls it from
  `didUpdateWidget` (workspaces changed), and notifying there is a setState
  during build.
- The tests send real key events (`sendKeyEvent`, with Ctrl/Shift held by
  `sendKeyDownEvent`), because the three Enters differ only in modifiers.

### Selecting several tasks

The selection is shell state (`_selected`, uuids, plus `_selectedIn`, the
workspace it was made in) and is pruned by reading it through `s.tasks`, so a
row that left the list drops out rather than being acted on. `TaskRow` takes
`selected` / `selecting` / `onToggleSelect`: Ctrl+click toggles, and once
anything is selected a plain click does too. `SelectionBar` takes the add
field's slot. `ui/move_picker.dart` answers "where does this go" for one task
or many - this workspace's shelves, then every other workspace's list and
shelves - and replaced the single-workspace park picker. The writes are
`AppState.moveTasks` / `finishTasks`: one pass, one refresh.


**Side thoughts have a selection of their own**, in `ThoughtsPanel`'s State
rather than the shell's: the pile is one global list, so there is no
workspace for the selection to belong to and nothing outside the panel acts on
it. Ctrl+click or a long press starts it; the header becomes its bar. Moving
goes through the same `move_picker.dart` with `includeHereList` (a thought is
on no list yet, so "This list" is its commonest destination), and
`AppState.moveThoughts` writes each as a task and resolves the thought.
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
- **A repeating event is one row, expanded on the way out.** `recur` on
  `calendar_events` (v13) is the same closed vocabulary tasks use, and the
  stored `start_at`/`end_at` are the *first* occurrence. `occurrencesBetween`
  produces the rest for whatever window is being drawn, and they are **never**
  written. This is the opposite of `Task.recur`, deliberately: a task
  occurrence gets completed, so it has to be a row and History is made of
  those; a block has no state of its own, and writing a year of them would be
  a year of rows to rewrite the day the title changes.
  - An occurrence **keeps the series' uuid** and carries the stored row in
    `series`. That is what makes everything keyed on uuid - its attachments,
    the todos planned into it, `eventTaskCounts` - work with no special case
    at all. `instanceKey` is what tells two occurrences apart. Occurrence ids
    are pointedly *not* derived the way `Task.nextOccurrence`'s are: deriving
    exists so two devices agree on a row they both **write**, and nothing here
    is ever written.
  - `copyWith` and `toMap` always build from `stored`, so a write reached
    through an occurrence cannot move the series onto whichever Tuesday was on
    screen. `_editEvent` opens `event.stored` for the same reason, and the
    form says the change applies to the series.
  - **The window query cannot filter a series on `end_at`.** A series has no
    end; the stored end only says how long one occurrence lasts. `eventsBetween`
    and `liveEvents` therefore have two predicates, and `upcomingEvents`
    contributes exactly one instant per series - the schedule is rewritten
    wholesale, so a year of a daily block would be a year of alarms to cancel
    on every edit.
  - **Occurrences are counted from the anchor** (`Recur.nth`), not walked one
    from the last (`Recur.next`). Walking clamps per step, so a monthly block
    on the 31st meets February and becomes the 28th *for ever*. Tasks keep
    using `next` because a completed task has no anchor left - the row in
    front of you is the series.
- **`all_day` (v14) says how to draw an event, not when it is.** The instants
  still carry the whole answer: midnight on the first day to midnight on the
  day *after* the last, which is .ics's exclusive end and is what lets
  `eventsBetween`, the spanning band and the session go on working without
  knowing the flag exists. Three things follow:
  - **The end is exclusive everywhere below the form.** `saveEvent` normalises
    to it, `parseIcs` already produces it, and the *editor* is the single place
    that converts - a person picking "ends 20 Aug" means the 20th included.
    Print the stored end anywhere user-facing and every all-day event gains a
    day.
  - **One whole day already satisfies `spansWholeDay`** (midnight to the next
    midnight is exactly one whole day), so it lands in the band with no
    separate rule. The grid still tests `allDay || spansWholeDay`, because that
    is the question being asked and relying on the coincidence would be a trap
    for whoever changes `spansWholeDay`.
  - **An all-day event does not inherit its calendar's lead time**
    (`notifyLead`). That rule is minutes before a start and an all-day start is
    midnight, so inheriting "an hour before" fires at 23:00 the night before
    for every birthday. A lead set on the event itself is still honoured -
    that is the only place someone can have meant it.
- **The band is for a whole day *inside* the event, not for two dates.**
  `spansWholeDay` asks whether a midnight-to-midnight day fits between the
  instants; it was `spansDays`, which asked whether the two ends fell on
  different dates, and so promoted every night shift and everything ending at
  00:00 into a band that then printed neither the hour it started nor the hour
  it ended. An overnight block is drawn in the grid, in **every column it
  overlaps** (`_timedByDay` adds it to each rather than breaking at the first),
  clipped into each by the clamp that `_positionedEvents` was already doing;
  `EventBlock.continuesBefore` / `continuesAfter` square off the cut end so the
  halves read as one thing. What genuinely cannot be drawn in a column is a
  block with a day entirely inside it - that one is 24 hours of scrolling past
  the same block. The agenda has always used this same overlap test, and
  `AgendaView._on` is where the shape came from.
- **The editor rolls an end time back over midnight.** Picking an end that is
  not after the start moves it to the next day rather than warning, because
  22:00-04:00 is the commonest overnight block there is and making somebody
  move the end *date* to say so is the long way round. Calendar arithmetic, not
  `Duration(days: 1)`.
- `notify_minutes` on an event is a **three-state column**: null inherits the
  calendar's rule, `CalendarEvent.notifySilent` (-1) overrides it to quiet, any
  other value is a lead time. One column rather than a flag plus a value,
  because two columns can disagree after a merge. Note `copyWith` cannot tell
  "leave alone" from "set back to inherit" — that is what `clearNotify` is for.
- Notifications for tasks and events are rewritten in **one** call
  (`NotificationService.reschedule`), because the cancel is global; two calls
  would each wipe the other's work.
- **It drops the workspace tint while it owns the window.** The window's
  background is `T.tintedBackground(ws)` everywhere else, which is how it says
  which workspace you are in; the calendar is not in one, and a window mixed 16%
  into one workspace's colour competes with the per-calendar colours the week
  view exists to distinguish. `_calendarChrome` on the shell decides it, and it
  is simply `showCalendar` — **including in the split**. It was
  `&& !splitsCalendar` for one commit, on the theory that half a split window
  really is that workspace's list; what that bought was a change nobody could
  see, since the widget is run at about 1140×670 and the split starts at
  813×400, so the exception was the only case that ever ran. Nothing is lost:
  which workspace you are in is on the bar's coloured pill, inches from the
  tint that was repeating it. The
  title bar's `accent` follows it to `T.accent`: the neutral itself is within a
  few points of `T.muted`, so tinting a lit control with it would stop it
  reading as lit. `T.calendarInk` has a light twin (`calendarInkLight`) that
  nothing reads yet — the light theme is still in the backlog, and deciding the
  pair together is the point, since "neutral" means something different against
  a pale window.
- The calendar is the one view that replaces the **whole window** rather than
  the content area. It lives on the dock's More, not beside the workspace's
  views, because it can show every workspace at once - and it still replaces
  only the body: the dock stays, so leaving it is picking where to go. `_toggleCalendar` used to
  resize the window to 920×640 and centre it on the way in; it does **not** any
  more — see `layout.dart` below, and don't put it back.
- Past `Layout.splitsCalendar` it replaces nothing: `_splitCalendar` puts the
  task pane (banner, the list under its workspace's name, add field) beside it. Both halves get
  their **own `LayoutScope`**, measured by a `LayoutBuilder` — the week's
  fallback and the year's column count must answer for the box the calendar
  actually got, not for the window. That split is also the only place
  `onPlanTask` is non-null, so the drop targets simply do not exist anywhere a
  task cannot be dragged from.
- **A double click edits** without delaying the single one: the details card
  opens on the first click, ignores the pointer for `kDoubleTapTimeout`, and
  `_SecondClick` (a global pointer route) turns a press in that window - which
  falls through to the barrier and closes the card - into `EventAction.edit`.
  The ignoring is what keeps the second click off the card's Delete.
- **A click on a block reads it** (`showEventDetails`), and right-click /
  long-press is the actions menu (`_eventMenu`); `_editEvent` is the form that
  used to be what a click did. The long press is safe to take *because* the
  create-drag listener sits below the blocks in the grid's `Stack` — the same
  arrangement documented above is what makes both gestures possible on one
  widget. On a **movable** block the long press lifts it instead (next
  bullet), and the menu is what letting go without moving opens.
- **A block is carried, not nudged** (`EventBlock.movable`, `_MovableBlock`).
  Which gesture lifts it is decided by the **pointer**, not by `Layout.touch`
  - a browser on a desktop lays out as touch and still has a mouse - so it is
  two nested `Draggable`s that each answer to one kind of pointer
  (`_DeviceDraggable`): an immediate drag for a mouse, which means nothing else
  over a block, and a long press for everything else, because a finger's drag
  over a block is how the day scrolls. Things that are load-bearing:
  - **The payload is mutable and owned by the block's State** (`EventDrag`).
    `Draggable` reads `data` when the drag *starts*, from the last build;
    where the press landed and whether the pointer has travelled are only
    known after, and a payload rebuilt per build would be a different object
    from the one the avatar carries.
  - **Event blocks in the grid's `Stack` are keyed** on instance and day. The
    edge zones step the week under a carried block, and an unkeyed block's
    State - and so its payload - would be handed to whichever event now sits
    at that index.
  - **The landing is read from the ghost**: its top edge rounded to a quarter
    (it is a line, like a dropped pending block), its day under its middle
    rather than its corner. The move is the wall-clock distance from the piece
    picked up (`pieceStart` - midnight cuts an overnight block into pieces) to
    there, applied by `CalendarEvent.shiftedBy` to `stored`, so an occurrence
    moves its series and a move across a DST change keeps the clock reading.
  - A feed's event is never movable (`fromFeed`): the next refresh would put
    it back without a word.
- **An end is stretched by a grip that is the block's sibling** (`_ResizeGrip`,
  edit mode only, via `EventBlock.onResizeUpdate`). The grips sit *on top of*
  the block in a `Stack` rather than inside it, because the block's own
  `Draggable` would otherwise also get the press and carry the whole thing.
  A plain vertical drag, safe on touch for the pending grip's reason (the
  deepest recogniser wins the arena over the scroll view). The grid turns the
  pointer into a quarter hour against `_bodyKey` - its own box also holds the
  day headers - clamps it inside the piece's day and a quarter short of the
  other end, previews it with the move's outline, and writes through
  `AppState.resizeEvent` → `CalendarEvent.resizedBy`, which, like a move,
  applies the wall-clock distance to `stored`. A cut (overnight) end has no
  grip. **The now line is drawn above the blocks** and ignores the pointer;
  under them it was the one line you could not see on a busy afternoon.
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
  **Pressing picks a quarter, it does not round to a line**: `_pointToSlot(
  floor: true)` for the start and the tap-to-place, and the draft is the run of
  slots from the pressed one to the one under the finger with both included
  (`_anchorSlot`). Rounding started every block a quarter late for anyone who
  pressed a few minutes below the hour line. A dropped pending block still
  rounds: there the point is the ghost's top edge, which *is* a line.
- **An event is a `RaisedFace`**: one solid face in the calendar's colour on a
  `T.edgeOf` edge showing right and bottom, inside the block's own box so the
  grid maths never hears about it; text is `T.inkOn`. The grid, the all-day
  band and the agenda share it. `EventBlock` measures the title and **stands
  it up** (`RotatedBox`, reading downwards) when it does not fit across and
  the block is at least 1.5x as tall as it is wide.
- **Edit mode is one nullable uuid**, `AppState.timeBlockCalendarUuid` (the
  names are from when it was "time-block" or "quick add" mode, a ⚡; it is the
  ✎ now, and Ctrl+E in the shell's key handler, both through
  `AppState.toggleCalendarEditing`). **Moving and stretching blocks exist only
  while it is on**: `CalendarView` hands `onMoveEvent` / `onResizeEvent` to the
  grid only then, so outside it a stray drag cannot move a meeting. The uuid
  is the calendar new blocks go on,
  resolved through `visibleCalendars` rather than `calendars` — the
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
- **The toolbar is one row on touch, and not the desktop's row.** It was three
  (back/step/Today, the date on its own line, bolt/mode/filter) - 106 units of a
  phone above the weekday strip. Now it is `‹ date ›`, a `_ModeCycle` chip that
  steps D → W → Y, the ✎ for edit mode, and the `_FilterMenu` as ⋯, which on
  touch also carries Today (`onToday` non-null is what turns the filter into
  the ⋯). Tapping the date is
  Today. There is no back arrow: the title bar's calendar button closes it. The
  date **scales down** (`FittedBox`) rather than ellipsing, which is what went
  wrong the last time it shared a row with controls - "August 2026" showed as
  "Au…". Desktop keeps its single row with the three-way `_ModeSwitch`.
- **A horizontal swipe moves through time** — next/previous week in the week
  view, day in the day view, year in the year view (`state.stepCalendar`), and
  unclamped, because time has no ends. It used to switch D/W/Y, which was the
  wrong axis: the mode is set once and read off the toolbar, while "what about
  next week" is asked twenty times in a sitting and meant reaching for the ‹ ›
  at the top of the screen each time. Safe to claim because the grid's own
  gestures are a vertical scroll and a *long-press*-then-drag to create —
  creating is split by input device precisely so a one-finger drag can still
  scroll, which leaves a plain horizontal fling belonging to nobody.
  **The neighbours are drawn under the finger** (`TimeSwipe.builder(delta,
  scroll)`), which is why `refreshEvents` loads `calendarLoadRange` - one step
  either side of `calendarRange` - and why **`AppState.events` is not "what is
  on screen"**: every view filters to its own days (the band's `_spanning`
  had to learn to; it used to trust the list). The middle page stays one
  element across a turn, keyed and in a Stack whose shape never changes, so
  the grid keeps its scroll; the neighbours open at the same offset through a
  shared `ValueNotifier` (`TimeGridView.sharedScroll`), and `page` changing is
  what zeroes the slide in the frame the step lands - so the neighbour that
  slid in and the middle page that replaces it are pixel-identical.
- **Edit mode holds tapped blocks before writing them** (`AppState.pendingBlocks`).
  Tapping the grid in edit mode places an adjustable hour; nothing reaches
  the database until the mode ends. They are deliberately not stored and not
  synced — an unfinished thought about Tuesday is not something another device
  should receive — which also means they do not survive the app closing, the
  right trade for something whose whole life is one sitting. **There is one
  commit rule and it is structural**: `commitPendingBlocks()` runs from
  `_toggleCalendar`, and — this is the load-bearing part — from
  **`AppState.setCalendarMode`** and
  **`setTimeBlockCalendar`** themselves — the only ways the view and the
  target ever change. It used to be a convention each call site had to remember, and the
  block strip did not: its "Off" set the target directly, so the blocks outlived
  the mode with nothing to belong to and the calendar closing then discarded
  them, while its pick filed blocks laid out on one calendar under another's
  name; and the mode change was committed by the *swipe* handler in
  `calendar_view.dart` but not by a *tap* on the same D/W/Y control, a split
  that only closed when the swipe was repointed at time and the commit moved
  onto `setCalendarMode`. Some exits committing and others discarding is how
  a user loses an
  afternoon's planning, so the rule lives where it cannot be bypassed rather
  than where it has to be repeated. (Turning the mode *on* commits nothing —
  nothing can be pending with the mode off.) It clears the list *before*
  awaiting the writes, so a missing target drops them instead of retrying
  forever. Note that "the target went away underneath" — unticked, scope
  narrowed, workspace deleted — is a *different* state from the mode being
  turned off, and only the first one drops blocks; `test/quick_add_test.dart`
  pins both. On the block itself: tap removes (nothing is
  written yet, so a mis-tap costs one tap), long-press *lifts* it (see the
  bullet below; long press, because a plain drag would make the grid
  unscrollable wherever a block sat), and the bottom grip resizes on a plain
  vertical drag — safe without the long press because the deepest recogniser in
  the arena beats the scrollable above it.
- **A pending block is picked up, not pushed around.** Moving one is a
  `LongPressDraggable` whose ghost the grid takes as a drop (`_dropPending`),
  resolved from the **top-left of the ghost** so it lands where it is drawn.
  The old version fed the block vertical deltas, which meant it could never
  leave its own column and was re-laid-out under the finger every frame. Two
  things about the edge zones (`kEdgeZone`): the grid steps *immediately* on
  entering one and then repeats on a timer, because waiting for the first beat
  reads as nothing happening; and they **arm only after the block has been
  outside both of them**, since a block in the first column starts its own drag
  inside the left zone and would otherwise step back a week before the finger
  moved. `_edgeStop` runs on drop, on leaving the grid and on dispose - a timer
  that outlives its gesture walks the calendar on its own.
- **Ctrl+wheel zooms, and its `Listener` must be *inside* the scroll view.**
  A scroll signal goes to whichever handler registers with
  `pointerSignalResolver` first and dispatch runs deepest-first, so a listener
  wrapped *around* `SingleChildScrollView` always loses the wheel to it - the
  day would zoom and scroll at once. From inside, claiming the event is what
  keeps it away from the scrollable, and an unmodified wheel is never claimed at
  all. `onZoom` is now passed unconditionally rather than on `layout.touch`:
  there are two gestures for it and the grid is what knows which one it is
  looking at.
- **The hour height is a value, not a constant** (`TimeGridView.hourHeight`),
  pinched on touch, Ctrl+wheeled with a mouse, and stored device-locally in
  `settings`. Everything vertical
  reads it - painter, labels, blocks, `_pointToSlot` - for the same reason
  nothing may read `kGutter` directly. The pinch is a **`Listener`, not a
  `GestureDetector`**: a `ScaleGestureRecognizer` enters the arena against the
  scroll view and wins it on one finger, so the day would stop scrolling. A
  Listener never competes, which leaves one finger meaning scroll and two
  meaning zoom with nothing to arbitrate. The pinched instant is held still by
  re-anchoring the scroll offset after the frame that draws the new height.
- The year view's month tiles are **always six week rows** (`_weekRows`), padded
  with blanks. A month needs four to six depending on where its 1st falls, and
  sizing each tile to its own month left a `Wrap` run ragged. Don't make it
  adaptive again to save a row of pixels.

### The shopping list (`app/lib/ui/shopping_list.dart`)

One throwaway list on the title bar beside the calendar; design in ROADMAP.md
*The shopping list*. The rules that are not obvious from the code:

- **"Current" is derived, never stored**: the newest list with no
  `archived_at` (`LocalStore.openLists`, `AppState.currentList`). Every device
  works it out the same way, so nothing has to keep it exclusive the way
  `enforceSingleInProgress` keeps focus. Two lists started offline leave an
  older open one behind; it is shown as "Also open" (`otherOpenLists`) to merge
  or finish, never hidden.
- **It opens on every return, and the rule lives in one place**,
  `_openListOnReturn` in `main.dart`: after the first frame at launch, on a
  lifecycle `resumed` that followed `hidden`/`paused` (`_wentAway` - plain
  `inactive` is a blink, not a return), and on desktop from `_surfaceWindow`
  and `onWindowRestore` only, because the widget is always open and focus
  changes would drag you to the list every click. It refuses while something
  is being written (a route on top, the add field, a capture) and in focus
  mode. Moving inside the app never calls it.
- **It owns the content area like the calendar**: `showList` is cleared by
  `_closeOtherViews`, so every other view and `toggleCalendar` close it, and
  `setListOpen` commits quick-add blocks when it closes the calendar.
- **Use mode places rows with `AnimatedPositioned` keyed on uuid** at a
  position computed from the row's index (to get, header, ticked), which is
  the whole slide animation. It needs a fixed row height, so an item is one
  line. Unticking puts an item back where it was because a tick never touches
  `sort_order`.

### Collections (`app/lib/ui/collections.dart`)

A per-workspace view beside Notes and Parked (`WorkspaceView.collections`,
`AppState.showCollections`): tables whose fields are defined first. Design in
ROADMAP.md *Collections*. The rules that are not obvious from the code:

- **Fields are rows, entry values are one JSON column.** `collection_fields`
  is a table so a rename on one device and a new field on another both
  survive a merge; `collection_entries.data` is an object keyed by **field
  uuid** (`data`, because `values` is an SQL keyword), so a rename touches no
  entry. The trade is that an entry is last-write-wins as a whole.
- **A removed field's values are kept.** `saveEntry` merges what the form
  showed over what the row already had, so a value under a field that is no
  longer drawn is not dropped by the next edit. `options` on a field is unused
  until choice fields exist and is in the schema so they are not another
  protocol bump.
- **The kind is an input hint.** Every value is text; `FieldKind` picks the
  keyboard, the drawing and the sort (`sortEntries`, `parseNumber`). An unknown
  kind from a newer build reads as text.
- **The entry form's Enter is the feature.** Each typed field's
  `onEditingComplete` is a no-op so the field's own idea of Enter (move along
  the focus traversal, or let go) does not run; `_submitted` focuses the next
  *typed* field (a checkbox would put the phone keyboard away), and on the
  last one adds and clears. `test/collections_test.dart` pins it.
- **Loaded only while open**, the whole workspace's worth (`refreshCollections`,
  called from `refreshTasks`, which is also what a sync merge runs). Search and
  sort are in memory.
- **Table or rows is decided by the width the view got** (`fitsTable`), not by
  `Layout.touch`. The view has two rungs and walks Esc back like the journal.

### The task row, and where its actions went

`TaskRow` (`app/lib/ui/task_row.dart`) is a tick box, a title and the task's
**marks** — and nothing else. The actions live in an overlay bar
(`ui/task_actions.dart`), and the read-only long form in `ui/task_detail.dart`.

The row used to carry them inline in two shapes: hover-revealed icons at the
right-hand end under a pointer, and an always-visible bar of fingertips below
the title on touch. Both paid for the actions **with the row's own width, all
the time**. The desktop icons were invisible at rest but deliberately *kept in
the layout* (revealing one must not reflow the text), so in a narrow window most
of a row belonged to controls that were not on screen; the touch bar was a
second line under every row on the smallest screen there is, and wrapped to a
third on a task that asked for everything.

- **One gesture per pointer, and it is the spare one.** Right-click with a
  mouse, a short tap on the text with a finger. A left-click *expands* the row;
  editing is the pencil inside the bar on both. The table in the file header is
  the authority — keep it true.
- **The double-click that edits is hand-rolled, and must stay that way.**
  Registering Flutter's `onDoubleTap` beside a tap puts both recognisers in one
  arena, and the tap then cannot fire until the double-tap window expires — so
  a second way into the composer would cost 300ms of lag on *every* expansion,
  which is the commonest click on the list. Instead the first click expands
  immediately and arms a `Timer(kDoubleTapTimeout)`; a click arriving while it
  is live undoes that expansion and calls `onOpen`. Two consequences worth
  keeping: a double-click leaves the row exactly as it found it (it is one
  gesture, not a click plus an edit), and the undo touches only the *in-place*
  expansion — where the shell owns the read view (`onExpand`, touch) there is
  nothing to put back and calling it again would open it twice. The tests drive
  it through a `click` helper that waits out the window, because
  `pumpAndSettle` advances the clock by about a frame and two of those in a row
  are a double-click.
- **The bar resolves to a `TaskAction`, and the row turns that back into a
  callback.** That is what keeps the reminder menu and the park picker — both of
  which want anchors of their own — out of a widget whose job is to draw nine
  icons. An action whose callback is null is simply not in the list, which is
  how the session view's rows come out with four buttons and the list's with
  nine (same shape as `onPlanTask` and `onDrop`).
- **The anchor is a rect in the *overlay's* coordinate space**, not the screen's
  (`taskActionAnchor`). `UiScale` sits above the `Navigator`, so a route lays
  out in layout units while `localToGlobal` with no ancestor reports scaled
  screen pixels — anchoring on the latter puts the bar a fifth of the way down
  the screen from its row on a phone. The reminder menu and the park picker are
  anchored off the same helper now that neither has an icon to hang from.
- **The bar is placed by a `SingleChildLayoutDelegate`**, not a `Positioned`:
  where it goes depends on how big it turned out to be (the item list is per row
  and the `Wrap` picks its own line count), and a delegate is handed the child's
  size. Below the row if it fits, above it if not, pinned to the bottom edge
  only as a last resort — a bar half off the screen is a bar with a missing
  delete.
- **What stays on the row is state, not actions** (`_StateMarks`): an armed
  bell, a paperclip, a planned-into mark, and the flagged task's red bar. They
  are not pressable. They were lit-up *buttons* before precisely because they
  were state as much as controls; only the state half is left.
- **Expanding is two implementations of one action, and the row picks by
  whether it was handed `onExpand`.** Null means grow in place (a pointer: the
  list scrolls past it and the rows around it stay put). Non-null means the
  **shell** takes it — on a phone the read view gets the whole content area, the
  way an open journal entry does, which a row inside a scrolling list cannot do
  for itself. `main.dart` passes it only where `_expandsToScreen`.
- **The shell holds the expanded task as a uuid**, not a `Task`: the list is
  reloaded under it constantly and a held row would be a copy that went stale.
  `_taskTakesScreen` is guarded **structurally** — no view open, no calendar, no
  focus mode — rather than by every path that opens something else, because a
  rule each call site has to remember is the rule that gets missed (see the
  quick-add commit rule for how that goes).
- **Reordering is per pointer too.** A pointer gets `dragHandle` on the *right*
  (it was on the left, indenting the title of every row for a control only a
  mouse can use); touch gets no handle at all and a
  `ReorderableDelayedDragStartListener` around the whole row. Safe to take the
  long press: the row's own gestures are a tap and — only where something is
  beside the list — a *horizontal* drag, which never happens on a screen that
  narrow.

### Dragging a task somewhere (`app/lib/ui/task_drag.dart`)

There are two things a task can be dragged onto — a calendar block ("do this
then") and a parked group ("not now") — and they are **one gesture with one
piece of feedback**, so `TaskDropTarget` and `TaskDragFeedback` live in a
neutral file. `TaskDropTarget` used to be in `calendar/time_grid.dart`; the
parked panel importing the calendar to get at a drop target was the wrong shape
of dependency, and a second copy would have been worse.

- **The drag *source* stays in `main.dart`** (`_plannable`), because whether a
  row can be dragged at all is a question about *layout* — there has to be
  something beside the list to drop onto — and the shell is what knows the
  layout. One `Draggable` covers both targets: what the drag means is decided by
  where it is let go, and the two can never be on screen at once (the calendar
  replaces the content area the parked panel lives in).
- **`affinity: Axis.horizontal`** is what keeps it out of the list's way: a
  vertical drag still scrolls, and reordering keeps its own gesture — the ⠿ grip
  under a pointer, a long press on touch.
- **A null `onDrop` makes the target its child and nothing more.** That is how a
  panel with no list beside it simply has no drop targets, rather than inert ones
  — the same shape as the calendar's `onPlanTask`.
- **The whole parked-group card is the target, collapsed or not**, and a drop
  *opens* the group. Aiming at a group's contents would leave an empty or closed
  shelf nothing to hit, and those are the ones something is most likely being put
  away into; opening it is the only visible confirmation the task landed, since
  otherwise a closed shelf just shows a bigger number.

### Reviewing a shelf (`app/lib/ui/parked_review.dart`)

A group's review interval is the thing that stops a shelf being a landfill, and
until 0.28.0 the review itself was a button called *Mark reviewed* under a
collapsed list of one-line rows — reachable without having read any of them. The
review is now a **funnel**: one task fills the pane, with the things a decision
needs (notes, "parked 47 days ago", an armed reminder), and four answers of
which exactly one leaves it alone. Three properties are load-bearing:

- **The queue is a snapshot** (`_queue` on `_ParkedPanelState`, taken in
  `_startReview`). Every answer but Keep takes the task off the shelf, so a
  funnel reading `parked[group]` live would renumber under the hand and skip
  whatever moved up into the current slot.
- **Reaching the end is the review.** `onFinished` — and therefore
  `markGroupReviewed` — fires from the last `choose`, not from opening. Leaving
  early keeps the decisions already written and does *not* restart the clock;
  those are two separate facts and trading one for the other is how a shelf gets
  a fresh timestamp it did not earn. An **empty** shelf is finished on open, from
  a post-frame callback in `initState` (the owner reacts with `setState`).
- **Enter is Keep.** The failure mode of a review under time pressure is
  bulk-answering it, so the answer that should be cheapest to give is the one
  that changes nothing.

The funnel is a **rung of `ParkedPanel`**, not a view of its own, so nothing in
the shell had to learn about it — the panel holds a `FocusNode` and walks Esc
back down the ladder exactly as `JournalView` does. Note the review's own node
is a *descendant* of the panel's: key events travel from the primary focus
upwards, so a `CallbackShortcuts` under the panel's node would never be reached,
and the funnel's node returns `ignored` for anything but Enter so Esc goes on up.

**Adding straight to a shelf** is `_AddToShelf`, one line at the foot of an open
group, wired to `AppState.addTask(..., groupUuid:)`. One call rather than
add-then-park: the pair writes the row twice and puts the first version on the
active list for as long as the second write takes, which is a task appearing and
vanishing on a list nobody asked to put it on.

**A task leaving a shelf for a list is retitled "Shelf: title"** (`_offShelf`
in `AppState`, applied by `unparkTask`, `unparkGroup`, `deleteGroup` and
`moveTasks` when the target is a list). One query for every shelf's title
(`LocalStore.groupTitles`) because the move picker can take a task off another
workspace's shelf. `recur_text` is prefixed too, or the next occurrence of a
repeat would be spawned without it. Shelf to shelf is left alone.

`AppState.unparkGroup` is the reverse and is deliberately **not** `deleteGroup`:
same release loop, no tombstone, because emptying a backlog is not the same as
deciding you no longer keep one. It filters to open tasks — `allTasksInGroup`
returns completed rows too, since a group being *deleted* has to release those
as well — and hands out sort orders in one pass. `test/parked_test.dart` and
`test/parked_panel_test.dart` split the two halves: what the move does to the
database, and the gestures that ask for it.

### Markdown and maths (`app/lib/ui/markdown_text.dart`)

Every long-form field renders through **one** widget, `MarkdownText`, differing
only in the base `TextStyle` it is handed: a task's `notes`, a journal entry's
body, a calendar event's `description`. The style sheet is *derived* from that
base rather than written per surface, for the same reason `UiScale` exists
instead of a mobile fork of every padding.

The dialect is GFM plus GitHub's maths, built on `flutter_markdown_plus` +
`markdown` + `flutter_math_fork`. Nothing about it is stored — this is a
rendering layer over text that was already in the database, so there is no
schema change and no migration.

- **The custom syntaxes go first** in `markdownExtensions`. Both parsers
  evaluate what the `md.Document` was handed ahead of their own standard set,
  and both orderings matter: ```` ```math ```` has to be seen before the ordinary
  fenced-code syntax claims it, and `$…$` before the escape syntax eats the `\$`
  of an escaped dollar.
- **The `$…$` rule is pandoc's**: no whitespace against a delimiter, and no digit
  after the closing one. That is what keeps "it costs $5, or $7 with tax" out of
  the maths renderer — and it is not a nicety, because switching this on re-parses
  every note anyone had already written. `test/markdown_test.dart` pins it.
- **`_MathBlockSyntax` returns a `p` wrapping the `math` element**, never a bare
  block-level one. `isBlockElement()` is a property of the *builder*, not of the
  element, so making the standalone form a real block would have made every
  inline `$x$` a block too.
- **A preview flattens, it does not render.** `markdownPlainText` walks the
  parsed tree — that is what makes `**done** by 5` preview as "done by 5" without
  a pile of regexes each getting one case right. Used by the notes line under a
  task title and by the agenda's description line, neither of which has room to
  lay out a heading.
- `softLineBreak: true`, unlike strict Markdown. These are notes; a stack of bare
  lines is written far more often than a paragraph is wrapped by hand.
- Not selectable, deliberately: selection fights the tap that opens the editor.

### Links in titles (`app/lib/link_titles.dart`)

A URL in a task's title is **drawn** as the page's title by `LinkedText` (the
row and the read view); the stored text never changes, so there is nothing in
the schema and nothing to sync. `LinkTitles` asks once per URL per device and
keeps answers - including "no title" - in the device-local `link-titles`
setting (capped); a failure is retried only on the next launch. Native builds
ask the page (`fetchLinkTitleDirect`); the web build asks
`/api/link-title` (`server/links.js`), which is `feeds.js`'s shape - account
only, every redirect hop checked against private addresses, head of the page
only - plus an in-memory cache. **`titleFromHtml` exists on both sides and
must agree.** `LinkedText` is stateful because it owns the span recognisers.

### Voice notes (`app/lib/voice_notes.dart`)

The thought pane's 🎙 **records** (`voice_recorder.dart`, MediaRecorder via
`todoRecorder` in `web/index.html`; web only - natively
`VoiceRecorder.supported` is false and no button is drawn). It replaced
dictation, whose transcripts were not worth keeping. Things that are
load-bearing:

- **A row names its recording by digest**: `audio` (SHA-256) and
  `audio_ms` on `side_thoughts` **and** `tasks` (v20, protocol 6). Columns
  on both rather than an attachment, because the web build has no
  attachments and the phone is where these are made; `moveThoughts`
  carries them onto the task.
- **Bytes travel on their own channel**: the device-local `blobs` table
  (not in `tables`, never synced as rows) holds what was recorded here with
  `uploaded` 0 until `SyncService._uploadBlobs` has `PUT /api/blobs/:sha256`
  it after a sync that worked; a 404 (older server) leaves it queued.
  Other devices `GET` it on first play and keep a copy, trimmed past
  `VoiceNotes.cacheBytes`, never a pending one. The server
  (`server/blobs.js`) checks the body hashes to its name and keeps bytes per
  account in the database file; `purgeUser` deletes them.
- **iOS plays only from an element a tap started**, and the bytes arrive
  after the tap, so `VoiceNotes.toggle` calls `VoicePlayer.prime()` before
  awaiting anything (`todoAudio.prime` plays a generated silence on the
  page's one element). Natively it is media_kit from a temporary file.

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
- **`adopt` is the manual way out of "not on this device"**, and content
  addressing is what makes it safe: the row already names its bytes by digest,
  so a file the user picks is *checked* rather than trusted. A copy under
  another name is recognised; a different document is refused and offered as a
  new attachment. It writes no row - nothing about the attachment changes, so
  nothing syncs and this is one device catching up with itself. It is not blob
  sync and does not pretend to be; that is still in FEATURES.md's backlog.
- A row tombstoned on another device arrives as a *merge*, so the local delete
  path never runs. `AppState.sweepAttachments()` at startup is the only thing
  that ever collects those bytes.

### The quick-action menu is data, not a manifest

`quick_actions.dart` re-registers its items whenever the focused task changes -
`_onState` calls `setActiveTask(s.focusTask?.text)` on every notify and the
class drops the call unless the *title* it would print has moved. Three things
about it:

- **`in_progress` is already "the active task".** It is exclusive and global by
  construction, so naming one in the menu needed no column and no second
  concept. Focus mode is how you set it.
- **The menu outlives the process.** Both platforms keep the last list handed to
  `setShortcutItems`, so a press can arrive naming a task that was completed on
  another device hours ago. `_noteOnActiveTask` therefore re-reads `focusTask`
  rather than trusting the entry, and falls back to the add field; and
  `AppState.appendToNotes` re-reads the *row* before writing, because the copy
  the shell is holding may be older than what sync has since brought in. It
  appends - a whole-field save from that path would drop whatever arrived.
- **iOS shows four items at most**, static and dynamic together. Three is the
  budget spent.

The pane it opens is `ThoughtSheet` with three strings changed. That widget is
the answer to "one line, written blind, on a phone held in front of people", and
this is the second thing that is; a copy would have drifted.

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
- `radio_library.dart` holds starred and hand-added stations as JSON in
  `settings` (device-local). A station's identity is `RadioLibrary.keyOf` - the
  directory uuid, or the URL for a custom stream, which deliberately has no uuid
  so `reportPlay` never reports it. `NowPlaying.id` uses the same key.
- `sources.dart` talks to archive.org and Radio Browser. Both are key-free;
  Radio Browser's client requirements (user agent, mirror fallback, play
  reporting) are honoured there.
- `ambience_cache.dart` keeps **bouts** — 30-minute prefixes of a recording — on
  disk beside `todo.db`. Tier 2 is the only one that had anything to gain: noise
  is already local and a station is a live stream. Four things are load-bearing:
  - **A prefix, asked for with a `Range` header**, sized from the `size` and
    `length` the search already returns (`AmbienceCache.boutBytes`, with an
    assumed 128kbps when the metadata says nothing). A truncated mp3 plays to
    its last whole frame, which is what looping wants. The cap is applied on
    the way *in* as well as asked for, because a server may ignore `Range`.
  - **Several per preset, picked at random.** Caching one recording would buy
    the latency and spend the variety, and the variety is what a preset *is* —
    it is a query, not a file.
  - **Filled behind the music, never waited on.** A play with nothing stored
    streams as before and calls `store` afterwards; a play from the cache calls
    `fill`. Making somebody wait for 29MB before any sound came out would trade
    one kind of lag for a worse one.
  - **The index is a file in the cache directory**, not a row and not a setting,
    so the class needs a directory and an injected fetcher and nothing else —
    which is what makes `test/ambience_cache_test.dart` possible without a
    network. Filenames in it are bare, because the application support directory
    moves between installs and an index of stale absolute paths is a cache that
    empties itself.
- Synthesis runs on a background isolate via `compute` — on the main isolate it
  drops frames.
- **iOS needs two things to keep playing with the screen off, and one alone does
  nothing.** `UIBackgroundModes: audio` in `Info.plist` *permits* background
  playback; the `AVAudioSession` category set in `AppDelegate.swift` is what
  *asks* for it. Without the category the default is `.soloAmbient`, which the
  lock switch silences. The category is only set, never activated — activation is
  what interrupts other apps' audio, and libmpv does it when a source actually
  starts, so launching the widget does not stop your music.

### Sync

`SyncService` reconciles in the background; the UI **never waits on it**. The
app always reads and writes its own local database first. Conflicts are last-
edit-wins per row. A merge that brings rows in must refresh what's on screen —
that's the `onChangesApplied` callback wired up in `main()`.

The offline queue is not a queue — it's the `dirty` column, which is why it
survives a crash and needs no replay log. `pendingCount()` counts it and
`describe()` surfaces it, so an unreachable server reads as queued, not lost.

**`dirty` means "*a* server accepted this row", not "*this* server did."** That
distinction cost 187 rows once: the sync database was rebuilt, every local row
was already clean from the old one, so the client pushed nothing and the new
server only ever received what happened to be edited afterwards. Both sides were
internally consistent and permanently different, and a second device set up
against the new server pulled the fragment and looked correct. Two signals now
catch it, and they are separate because either can fire without the other:

- **The cursor going backwards** (`SyncClient.syncOnce`). On a given server a
  user's cursor only grows — `seq` is monotonic and rows are tombstoned, not
  deleted — so an answer below what we sent is proof this is a different
  database. Note `purgeUser` is the one thing that legitimately resets it, and a
  re-arm is the right response there too.
- **A fingerprint of address + account** (`kServerFingerprint`, checked in
  `SyncService._reconcileFingerprint` right after `whoAmI`). Catches the swaps a
  cursor cannot see: a different token at the same address, or a move to a
  server that happens to be further along.

Either re-arms every row via `LocalStore.markAllDirty()`. **A needless re-arm is
free and that is what makes this safe to be aggressive about** — `mergeRow` gives
ties to the incumbent, so an in-sync database writes nothing server-side, burns
no `seq`, and re-broadcasts nothing. An absent fingerprint therefore re-arms too:
a database that has never been checked cannot be distinguished from one that has
been diverging for a month, and proving it costs one request.

### The wire has a version, and it is not either program's

`server/protocol.js` and `app/lib/sync/protocol.dart` hold the same two numbers
on each side: what this end speaks, and the oldest other end it will accept.
The number is **the wire**, not the app's version and not the server's — those
move on every release, and almost every release leaves the wire alone. That is
the whole reason it is a number and not a table of "app 0.24.x works with server
1.2–1.4": a table is a second thing to edit on every release, it goes stale in
silence, and its failure mode is claiming a pair works when it does not.

The 0.24.0 deploy is what it is for: the app wrote `recur` and `all_day`, the
server had neither column, and the only symptom was those fields arriving null
on the other device. Nothing said anything, and nothing could.

- **What moves `PROTOCOL`.** A required field, a renamed one, a changed meaning,
  a different conflict rule, an endpoint the client cannot work without — and
  **a new column**, however optional. That last one used to be listed as *not*
  moving it, and it was wrong in the direction nobody looked at: an older server
  drops a column it does not know, but an older **client** inserts pulled rows
  verbatim, so one unknown column fails its whole merge and the device stops
  receiving anything. v16's `feed_uuid` did exactly that to every un-updated
  device the moment the server was deployed. So a new column now bumps the
  number and goes in `COLUMN_SINCE` (a table in `TABLE_SINCE`) in `db.js`; the
  client sends its protocol in the `/api/sync` body, and the server withholds
  what that protocol does not cover — and keeps the stored value when such a
  client pushes the row back without it. Clients from 0.29.0 on also drop an
  unknown pulled column themselves (`_columnsOf` in `applyRemote`), but the
  server rule is what protects the builds already out there. A client gaining
  a protocol has to re-pull what was withheld: v16 resets the cursor for that.
  `MIN_CLIENT` moves far more rarely still: raising it cuts devices off until
  they update.
  **Not** an optional endpoint — `/api/events` returning 404 already means "no
  instant sync, carry on".
- **An absent number is 1**, on both sides. Protocol 1 is what the wire was on
  the day the number was invented, so every server already deployed is protocol
  1 by definition and nothing had to be upgraded in lockstep. Without that rule
  this would have been a flag day, which is the exact kind of upgrade it exists
  to prevent.
- **Asked on `/api/health`, before anything is exchanged.** `_agreeProtocol` in
  `SyncService` runs ahead of `syncOnce`, not after it — `whoAmI` (where the
  fingerprint check lives) runs on the back of a sync that already *worked*,
  which is far too late to gate one. Health is unauthenticated, so the answer is
  available at setup before a token exists. The same pair is repeated on
  `/api/me` so the loop can read it without a second request.
- **Unreachable is not incompatible.** A probe that fails tells us nothing about
  the wire, so the sync runs and reports the network failure in its own words. A
  server that is merely down must never read as one that needs updating.
- **Agreed once per configuration, re-asked every cycle while it is failing.**
  That is the right way round: the failing case costs one request *in place of*
  the sync it is refusing, and re-asking is what makes syncing resume by itself
  the moment the server is deployed. `configure()` forgets it — a different
  address is a different server.
- **`SyncStatus.outdated`, deliberately not `blocked`.** Blocked means "check
  the address and token", and sending someone to their credentials for a version
  problem is a wasted afternoon. Two directions, two sentences: the client being
  behind says *update the app*, the server being behind says *update the
  server*, because there is nothing to be done on a phone about a server that
  needs deploying.
- **Blocking is airplane mode with a reason.** No rows move, the local database
  is untouched, `dirty` keeps filling, and `UpdateSheet` says so in as many
  words — the first thing anybody reads "syncing is off" as is "where are my
  tasks". The sheet is closable and shown once per mismatch: it re-checks every
  cycle, and a screen that reappeared every minute is one you learn to dismiss
  unread.

### Instant sync is a hint, not a channel

`server/events.js` holds an SSE connection per running device, keyed by user, and
`POST /api/sync` broadcasts to that user's *other* devices whenever the merge
actually wrote something (`sync()` returns `merged` for exactly this; the route
strips it from the response). `ChangeStream` on the client turns a hint into a
`syncNow()`.

**Nothing about the data travels down it.** That is the whole design constraint:
rows enter the database through `SyncClient.syncOnce` and nowhere else, so there
is still one merge, one conflict rule and one tombstone path. Consequences worth
keeping:

- **A dropped hint costs latency, nothing else** — the 60s poll is still running.
  That is why there is no acknowledgement, no replay and no per-connection
  cursor; none of it would ever earn its keep.
- The hint's payload carries a cursor and `ChangeStream` **deliberately ignores
  it**. It arrived outside the transaction that produced it; the sync it triggers
  computes its own.
- `onHint` calls `syncNow`, **not** `scheduleSync`. The 2s debounce exists to
  coalesce *our own* typing, and a hint means the rows are already on the server —
  debouncing it would add back the latency this exists to remove.
- **A 404 turns the feature off for good** (`supported`), rather than retrying an
  older server every two seconds forever. A 401/403 likewise stops: reconnecting
  never mints a credential.
- `X-Device-Id` is how a push avoids coming back to its own author. It is not a
  credential and is not trusted for anything — the bearer token already
  established *who* — so the worst a wrong one does is cost its owner one
  redundant sync.
- `resume()` drops the stream outright. A suspended process holds a socket the
  other end abandoned and cannot know it: no packet says so, and the watchdog
  that would notice was frozen too.
- **Behind a reverse proxy this needs one line** (`flush_interval -1` in Caddy,
  `proxy_buffering off` in nginx) or the stream is buffered into uselessness —
  see `server/DEPLOY.md`. It fails *soft*: without it, sync is exactly what it
  was before, one minute slower.
- `ChangeStream.stop()` sets `_connected` directly instead of going through
  `_setConnected`. Firing `onStateChanged` from a teardown means calling
  `notifyListeners` on a `SyncService` that may be half way through `dispose()`.

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

- **Window modes** (`window_spots.dart`, the title bar's □ beside
  Minimize): **no presets**. Marco arranges the window by hand and *Save this
  window…* keeps its exact bounds under a name he types
  (`askWindowModeName`); saving under a taken name replaces that one in
  place, which is how a mode is moved. The one built-in row is *Full screen*
  (`windowManager.maximize`), because it is the only arrangement that means
  the same on every screen. A `WindowMode` stores the bounds **and the work
  area of the screen it was saved on**: `placeIn` uses the bounds as they are
  while a screen still holds them, and carries them over in proportion to
  the current screen when it does not (monitor unplugged); the area also
  draws the row's picture. Device-local (`AppState.windowModes`,
  `window:modes`). The menu drops down on
  hover (`_WindowModes`, the volume panel's arrangement: an `OverlayEntry`
  on a `LayerLink`, one hover fed by button and panel, a grace timer to
  cross the gap, and a 150ms open delay so passing over it on the way to
  Close opens nothing); a click opens it too. The maths is pure and tested;
  `_windowAndAreas` in `main.dart` asks `screen_retriever` for each display's
  *visible* area (the work area, minus the taskbar) and picks the one
  holding the window's middle.

- `TitleBar` is the drag handle, via a `DragToMoveArea` **behind** its row,
  not around it. Around it, its pan recogniser is an ancestor of the buttons
  and of a top dock, and a press-and-slide on a dock segment would move the
  window. Behind, it gets only what nothing in the row took - which is why the
  "Todo" label is an `IgnorePointer`.
- **Always-on-top is re-asserted, not set.** `WS_EX_TOPMOST` is not ours alone
  to hold — another application going full screen makes Windows strip it from
  every other window, and nothing restores it when that application exits, so a
  pin set once in `main()` silently stopped being true (closing Windows Photo
  Viewer was the reproducible case). `_ensurePinned` on the shell runs from the
  reminder poll and from `onWindowFocus`; `_pinned` is the **intent**, the style
  bit is the fact, and the two are reconciled. It **reads before it writes**:
  `window_manager`'s `setAlwaysOnTop` is a `SetWindowPos` without
  `SWP_NOACTIVATE`, so calling it unconditionally on a 20-second timer would
  raise and activate the window every time round.
- **Sheets animate through `SheetTransition`** (`ui/sheet_transition.dart`),
  which owns *how* a panel moves; each sheet still returns its own `Positioned`
  and so owns *where* it sits. The child goes into a nested `Stack` precisely
  because a `Positioned` is only legal as a direct child of one and still has to
  be translatable. The exit is the part with machinery: a widget removed from
  the tree cannot animate itself out, so the host caches the last child it built
  and keeps showing it until the reverse finishes — which is also why the
  builder is a callback. A sheet built from a nullable field - the quick
  action's `_noteOn!`, say - loses it the instant it closes. Its `AnimationController` is built in `initState`,
  **not** as a `late final`: a sheet never opened never reads it from `build`,
  so a lazy field is first touched by `dispose`, where `vsync: this` looks up
  `TickerMode.of(context)` on a deactivated element and throws.
- **Every *form* opens as the same panel** (`ui/form_sheet.dart`): the task
  composer, the event editor and the event details card. `showFormSheet` is a
  `showGeneralDialog` with the surface drawn from `T`, full width against the
  bottom edge on touch and a centred column under a pointer, and `FormSheet` is
  the titled body with its actions along the bottom. It started as `_Surface`
  inside `task_composer.dart` and moved out when the second and third form
  wanted it — a copy of a shape whose whole point is that every form looks the
  same is the copy guaranteed to drift. Two things it fixes that Material's
  `AlertDialog` caused: the panel is lifted by `viewInsets` so the last row of
  controls is reachable with the keyboard up, and the actions are a `Wrap`, so
  four finger-sized buttons take a second line instead of an `OverflowBar`
  claiming the height and squeezing the card's own content into nothing (which
  is what drew the "white rectangle" on a phone). `accent` is the workspace's
  colour on a task and the *calendar's* on an event, so a form belongs to what
  opened it. The `Layout` is passed **in**, not read from context: these are
  routes, and a route sits above the shell's `LayoutScope`.
- **The content area keeps its element through every rearrangement of the
  chrome** — `contentSlot` in `ui/content_slot.dart`, which is a key and an
  unconditional `Stack` and nothing else. `_takesScreen` removes the workspace
  bar above and the view bar and footer below in the same frame a note is
  opened, and Flutter matches unkeyed children of a multi-child widget **by
  position**: the content went from child 2 to child 0, matched nothing, and the
  whole subtree was rebuilt. That threw away `JournalView`'s State, which is
  what holds *which rung of its ladder* you are on — so on a phone a note
  reported itself open, the shell hid the chrome, and the panel snapped back to
  its list one frame later, looking exactly like the note refusing to open. The
  Stack is built unconditionally, with `overlay` as an optional child, for the
  same reason: a Stack that comes and goes is the same structural change one
  level down. `test/content_slot_test.dart` pins it, and fails if the key goes.
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
- **Design tokens live in `theme.dart` (`T.*`) and nothing may pick its own
  number.** One radius (`T.radius`), one spacing scale (`T.s1`-`T.s5`), four
  type sizes (`T.fsBody`/`fsLabel`/`fsMeta`/`fsMenu`) plus `T.fsTitle` for a
  view's name and nothing else, and two weights. Two faces: the platform one
  for body text and `T.fontDisplay` (Space Grotesk, bundled in
  `assets/fonts`, Regular and Medium only) for what names things - view
  titles, counts, the dock, group titles. Text on a solid colour is
  `T.inkOn(fill)`, a deep shade of the fill's hue, never black. There
  were six radii and six sizes inside a 4.5-point range before 0.27.0, which is
  what "too standard productivity app" turned out to mean. Two escapes exist
  and both are documented at the token: `T.wStrong` for **content** emphasis
  (Markdown's `**bold**` has to look bold; the rule is about the widget's own
  labels) and `T.fsGrid` for text laid *into* the calendar, where a box is
  sized by duration or column count rather than by its contents - a 15-minute
  block at the default hour height is 14px tall, and `fsMeta` in it is an
  overflow the test suite catches. Colour is likewise one job per token:
  `danger` is destructive **only**, `warn` is attention that costs nothing (an
  overdue reminder, a retrying sync), `flagged` is the priority bar. Durations
  that used to be duplicated between CSS and JS have exactly one copy each.
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

  **The zoom setting rides on the same transform** (`UiScale.zoom`, from
  `AppState.zoom`). That one multiplies the automatic zoom and *may* take the
  layout below `designWidth`: that is what "bigger" means in a window that
  stays the same size, and the narrow layouts already exist. It stops at
  `T.minLayoutWidth`, the window's resize floor, the narrowest box anything
  was ever made to work in. `AppState.zoom` is a `ValueNotifier` as well as
  a setting because `TodoApp` builds `UiScale` and has no other reason to
  rebuild on AppState's notifications. Ctrl +/−/0 are desktop-only: in a
  browser those keys are the browser's zoom, and taking them as well would
  apply two zooms at once.

### Adapting to the size (`app/lib/layout.dart`)

`Layout` is the **single place** any size-dependent decision is made. Every
threshold is a named getter on it; `WidgetShell` measures its own box in one
`LayoutBuilder` and publishes it as `LayoutScope`, so a descendant asks
`Layout.of(context)` rather than adding a `LayoutBuilder` and a number of its
own. Two rules hold everything together and both are load-bearing:

- **No size takes a feature away.** A view may change shape when it does not fit
  — the week grid becomes an agenda, the year stacks into one column, the
  dock moves off the bottom edge — but nothing becomes unreachable.
  That is what separates this from a mobile/desktop fork, and it is why the fix
  for a cramped view is a fallback here, *not* a call to `windowManager.setSize`.
- **The design width is the floor, not the target.** Extra room buys more at
  once (a rail, a second pane), never a stretched copy of the same thing — hence
  `taskColumnMax` and `focusTileMax`.

**`Layout.touch` is the one axis that is not a size**, and it is separate
because the questions genuinely differ: every other getter asks *does it fit*,
this asks *can it be reached at all*. A 340px desktop window and a 340pt phone
lay out identically and still need different controls, because one has a hover
state and a 3px pointer and the other has neither. It exists because pretending
otherwise had already cost real function — every action on a task row was drawn
behind `visible: _hovered`, so on a phone reminders, parking, focus and delete
were not small, they were **absent**, and no width would ever have revealed
them. (The actions have since moved off the row entirely — see *The task row* —
but the axis is what decides which gesture opens them and how big they are
drawn.) It is a field on `Layout` (set from `!isDesktop`, default false) rather
than a `Platform` check at the point of use, so there is one place to read, one
to change, and a test can pump a touch layout on a desktop machine. `tapTarget`
and `actionIcon` hang off it; 40 rather than Apple's 44 because the number is
spent *inside* `UiScale`, whose smallest real-phone zoom is about 1.1.

Notes for changing it:

- The thresholds are worked backwards from **contents**, and the tests assert
  them that way: `weekGridFits` is "seven columns of at least `minDayColumn`",
  not a round number, and `calendarSplitMinWidth` is "the task pane at its
  design width plus a week grid at `roomyDayColumn`". Keep new ones in the same
  shape or `test/layout_test.dart` has nothing to check them against.
- Where a view has a compact shape, the threshold is measured against **that**
  shape. `minDayColumn` is 40 rather than 62 because the narrow week is drawn
  with the compact grid geometry; measuring the compact case against the roomy
  numbers is what had a 340px phone falling back to a list.
- `_layout` on the shell is assigned *during build* and read by the focus
  flight, which runs from a callback and has no builder context. It is a record
  of what layout just decided, so nothing notifies off it.
- `isWide` (it was `hasRail`) and the split pane are gated on **height** as
  well as width. It is what moves the dock off the bottom edge, and a wide,
  short window (phone landscape, a widget squashed against the taskbar) keeps
  it at the bottom.

### What's new (`app/lib/whats_new.dart`)

**Every deploy of the app - the web build to `/srv/todo-web`, or a release of
the native app - adds a `ReleaseNote` at the top of `kReleaseNotes` with a new
`id`** (the date; a suffix for a second one that day). That is the whole of how
a device knows it has something to show, so a deploy without one shows
nothing, and reusing an id shows nothing either. Write the points for Marco,
not for the code: what he will notice, one sentence each - FEATURES.md's
changelog is the long record.

- **An id, not the version.** The web app is redeployed many times per
  version number; each is still an update to the person reloading.
- **Seen is device-local** (`whats-new:seen` in settings). `checkWhatsNew`
  runs from `main()`, deliberately **not** from `AppState.load`, so no test
  that builds the shell ever has a box open over it.
- **No stored id** is a fresh install or a device from before the box: a
  database that has ever held a task (`LocalStore.hasAnyTask`) gets the
  latest note, an empty one is marked seen silently.
- **Marked seen when it opens**, not when it closes, so a reload with the box
  up does not bring it back. At most `kMaxNotesShown` notes at once.
- It opens after `_openListOnReturn` in the shell's first post-frame
  callback, over whatever that opened.

## Gotchas

- **The old Tauri build is gone from the working tree**, not from history:
  `git show legacy-tauri:...`. See the note under the layout table.
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

### The web build

The same app compiles for the browser and is served by the sync server
(`TODO_SYNC_WEB`, see `server/DEPLOY.md`); `server/build-web.sh <dir>` builds and
publishes it. Three rules keep it compiling and starting:

- **Ask `platform.dart`, never `Platform`.** `dart:io` compiles into a web build
  and then throws the first time `Platform.isX` is read, so a stray check is a
  blank page, not a false. `isDesktop` / `isMobile` / `isWindows` / `isWeb`
  check `kIsWeb` first, and every `supported` getter (tray, hotkeys,
  notifications, quick actions, startup, taskbar) reads from them.
- **Shared store code imports `package:sqflite_common/sqflite.dart`**, never
  `sqflite_common_ffi` (which pulls in `dart:ffi`). `sync/db_factory.dart`
  picks the implementation by conditional export; on the web it is WASM SQLite
  in IndexedDB, and `web/sqlite3.wasm` + `web/sqflite_sw.js` are fetched by
  `dart run sqflite_common_ffi_web:setup`, not committed.
- **The safe area comes from the page, not the engine.** Flutter's web engine
  reports `viewPadding` as zero everywhere, so a home-screen web app on an
  iPhone laid the view bar over the home indicator and a swipe up on it went
  home. `web/index.html` adds `viewport-fit=cover` (and swaps Flutter's
  `maximum-scale=5.0` for `1.0`, or iOS zooms into every text field under
  16px and the app, owning every touch, can never be pinched back out) to
  the viewport tag Flutter
  inserts (without it iOS reports the inset as zero too) and exposes
  `todoSafeBottom()`; `web_safe_area.dart` reads it and `_withWebSafeArea` in
  `main.dart` puts it into the `MediaQuery` above `UiScale`, so the shell's
  ordinary `SafeArea` does the rest. **Cover is for the home-screen app
  only** (`navigator.standalone` / `display-mode: standalone`): in a browser
  tab it ran the page under the browser's bottom toolbar, and on iOS a tap
  there brings the toolbar back instead of reaching the dock - the whole dock
  was untappable in Firefox. Without it a tab ends above the toolbar.
- **Notifications are pushed by the server** (`server/push.js`), because a
  browser cannot schedule anything: a page that is closed runs no code. The
  server already holds every task and event row, so it reads what is due once
  a minute and sends a Web Push to every subscription of that account,
  claiming each `row:instant` key in `push_sent` first so a restart or an
  overlapping tick never sends twice. Its rules are the client's - parked
  tasks are quiet, `eventLead` is `CalendarEvent.notifyLead`, and `nth` is a
  port of `Recur.nth` counted in the server's local time. **Change one and
  change the other.** The browser half: `web/push_sw.js` (the site's only
  service worker - `web/flutter_bootstrap.js` exists to stop Flutter
  registering its own at the same scope, which would replace it and drop the
  subscription), `todoPush` in `index.html`, `web_push.dart`, and
  `ui/push_settings.dart`. The key is fetched when that row appears, and
  `_turnOn` calls `WebPush.enable` before awaiting anything: a browser shows
  its permission prompt only while the tap is still being handled.
  `POST /api/notify` is the same send for news from outside the app
  (`readNotification`, `notifyUser`), not recorded in `push_sent`. It takes
  a **notify-only token** (`tokens.scope = 'notify'`): `identify()` refuses a
  scoped token unless the route passed that scope to `middleware()`, so a new
  route is closed to it by default - keep it that way.
- **A field that opens on a tap needs `primeWebKeyboard()` inside the tap**
  (`web_keyboard.dart`, `todoPrimeKeyboard` in `index.html`). iOS shows the
  keyboard only for a focus moved during a touch's own event handler, and a
  pane's field is built a frame later; the page focuses a throwaway 16px
  input inside the tap so the keyboard is already up when the real field
  takes over. `_openThoughtCapture` does it (web + touch only). The field
  itself must still ask for focus outright, after its first frame -
  `autofocus` gives way to the shell's key handler, which always has focus
  (`ThoughtSheet.initState`; `test/thought_sheet_test.dart` pins it).
- **Native-only features are switched off at their entry point, not stubbed.**
  `main()` skips `MediaKit`, the legacy import and the attachment store on the
  web; `blobs == null` is what hides the paperclip, and a null `onToggleSound`
  hides the sound button. A feature that cannot work is absent rather than a
  control that does nothing.
