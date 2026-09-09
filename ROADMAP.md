# Roadmap

What is agreed but not yet in `FEATURES.md`. An item leaves this file when it
ships: the description moves into the feature list and the changelog, the
reasoning moves into the comment above the code that needed it, and the line
here becomes one line under *Shipped*. Longer-term wishes with no design behind
them live in FEATURES.md's *Ideas / backlog* section instead — this file is for
work that is about to happen.

## In progress

### Six things asked for on 2026-09-09 — shipped as 0.28.0

Kept here for one release because the reasoning is the kind that gets lost;
the one-line record is under *Shipped*.

Four of them are small and are already in (26-29 in `TODO.md`); the reasoning is
recorded here because it is the kind that gets lost.

**Switching workspace should land on the list.** Every per-workspace view
already closed on a switch; the thought pile did not, on the stated grounds that
it is global and therefore not a fact about the workspace. True, and beside the
point: picking a workspace is asking *what is on this list*, and the one control
whose whole job is to show you a list was showing something else. Nothing is
lost by closing the panel, because the pile's count is on the footer and on the
bubble either way.

**A note on a phone was closing itself.** Not a journal bug at all - a
reconciliation one. Opening a note makes the shell hide the workspace bar, the
view bar and the footer in the same frame; that changes the content's *position*
in its column, Flutter matches unkeyed children by position, and the whole
subtree was rebuilt. `JournalView` keeps which rung of its ladder it is on in
its own State, so the rebuild put it back on the list one frame after it opened.
The fix is a key, and the general shape - `contentSlot` - is worth having
because the same thing would happen to any panel that ever takes the screen.

**Adding straight to a shelf.** The commonest thing anybody does with a backlog
is think of something that is explicitly not for today. Every existing way in
puts the task on the current list first and then takes it off again, which is
three steps to record that you are *not* doing something, and a flicker of the
task on a list nobody asked to put it on.

**A review has to make you read the tasks.** The review interval is the feature
that stops a shelf being a landfill, and it was enforced by a button under a
collapsed list - reachable without having looked at anything. So it enforced
nothing, and put a fresh timestamp on the shelf for doing it. A funnel is the
smallest honest version: one task at a time, four answers, and the clock only
restarts at the end. Leaving half way keeps the decisions and not the clock,
because those are two different facts.

**Thirty minutes of sound on the device.** Tiers 1 and 3 are already right -
noise is generated locally, and radio is a live stream that cannot be anything
but streamed. It is tier 2 that lags: every play is two archive.org lookups and
then an mp3 pulled over the wire, looped, for an hour. Keeping a **bout** - a
30-minute prefix of a recording, sized from the metadata the search already
returns - makes the second play of a preset instant and offline. It must not
cost the variety, which is the entire reason a preset is a *query* rather than a
fixed file, so the cache holds several bouts per preset, plays a random one, and
fills in the background rather than making anyone wait for a download.

**Recurring todos, and why they are two kinds and not one.** What exists today
is one behaviour: complete a task and its successor is laid down, dated by
calendar arithmetic from the *reminder*. That covers neither thing asked for.

  - *Rule-based creation.* "Send working hours for September to management",
    made on the last day of every month, whether or not August's was ever
    ticked. The existing rule spawns on completion, so a month you did not
    answer for is a month that never produces the next one.
  - *Interval from completion.* "Clean the kitchen" every two weeks **counted
    from when it was last done**, not from when it was due. Created 1 Jan,
    ticked 8 Jan, back on 22 Jan.

The design keeps one mechanism and gives it three pieces of state rather than
adding a table of rules:

  - **`recur_from`** says which instant the next occurrence is measured from -
    the schedule, or the completion. That is the whole of the second kind.
  - **`recur_lead`** says how long before its due time an occurrence is
    *created*, which is the "make it three days early with the real due date"
    half of the first kind - and, at zero, is what stops a monthly report
    appearing four weeks before it is due. Null is the legacy value: created the
    moment the previous one is ticked, which is what every existing recurring
    task means.
  - **`recur_text` / `recur_notes`** carry the template, so `$(month)` can be
    expanded against each occurrence's own due date and the *expanded* text is
    what lands in the row and therefore in History. Without them the first
    expansion would eat the variable.

