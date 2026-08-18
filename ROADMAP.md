# Roadmap

What is agreed but not yet in `FEATURES.md`. An item leaves this file when it
ships: the description moves into the feature list and the changelog, the
reasoning moves into the comment above the code that needed it, and the line
here becomes one line under *Shipped*. Longer-term wishes with no design behind
them live in FEATURES.md's *Ideas / backlog* section instead — this file is for
work that is about to happen.

## In progress

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

- [x] **The "Now" tile takes you to the block, workspace and all** — and offers
      *Sublist* instead of an empty session view when nothing is planned into
      the running block. → `main.dart` `_openSession` / `_openSublist`,
      `ui/sublist_sheet.dart`.
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
