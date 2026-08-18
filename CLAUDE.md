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
the calendar, notification scheduling, the tray, the Markdown dialect, the
journal pane's states and shortcuts, the parked panel's drag and activate, and
the noise synthesis. Run it.

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

`LocalStore` (`app/lib/sync/local_store.dart`) owns eight tables: `workspaces`,
`parked_groups`, `tasks`, `attachments`, `side_thoughts`, `journal_entries`,
`calendars`, `calendar_events`, plus a key/value `settings` table used for UI
prefs (last workspace, nudge, sound volume, calendar mode/scope/hidden/block
target).

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

**On touch those views are a bottom bar instead** (`ui/view_bar.dart`), and the
workspace bar's ▾ is hidden — two doors to the same four views, one of them at
the far end of the phone from the hand, is one too many. `kBarViews` is the
order, and **`_swipeView` in `main.dart` reads that same list**, so the bar and
the swipe cannot disagree about what is next to what. The swipe is safe to claim
because the only other horizontal gesture in the list is the task `Draggable`,
which exists only when there is something beside the list to drop onto — a
window far wider than any phone. Note `_selectView` is a *destination* while the
▾ menu's entries are *toggles*: tapping Notes must land on Notes whatever was
showing, and a swipe that toggled would go backwards half the time.

Two things take the whole screen on touch and both are about what is
*incidentally* on display: `ThoughtSheet` (`ui/thought_sheet.dart`), because a
phone is held in front of people and the inline capture field left every task in
the workspace visible behind the keyboard; and an open journal entry, via
`_noteTakesScreen`, which hides the workspace bar, the view bar and the footer.
`JournalView` reports that through `onEntryOpen` rather than the shell inferring
it — `showJournal` says the pane is open, not which rung of its ladder you are
on. That callback is deferred to after the frame, because the shell reacts with
`setState` and doing that from inside another widget's build is a crash.

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
and v11 `notes` / `priority` lines in `attachments_test`, `calendar_test` and
`default_workspace_test`; the v13 `recur` on `calendar_events` is the first
such column on a table other than `tasks`, so `recurrence_test` and
`default_workspace_test` roll that one back too), and a hand-built one has to
contain every table a later step touches, which is why `journal_test` carries
`_v9Tasks` and `_v4Attachments` as scaffolding.

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
  - **One whole day already satisfies `spansDays`** (midnight to the next
    midnight is two calendar days), so it lands in the band with no separate
    rule. The grid still tests `allDay || spansDays`, because that is the
    question being asked and relying on the coincidence would be a trap for
    whoever changes `spansDays`.
  - **An all-day event does not inherit its calendar's lead time**
    (`notifyLead`). That rule is minutes before a start and an all-day start is
    midnight, so inheriting "an hour before" fires at 23:00 the night before
    for every birthday. A lead set on the event itself is still honoured -
    that is the only place someone can have meant it.
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
- Past `Layout.splitsCalendar` it replaces nothing: `_splitCalendar` puts the
  task pane (workspace bar, banner, add field, list) beside it. Both halves get
  their **own `LayoutScope`**, measured by a `LayoutBuilder` — the week's
  fallback and the year's column count must answer for the box the calendar
  actually got, not for the window. That split is also the only place
  `onPlanTask` is non-null, so the drop targets simply do not exist anywhere a
  task cannot be dragged from.
- **A click on a block reads it** (`showEventDetails`), and right-click /
  long-press is the actions menu (`_eventMenu`); `_editEvent` is the form that
  used to be what a click did. The long press is safe to take *because* the
  create-drag listener sits below the blocks in the grid's `Stack` — the same
  arrangement documented above is what makes both gestures possible on one
  widget.
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
- **The toolbar is two rows on touch, one everywhere else.** As a single Row it
  had to fit a back arrow, two steppers, the date, Today, the bolt, a three-way
  mode switch and a filter menu across 390pt — it "fitted" by giving the title
  whatever was left, which was six characters, so the one label saying *where
  you are* showed as "Au…". Splitting it puts where-you-are on one line and the
  controls on another and makes every target finger-sized out of the same
  change. `_IconBtn`, `_ModeSwitch` and `_FilterMenu` take optional sizes; null
  keeps the compact desktop shape.
- **A horizontal swipe moves through time** — next/previous week in the week
  view, day in the day view, year in the year view (`state.stepCalendar`), and
  unclamped, because time has no ends. It used to switch D/W/Y, which was the
  wrong axis: the mode is set once and read off the toolbar, while "what about
  next week" is asked twenty times in a sitting and meant reaching for the ‹ ›
  at the top of the screen each time. Safe to claim because the grid's own
  gestures are a vertical scroll and a *long-press*-then-drag to create —
  creating is split by input device precisely so a one-finger drag can still
  scroll, which leaves a plain horizontal fling belonging to nobody.
- **The date label is its own line on touch**, under the arrows rather than
  between them. Sharing a row with a back arrow, two steppers and Today left a
  day view's "Tuesday, 18 August 2026" a few characters wide; given the full
  width it fits at a *smaller* size than it was being clipped at.
- **Quick add holds blocks before writing them** (`AppState.pendingBlocks`).
  Tapping the grid with the bolt on places an adjustable hour; nothing reaches
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
- **The hour height is a value, not a constant** (`TimeGridView.hourHeight`),
  pinched on touch and stored device-locally in `settings`. Everything vertical
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
  vertical drag still scrolls and the ≡ handle still reorders.
- **A null `onDrop` makes the target its child and nothing more.** That is how a
  panel with no list beside it simply has no drop targets, rather than inert ones
  — the same shape as the calendar's `onPlanTask`.
- **The whole parked-group card is the target, collapsed or not**, and a drop
  *opens* the group. Aiming at a group's contents would leave an empty or closed
  shelf nothing to hit, and those are the ones something is most likely being put
  away into; opening it is the only visible confirmation the task landed, since
  otherwise a closed shelf just shows a bigger number.

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

- `TitleBar` is the drag handle, via `DragToMoveArea`. It must **not** wrap the
  buttons themselves or it swallows their clicks.
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
  builder is a callback. `SublistSheet` is built from `_sublist!`, and that goes
  null the instant it closes. Its `AnimationController` is built in `initState`,
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

**`Layout.touch` is the one axis that is not a size**, and it is separate
because the questions genuinely differ: every other getter asks *does it fit*,
this asks *can it be reached at all*. A 340px desktop window and a 340pt phone
lay out identically and still need different controls, because one has a hover
state and a 3px pointer and the other has neither. It exists because pretending
otherwise had already cost real function — every action on a task row was drawn
behind `visible: _hovered`, so on a phone reminders, parking, focus and delete
were not small, they were **absent**, and no width would ever have revealed
them. It is a field on `Layout` (set from `!isDesktop`, default false) rather
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