The spawn itself becomes one function called from two places - completing a
task, and the reminder sweep - and it is safe to call from both because the
successor's uuid is already **derived** from the parent and the occurrence
instant. An occurrence that exists is not written again, on this device or any
other. That is the same property that made recurrence cheap in the first place,
used for a second purpose.

A rules *table* was the other option and was rejected: it would need a pointer
column anyway, and everything that already works - History, reminders,
notifications, the merge, the derived-uuid idempotency - would have had to learn
about a row that is not a task.

### Receiving a calendar invite from the share sheet

The reader and the import are built and shipped (see FEATURES.md): `sync/ics.dart`
parses what other apps produce, and **Calendar -> tune menu -> Import .ics...**
brings events in on every platform today. What is *not* built is the phone half
- being offered in another app's "add to calendar" share sheet - because it is
the one part that cannot be done in Dart:

- **Android.** An `<intent-filter>` on the main activity for `ACTION_VIEW` and
  `ACTION_SEND` with `text/calendar`, plus Kotlin to read the incoming
  `content://` URI and hand the bytes to Dart over a `MethodChannel`. Doable and
  testable on a device; roughly an afternoon.
- **iOS.** Needs `CFBundleDocumentTypes` for `com.apple.ical.ics` *and* a Share
  Extension target, which has to be created in Xcode - it is a second binary
  with its own bundle id and entitlements, not a file that can be written from
  a terminal.

Deliberately **not** half-done: registering the intent filters without the
native glue would put the app in the share sheet where it would then do
nothing, which is worse than not appearing at all.

The parse, the confirmation dialog and the write are already shared, so both
platforms are a second *way in* rather than a second implementation - each has
only to end in `parseIcs` + `showImportIcs`.

## Next

### Google Calendar, mirrored in

The week grid should show what is actually booked, not only what was planned
here. The .ics import already covers the one-off — "here is an invite, put it
in" — and this is the standing case, where the source keeps changing and
re-importing it by hand is the thing nobody does twice.

**Read-only, in one direction, for as long as that is enough.** Google's model
is richer than ours in every direction that matters (recurrence rules,
attendees, all-day, per-event reminders, timezones by name), so a two-way link
means resolving conflicts between two systems that disagree about what an event
even is. A mirror has one authority per row and cannot lose an edit, because
there are no local edits to lose.

Three steps, each of which is useful on its own and none of which is wasted if
the next never happens:

**Step 0 — subscribe to the private .ics address.** Every Google calendar has a
"Secret address in iCal format" under its settings: a URL that returns the whole
calendar as a file `sync/ics.dart` can already read. Subscribing to one is a
`calendars` row that carries a URL, a poll, and `parseIcs` — no OAuth, no
consent screen, no Google Cloud project, no verification, and it works against
anything that publishes an .ics (Outlook, Fastmail, a university timetable, a
football fixture list). It is worth building first even if the API link is
certain to follow, because it is a day's work against parts that exist and it
answers the question the API link is expensive to answer: *is a mirrored
calendar on this grid actually useful, or is it noise?* The cost is refresh
latency — Google regenerates that file lazily, on the order of hours — and no
way to write back.

**Step 1 — the real API, brokered by the sync server.** The device does not hold
the Google credential; the server does, one refresh token per user, and it
writes mirrored rows into the `calendars` / `calendar_events` tables every
device already pulls. That is the whole reason this belongs on the server: sync
is already a delivery mechanism to every device, so a server-side mirror needs
no new transport, no new merge and no new conflict rule on the client. The client
change is an entry in Settings that opens the consent URL and a line saying when
the mirror last ran. Doing it per-device instead would mean three refresh tokens,
three pollers, and three devices writing the same rows — which sync can only
merge as siblings unless the ids are derived anyway, and which triples the
consent problem for nothing.

**Step 2 — writing our blocks back**, into a Google calendar *we* created and
only ever into that one. Anything else means owning an edit war with whatever
made the event. Needs Google's event id and `etag` stored beside our row, and is
deliberately last.

What is already decided about the shape:

- **A mirrored calendar is read-only, and the schema has to say so.** A `source`
  column on `calendars` (null = ours, otherwise where it came from), and the grid
  must refuse drag-to-create, quick-add and delete on it. Without that a user
  drags out a block on a mirrored calendar, it saves locally, and the next pull
  silently removes it — the exact shape of bug this codebase keeps buying
  columns to avoid. This is the one prerequisite that cannot be deferred, and it
  is the usual three edits (`local_store.dart` `_create` *and* `_upgrade`, the
  model, `db.js` schema + `addColumn` + `TABLES`).
- **Ids are derived, not generated.** Third application of the rule after
  `_foldSeededDefaults` and `Calendar.forWorkspace`: uuid v5 over the Google
  calendar id plus the event id plus, for an expanded occurrence, its instance
  id. Re-linking an account after a purge then lands on the rows that are
  already there instead of duplicating a year of events, and a mirror that runs
  in two places converges instead of doubling.
- **Deletions arrive as tombstones already.** Google's incremental list returns
  cancelled events as `status: cancelled`, which is a `deleted_at` — the model
  needs nothing new to express a meeting that was called off.
- **Instances, not rules** (`singleEvents=true`), with a rolling horizon of
  about a year either side. `calendar_events` has no recurrence and does not
  need one for this; the cost is that the horizon has to move, which is a
  scheduled job's problem rather than a schema problem.
- **Quiet by default.** Mirrored events get `notify_minutes` left alone and
  their calendar's rule set to silent, because the phone that has Google
  Calendar installed is already going to notify for the same meeting, and two
  alerts for one event is worse than none. An event's own override still works
  if you want one of them to nag.
- **What has no column goes into the description**, which is Markdown, so a Meet
  link is a link: location, conferencing, attendees.
- **`syncToken` per linked calendar**, and a `410 GONE` means the token expired
  and the answer is a full re-list — the same "cursor went backwards, re-arm
  everything" shape the sync client already has for a rebuilt server.
- **Poll, don't subscribe.** Google's push channels want a public https endpoint
  (which exists, behind Caddy) but expire and have to be renewed, so they are an
  optimisation on a five-minute poll, not the first implementation.

Open, and worth answering before any of Step 1 is written:

- **What Google's consent policy currently costs a personal project.** Calendar
  scopes are *sensitive*, and an OAuth client left in "Testing" hands out refresh
  tokens with a short life — a mirror that silently stops after a week and needs
  a human to click through consent again is not a mirror. This is the single
  thing most likely to sink Step 1, it is a policy question rather than a code
  question, and it should be checked **before** anything is built. Step 0 exists
  partly because it is immune to it.
- Whether the mirror is per-user (server-side, as above) or per-workspace, and
  therefore whether a linked Google calendar can be *the* calendar of a
  workspace or is always a standalone one beside it. Standalone is the smaller
  answer and probably the right one: a workspace calendar takes its name and
  colour from its workspace, and a mirror wants Google's.
- All-day events. Nothing here has an all-day concept — the .ics importer
  already flattens one to a span — and Google produces them constantly. Either a
  `all_day` column (a fourth edit to the same three files) or accept
  00:00–24:00 blocks drawn in the multi-day band. The second is honest enough to
  ship and reversible.
- Whether this is wanted on the phone at all, which already has Google Calendar
  on it.

## Shipped

### 0.28.0 — todos that arrive on their own, and a shelf you have to read

The six-item batch above, all of it landed. What is worth keeping out of it:
recurrence stayed **one mechanism with three more pieces of state** rather than
becoming a table of rules — `recur_from` for which instant it is measured from,
`recur_lead` for when the next one is *written*, and a template pair so a
`$(month)` is not eaten by the first occurrence that renders it. The spawn is
one function called from a completion and from the clock, and it is safe from
both because an occurrence's uuid was already derived. A rules table would have
needed a pointer column anyway, and every part of the app that already works —
History, reminders, notifications, the merge — would have had to learn about a
row that is not a task.

The one thing that nearly went wrong: `recur_from` started as NOT NULL on both
sides, which would have made a push from any un-updated device a constraint
failure that rejected the whole sync. Nullable in the databases, non-null in the
model, null read as `schedule`. Same rule `review_every_days` has followed since
v3.



### 0.27.0 — one scale, and the colour turned down

Marco, 2026-09-07: the widget read as "too standard productivity app" and the
colour was too loud, but workspaces still have to be told apart by colour. Five
directions were drawn at true size and compared side by side - a Swiss hairline
ledger, a mono technical readout, a warm paper-and-serif, a Braun-style
instrument panel, and **Quiet**, which is this one: today's structure with a
real system put back under it. Quiet was the pick.

Worth writing down, because it is the thing the next design change has to
answer: Quiet fixes *loud*, not *standard*. Nothing about the shape of the app
changed. If the widget still reads as generic after living with it, the
cheapest step from here is the ledger's row treatment - drop the card fill,
separate rows with one full-bleed hairline - because every other token here
already lines up with it.

- [x] **One radius.** `T.radius` is 8 and is the only one; 14, 9, 8, 7, 6 and
      20 had no rule saying which belonged where. A thing that wants a
      different shape asks for a *shape* (`BoxShape.circle` on the tick box),
      not a fourth number.
- [x] **One spacing scale** (`T.s1`-`T.s5`, 4/8/12/16/24). Paddings were picked
      per widget - 6/7 on a row, 9/5/7/5 on a workspace pill, 8/4 in the title
      bar - and a 1px difference repeated down a column is exactly what makes a
      layout feel approximate. The window column is inset one step and a row's
      inside is one step, so a task's text sits two steps from the window edge
      and the add field's fill lands exactly over the rows' fills. They were 12
      and 10 before: misaligned by a pixel nobody could name.
- [x] **Four type sizes, two weights** (`T.fsBody` 13 / `T.fsLabel` 12 /
      `T.fsMeta` 11 / `T.fsMenu` 15; `w400` and `w500`). There were six sizes
      between 10.5 and 15 - 13 and 13.5 sat in the same window and only one of
      them can have been deliberate. Weight 600 is gone from the chrome.
      Two escapes, both stated rather than assumed: `T.wStrong` for *content*
      emphasis, because Markdown's `**bold**` has to look bold; and
      `T.fsGrid` (9.5) for text laid into the calendar, where the box is sized
      by duration and column count rather than by its contents.
- [x] **Colour stopped doing five jobs.** `danger` was destructive *and*
      overdue *and* flagged, which is most of why nothing read as a signal. It
      is now three tokens: `danger` for what cannot be undone, `warn` (warm
      amber) for attention that costs nothing - an overdue reminder, a sync
      that will retry - and `flagged` for the priority bar. `ok` exists too,
      because the settings sheet was carrying a raw `0xFF7EE3A1` that stayed
      the *old* mint through two palette changes.
- [x] **The workspace palette, at about 60% chroma**, same hues in the same
      order - a workspace is stored as an index, so nobody has to re-learn
      which one is theirs - and the window tint down from 16% to 6%. At 16 the
      tint was the loudest thing in the window and was repeating the coloured
      pill an inch above it.

### 0.26.0 — the task row gives its width back

Marco, 2026-09-03: the action bar should not be visible in the normal state, on
either platform — and on desktop it should not be *taking the space* either,
because in a narrow window the invisible bar was most of the row.

- [x] **The actions moved into an overlay** (`ui/task_actions.dart`), opened by
      the one gesture each pointer had spare: right-click with a mouse, a short
      tap on the text with a finger. The row is a tick box, a title and its
      marks. Two costs went away with it — the desktop icons that were hidden
      but still laid out (correct while they were on the row: revealing one
      must not reflow the text), and the phone's permanent second line under
      every task, which wrapped to a third on a task carrying everything.
- [x] **A left-click expands rather than editing**, because the pencil in the
      bar is now the way to the composer on both platforms and the click was
      free. Marco's call between four options.
- [x] **Expand is a real read view** (`ui/task_detail.dart`): Markdown rendered
      properly, and the state the row can only hint at spelled out in chips.
      Read-only on purpose — the composer is a form, and reading a checklist in
      a form is being one keystroke from editing it. In place under a pointer
      (the list scrolls past it); the whole content area on a phone, which the
      shell owns because a row inside a scrolling list cannot take it.
- [x] **Reordering per pointer**: the grip moved to the right and is drawn only
      for a mouse; a phone presses and holds the row. The grip on the left was
      indenting the title of every row in the list for a control touch cannot
      use at all.
- [x] What stays on the row is **state, not actions**. The bell, the paperclip
      and the planned mark were lit-up buttons before *because* they were state
      as much as controls; only that half is left, and it is not pressable.

### 0.25.0 — a night, a phone, and one menu that names what you are doing

Marco's list from a week of using the phone build, in his order.

- [x] **Block sublists removed** (`ui/sublist_sheet.dart`, `_openSublist`,
      `EventAction.plan`, `AppState.addTaskForEvent`). Shipped in 0.17.0 and
      annoying in practice: a second add field, reachable from three places,
      competing with the planning it sat next to. **Planning is untouched** —
      the block's tick list and dragging a row onto a block both still write
      `event_uuid`, which is all a sublist ever was. It is in FEATURES.md's
      backlog rather than deleted from the record, with the two things it would
      need to come back: somewhere on the block itself rather than a sheet, and
      an answer to what a todo written *into* a block is once the block is
      gone. The session view's empty state now says so and stops, which is the
      honest version of what the button was for.
- [x] **A block that crosses midnight stays in the grid.** `spansDays` asked
      whether the two ends fell on different dates, which promoted every night
      shift - and everything ending at 00:00 - into the all-day band, where it
      lost both the hour it started and the hour it ended. `spansWholeDay` asks
      whether a midnight-to-midnight day fits *inside* it, which is the case the
      band actually exists for. → `sync/models.dart`, `_timedByDay` and
      `EventBlock.continuesBefore/After` in `ui/calendar/time_grid.dart`, and a
      roll-forward on the end time in `ui/calendar/event_editor.dart`.
- [x] **The phone's side-thought bar is gone.** `ThoughtFooter.showPressure`
      alongside `showCaptureButton`; the count, the tint and the pulse moved
      onto `ThoughtBubble`, and a swipe up on it opens the pile. The escalation
      is shared through `ui/thought_pressure.dart` rather than copied. →
      `ui/thought_bubble.dart`, `ui/footer.dart`, `main.dart` `_footer`.
- [x] **The quick-action menu names the task in focus**, and the entry appends a
      line to its notes. Dynamic shortcut items are supported on both platforms
      and survive the app being killed, which is what forced the two rules
      worth keeping: re-read the task, and *append* rather than save. →
      `quick_actions.dart`, `AppState.appendToNotes`, `main.dart`
      `_noteOnActiveTask`, `ui/thought_sheet.dart` (three strings, same pane).
- [x] **"Add workspace…" works from the ▾ menu.** It was valued `null`, and
      `PopupMenuButton` reads a null result as a dismissal and never calls
      `onSelected` - so the entry could be pressed all day and report nothing.
      A named sentinel instead. Only ever broken on the narrow layout, since
      the rail's Add is an ordinary button. → `ui/workspace_bar.dart`.
- [x] **Ctrl+wheel zooms the timeline.** The pinch has been there since 0.24.0
      and a mouse had no way to ask. The listener has to sit *inside* the scroll
      view or the wheel is resolved by the scrollable first. →
      `ui/calendar/time_grid.dart`, `ui/calendar/calendar_view.dart`.

### 0.24.1 — a version handshake between app and server

Built; see FEATURES.md for what it does and CLAUDE.md for how it works. The
design as agreed is below, and the build changed nothing about it.

- [x] A **protocol number** rather than a table of app↔server versions, moved
      only when the wire changes — a new optional column is not that.
- [x] Two numbers per end (`PROTOCOL`/`MIN_CLIENT`, `kSyncProtocol`/
      `kMinServerProtocol`), because either side can be the old one and the two
      cases are different sentences.
- [x] **Absence means 1**, which is what kept this from being a flag day.
- [x] Asked on `/api/health` before anything is exchanged, repeated on
      `/api/me`; unreachable is not incompatible.
- [x] A mismatch blocks the sync and says which machine to fix; the local
      database is untouched and the queue keeps filling.

### 0.18.0 — reminders that say when, and keep saying it

Both built; see FEATURES.md for what they do.

- [x] **Reminders at an arbitrary date and time.** `MonthGrid` lifted out of the
      year view so the picker and the calendar cannot disagree about where a
      month starts. → `ui/month_grid.dart`, `ui/reminder_picker.dart`.
      Shipped as a **dialog, not the sheet this file first specified**: the
      picker opens from inside the composer, which is itself a dialog, and a
      sheet in the shell's `Stack` is drawn behind a dialog's barrier.
- [x] **Recurring reminders**, schema v12. Completing one spawns the next
      occurrence as a new row with a derived uuid. → `Recur` and
      `Task.nextOccurrence` in `sync/models.dart`, `AppState.completeTask`.
      Two things the plan here got wrong and the build corrected: no
      `series_uuid` is needed (deriving the child from its parent and the
      occurrence instant is already stable across devices, and with one
      occurrence live at a time "stop repeating" only has to reach the row in
      front of you), and `NotificationService` needed **no** change —
      pre-scheduling several occurrences was a consequence of the advance-on-fire
      model this file rejected, and under spawn-on-completion there is only ever
      one armed instant to hand the OS.

### 0.17.0 — the list and the calendar, pointed at each other

All six built; see FEATURES.md for what they do and the changelog for the shape
of the release.

- [x] **The "Now" tile takes you to the block, workspace and all.** →
      `main.dart` `_openSession`. It also offered *Sublist* instead of an empty
      session view; **that half was removed in 0.25.0** — see *Shipped*.
- [x] **Space between the workspace bar and the tile** at phone width. The gap
      belongs to the banner, not the bar: the bar is drawn on every screen and
      the tile is not. → `main.dart` `_sessionBanner`.
- [x] **Click an event for details, right-click / long-press for actions.** →
      `ui/calendar/event_details.dart`, `main.dart` `_openEvent` / `_eventMenu`,
      `EventMenuArea` in `ui/calendar/time_grid.dart`.
- [x] **Ctrl+D opens the full task composer**, landing in the notes box. Needed
      a `notes` column, hence schema v11 and the server's three edits. →
      `ui/task_composer.dart`, `AppState.saveTaskDetails`.
- [x] **Calendar and tasks side by side, dragging between them.** A size, not a
      mode — `Layout.splitsCalendar`, `main.dart` `_splitCalendar`,
      `TaskDropTarget` in `ui/calendar/time_grid.dart`.
- [x] **High-priority tasks** — a red bar down the leading edge plus a red
      border, in the one channel the overdue and focus states do not already
      use, and no reordering. Shares the v11 migration with `notes`. →
      `Task.priority`, `ui/task_row.dart`.
