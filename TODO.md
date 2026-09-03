# TODO — the running work order

What is being worked on **now**, and what comes **next**, in the order agreed
with Marco. This file exists so that a session which ends in the middle of the
list can be picked up from this file alone: each step carries enough detail to
be started cold.

Rules for keeping it honest:

- **Ordered.** The first unchecked step is the one being worked on.
- `[ ]` not started · `[~]` in progress · `[x]` done.
- A step is only `[x]` when it is **committed** — analyze clean, tests green,
  `FEATURES.md` updated if behaviour changed.
- Finished blocks move to *Done* at the bottom with their commit subject, so the
  live part of the file stays short.
- Design reasoning does **not** live here. It goes in `ROADMAP.md` before the
  work, and in a comment above the code after it. This file is only the order
  and the steps.

---

## Now

**Nothing.** Step 24 landed as 0.26.0; steps 18-23 as 0.25.0. Everything on
this list is done; the design that produced it has moved to `ROADMAP.md`'s
*Shipped*.

**Committed, pushed and installed on Windows** (2026-09-03, `52963f8`).
**Not on the phone yet**: 0.25.0's three mobile items (19, 20, 21) and the
touch half of 24 can only really be judged there, since the whole of 24 is
which gesture does what.

---

## Done — 0.26.0, the task row

Agreed 2026-09-03. One rework, both platforms. `flutter analyze` clean,
`flutter test` 498 passed / 6 skipped (the integration file, correctly gated
behind `--dart-define=SYNC_URL`). Nothing here touches the server or the wire.

### 24. The actions come off the row  `[x]`

"I don't want it visible in the normal state." On desktop it should not take up
space either - in a narrow window the invisible bar was most of the row's
width. On mobile it should pop up on a short tap on the text.

- [x] `ui/task_actions.dart` - `TaskAction`, `TaskActionItem`,
      `showTaskActions`, `taskActionAnchor`. A floating icon bar, not a menu of
      labelled rows: same glyphs, same order, so the muscle memory built on the
      old bar still points at the right thing.
- [x] The anchor is a rect **in the overlay's space**. `UiScale` is above the
      `Navigator`, so `localToGlobal` with no ancestor reports scaled screen
      pixels and the bar would open a fifth of the way down a phone.
- [x] `TaskRow`: `_IconAction`, `_TouchAction` and `_TouchActions` deleted.
      What is left inline is `_StateMarks` - the bell, the paperclip, the
      planned mark - which are **not pressable**.
- [x] Right-click opens the bar under a pointer (`onSecondaryTapUp`, opaque, so
      the blank space right of a short title is part of the target); a tap on
      the text opens it on touch.
- [x] A left-click on the title expands instead of opening the composer.
      Editing is the pencil in the bar on both, which is what freed the click.
- [x] `ui/task_detail.dart` - `TaskDetail` (chips + rendered Markdown, read
      only) and `TaskDetailScreen` (the same with a header and a scroll).
- [x] Expansion is two shapes of one action: in place under a pointer, the
      whole content area on a phone via `TaskRow.onExpand` + the shell's
      `_expandedTaskUuid` / `_taskTakesScreen` / `_takesScreen`. Guarded
      structurally, not by every path that opens another view.
- [x] Esc collapses it, alongside the rest of the ladder.
- [x] Reordering: `dragHandle` on the **right** and pointer-only;
      `ReorderableDelayedDragStartListener` around the whole row on touch.
- [x] `test/touch_task_row_test.dart` rewritten around the new shape (15
      tests); `widget_test.dart`'s flagged-row test now asserts the bar's
      glyph and the row's red bar rather than an `AnimatedOpacity` that no
      longer exists.
- [x] `FEATURES.md` (Tasks, Attachments, Parked, Reminders, Calendar, plus a
      0.26.0 changelog entry), `CLAUDE.md` (*The task row, and where its actions
      went*), `ROADMAP.md`, and `pubspec.yaml` to 0.26.0+13.

---

## Done — 0.25.0, Marco's list from a week on the phone

Agreed 2026-08-24, in his order. Checks were run over the batch rather than per
step: `flutter analyze` clean, `flutter test` 492 passed / 6 skipped (the
integration file, correctly gated behind `--dart-define=SYNC_URL`),
`node --test server/` untouched by any of it and green.

### 18. Remove block sublists  `[x]`

"It needs more thought and is rather annoying." Delete the feature, keep the
record.

- [x] `ui/sublist_sheet.dart` deleted, with `_openSublist` / `_loadSublist` /
      `_closeSublist` / `_dropSublistIfGone`, the sheet in the shell's `Stack`,
      its rung on the Esc ladder and in `_clearOverlays`, and every path that
      had to close it on the way past.
- [x] `EventAction.plan` and its two ways in (the details card's *Todos*, the
      context menu's *Todos…*), the "Now" tile's `_SublistButton`, and
      `SessionView.onCreateSublist`.
- [x] `AppState.addTaskForEvent`. `plannableTasks` and `tasksForEvent` stay -
      the editor's tick list is planning, which is not what was removed.
- [x] The empty session block says "Nothing planned into this block. Plan todos
      into it from the calendar." and stops there, rather than offering a
      button. `_openSession` therefore always opens the view: a tile that looks
      pressable has to be pressable.
- [x] FEATURES.md: bullet out of *Calendar*, entry into *Ideas / backlog* with
      what it would need to come back. ROADMAP's 0.17.0 line amended rather
      than rewritten.

### 19. A block that crosses midnight is not a multi-day event  `[x]`

Reported: an entry ending at 00:00 gets promoted to the all-day band. 22:00-04:00
has to be possible and has to be drawn where it happens.

- [x] `CalendarEvent.spansDays` → `spansWholeDay`: is there a whole
      midnight-to-midnight day *inside* this, rather than do the two ends fall
      on different dates. Calendar arithmetic, not `Duration(days: 1)`.
- [x] `_timedByDay` puts an event in **every** column it overlaps instead of
      breaking at the first; `_positionedEvents` already clamped to the day, so
      the clipping was free. `EventBlock.continuesBefore` / `continuesAfter`
      square off the cut end.
- [x] The editor rolls an end time that is not after the start to the next day,
      so 22:00-04:00 is two taps.
- [x] `test/overnight_event_test.dart` - two columns for a night, one for a
      block ending at midnight, none for a block with a day inside it. The two
      `spansDays` assertions in `calendar_test` / `all_day_test` rewritten.

### 20. The side-thought bar off the phone  `[x]`

"I don't want to have this bar in mobile. Rather make the bubble flash and make
sliding it up open the thoughts view."

- [x] `ThoughtFooter.showPressure` beside `showCaptureButton`; with both false
      the bar takes no height at any pile size. Kept in the tree for
      `openAndFocus` and the close guard's refusal, neither of which a phone
      reaches.
- [x] `ui/thought_pressure.dart` (`ThoughtPulse`) - the escalation, owned by
      both controls rather than copied into the second one.
- [x] `ThoughtBubble` gains the count on its shoulder, the warm-to-alarm tint,
      the pulse, and a vertical drag that lifts it and toggles the pile on
      distance or velocity.
- [x] `test/thought_bubble_test.dart` extended: the count, the swipe, a nudge
      that does not commit, and that a tap still captures.

### 21. A quick action for the task you are on  `[x]`

Asked as a question - "is it possible to make iOS home screen quick actions
dynamic?" - and it is: `setShortcutItems` can be called at any time and both
platforms keep the list across launches. iOS shows four at most.

- [x] `AppQuickActions.setActiveTask(title)`, re-registering only when the
      title moves; driven from `_onState`, since a task can leave focus by
      being completed, deleted, parked or merged away.
- [x] `AppState.appendToNotes` - re-reads the row, appends a line, moves
      `focusTask` with it. The menu outlives the process, so the press can
      arrive long after the copy the shell is holding went stale.
- [x] The pane is `ThoughtSheet` with a glyph, a title and a hint passed in.
      Same problem, same widget.
- [x] A stale entry falls back to the add field rather than doing nothing.
- [x] `test/active_task_note_test.dart`.

### 22. "Add workspace…" from the ▾ menu  `[x]`

- [x] It was `value: null`, and `PopupMenuButton` treats a null result as a
      dismissal - `onSelected` is never called for one. A named sentinel and an
      `Object`-typed menu. Broken only on the narrow layout; the rail's Add is
      an ordinary button.

### 23. Ctrl+wheel zooms the calendar's timeline  `[x]`

- [x] A `Listener` **inside** `SingleChildScrollView`, registering with
      `pointerSignalResolver` - dispatch runs deepest-first and the first
      registration wins, so wrapped around the scroll view it would lose the
      wheel and the day would zoom *and* scroll.
- [x] A ratio per notch about the pointer, `onZoom` passed unconditionally
      rather than on `layout.touch`.
- [x] `test/calendar_zoom_test.dart` - it zooms with Ctrl, and a plain wheel
      still scrolls.

---

## Older

One thing step 17's handshake found while it was being built, and could not fix
from here: the fake servers in the test suite are stand-ins for a real one, so they
have to answer `/api/health` now. `server_swap_test` was taught to;
`change_stream_test` never talks to `SyncService`, so it did not need it. A new
fake server that omits the route will hang for the client timeout rather than
fail cleanly.

### 17. A version handshake between app and server  `[x]` — see *Done*

Agreed 2026-08-19. The 0.24.0 deploy is the worked example: the app wrote
`recur` and `all_day`, the server had neither column, and the only symptom was
those fields arriving null on the other device. Nothing said anything.

A **protocol number**, not a table of app↔server versions — see ROADMAP for why
the table is the wrong shape. Bumped only when the wire changes, which a new
optional column is not.

- [x] `server/protocol.js`: `PROTOCOL` and `MIN_CLIENT`, both 1 today, with the
      rule for bumping them written above the constants rather than in a commit
      message nobody will find.
- [x] Serve them on **`/api/health`** (unauthenticated — the setup screen has to
      be able to say "too old" before a token exists) and repeat them on
      `/api/me` so the sync loop sees them without a second request.
- [x] `app/lib/sync/protocol.dart`: `kSyncProtocol`, `kMinServerProtocol`,
      `ServerProtocol.parse`, and the comparison. **Absent fields mean 1** — a
      server that predates this is protocol 1 by definition, and that is what
      stops this being a flag day.
- [x] Two directions, two sentences: `client < server.minClient` is *update the
      app*, `server.protocol < client.minServer` is *update the server*. One
      message for both sends the user to the wrong machine half the time.
- [x] `SyncService`: check before the first sync of a configuration, not after —
      `whoAmI` runs on the back of a sync that already worked, which is too late
      to gate one. Re-check while incompatible (it costs the poll it replaces,
      and resuming the moment the server is updated is the point); skip it once
      it has passed.
- [x] New `SyncStatus.outdated`, **not** `blocked`: that one says "check the
      address and token", which is the wrong machine and the wrong afternoon.
      Update `describe()` and `_syncColor()` with it.
- [x] The alert screen: a sheet in the shell's `Stack` (never a route — a
      barrier over the title bar leaves the window undraggable), opened once per
      run when the mismatch is first seen, naming both numbers and saying the
      local database is fine. Closable; the red sync icon and the settings line
      are what remain afterwards. Add it to `_clearOverlays` and the Esc ladder.
- [x] Tests both sides — `node --test server/` for the fields, and Dart for the
      comparison, the absent-field default, and that an incompatible server
      stops the sync rather than running it.
- [x] `FEATURES.md` + changelog, and move the ROADMAP entry to *Shipped*.

One thing carried over, not blocking: `src-tauri/target`, `src-tauri/gen` and
`dist/` are still on disk (6.5 GB of Rust build output from the deleted app).
Gitignored, safe to `rm -rf` whenever Marco says so.

### 0. Commit the 0.23.1 batch  `[x]`

22 modified files, unreleased: the timezone-offset fix, the phone action bar
wrap, the quick-add commit rule, the quick-add drag fixes, the Android build
repair, the change-stream and date-picker fixes. Checks already run and green —
`flutter analyze` clean, `flutter test` 382 passed / 6 skipped (integration,
correctly gated behind `--dart-define=SYNC_URL`), `node --test server/` 91/91.

- [x] Commit the code + `FEATURES.md` + `CLAUDE.md` as the 0.23.1 batch.
- [x] Commit the planning docs separately: `ROADMAP.md` (Google Calendar),
      `TODO.md`, the `CLAUDE.md` pointer to it.

---

## Next

### 1. CI builds more than iOS  `[x]`

`.github/workflows/ios.yml` is the only workflow, so Android was broken outright
for an unknown length of time and nothing noticed (see the 0.23.1 changelog),
and the server's own tests have never run in CI at all.

- [x] Split the checks out of the iOS job into a `checks` job that runs once:
      `flutter analyze`, `flutter test`, and `node --test server/`.
- [x] `android` job — ubuntu-latest, JDK 17, `flutter build apk --release`
      (unsigned is fine; it is the *compile* that regressed, not the signing),
      artifact uploaded like the .ipa.
- [x] `windows` job — windows-latest, `flutter build windows`. This is the
      primary platform and has never been built by CI.
- [x] Keep the iOS job's unsigned-.ipa output and its comment block intact.
- [x] Push the branch and watch the run go green before calling it done.
      Done 2026-08-19: the workflow only fires on `main` (or a PR into it), so
      pushing the branch alone did nothing — the merge is what ran it. All four
      jobs green in 7m36s, run `32239641231`, Android included.

### 2. Recurring calendar events  `[x]`

Tasks repeat (`Recur`, v12); events do not. The .ics importer therefore drops
every RRULE and says so, and a weekly stand-up has to be laid out by hand.

- [x] Schema **v13**: `recur` TEXT NULL on `calendar_events`. The usual three
      edits — `local_store.dart` `_create` *and* `_upgrade`, the model, and
      `db.js` (schema, `addColumn`, `TABLES`). Reuse `Recur` from
      `sync/models.dart` rather than inventing a second rule format.
- [x] Expansion at **read** time, in Dart, not in SQL: `eventsBetween` keeps its
      current query for one-off rows, and recurring rows (few, so load them all)
      are expanded into the window. Occurrence uuids are **derived** — v5 over
      the series uuid and the occurrence instant — same rule as
      `Task.nextOccurrence`.
- [x] `Recur.next` is calendar arithmetic in local time already; reuse it so a
      09:00 block stays 09:00 across a DST boundary.
- [x] **v1 has no per-occurrence edit.** Editing or deleting a recurring event
      is the series. "Only this one" needs an exception list and is a second
      step, deliberately deferred — say so in the UI rather than silently
      editing the series.
- [x] Planning a task into a recurring block attaches to the **series**;
      `refreshSessions` must match a task whose `event_uuid` is the series *or*
      the occurrence, or a stand-up's todos vanish the week after.
- [x] Notifications: only the next occurrence is ever armed. `reschedule` still
      rewrites everything in one call.
- [x] Editor UI: the same repeat control the reminder picker uses.
- [x] Payoff: `sync/ics.dart` can then import the RRULEs it understands
      (DAILY / WEEKLY / MONTHLY, no COUNT/UNTIL gymnastics) instead of importing
      one occurrence and apologising. Keep the apology for the rest.
- [x] Tests: expansion across a month boundary and a DST boundary, derived-uuid
      stability, and the migration fixtures (`attachments_test`,
      `calendar_test`, `default_workspace_test`, `journal_test` scaffolding).
- [x] `FEATURES.md`: calendar section + changelog.

Two things this plan had wrong and the build corrected:

- **Occurrence uuids are not derived.** Derivation exists so two devices agree
  on a row they both *write*, and an occurrence is never written; it keeps the
  series' uuid instead, which is what makes attachments, planned todos and the
  task counts work with no special case. `instanceKey` tells two occurrences
  apart.
- **`Recur.next` was not enough.** Walking occurrence to occurrence clamps per
  step, so a monthly block on the 31st meets one February and becomes the 28th
  for ever. Expansion counts from the anchor through a new `Recur.nth`; tasks
  still use `next`, because a completed task has no anchor left.

### 3. All-day events  `[x]`

Nothing here has an all-day concept. The .ics reader already *parses* one
(`IcsEvent.allDay`) and then flattens it to a span, and Google produces them
constantly — so this is also a prerequisite for the calendar mirror.

- [x] Schema **v14**: `all_day` INTEGER NOT NULL DEFAULT 0 on `calendar_events`
      (NOT NULL with a default that is what every existing row means, so there
      is no third state). Three edits again.
- [x] Rendering: an all-day event belongs in the **spanning band**, not in the
      hour grid, whether it covers one day or five. `spansDays` stays what it
      is; the band's membership test becomes `allDay || spansDays`.
- [x] Editor: a toggle that hides the time pickers and keeps the dates.
- [x] Notification lead is measured from the **start of the day**, and an
      all-day event is silent unless it says otherwise — a 60-minute lead
      inherited from its calendar would otherwise fire at 23:00 the night
      before, which is not what that rule meant.
- [x] `parseIcs` stops flattening: `allDay` goes straight onto the row, and the
      exclusive DTEND that .ics uses keeps working.
- [x] Tests + `FEATURES.md`.

One correction to the plan: the band's membership test did not need changing
for the *single*-day case after all - midnight to the next midnight is already
two calendar days, so `spansDays` is true. It tests `allDay || spansDays`
anyway, because that is the question being asked and leaning on the coincidence
would trap whoever next edits `spansDays`.

### 4. An attachment whose bytes never arrive  `[x]`

A row syncs, the file does not, and "not on this device" is currently a dead
end: there is no way to resolve it short of the byte-sync feature that is still
in the backlog.

- [x] "Locate file…" on a missing attachment: pick the file, hash it, and if the
      SHA-256 matches the row's digest, store it — the row lights up here and
      the state clears. Content addressing is what makes this safe; the digest
      is the proof it is the same file.
- [x] A non-matching file is offered as a **new** attachment instead of
      silently replacing, since the digest says it is a different file.
- [x] Say something useful in the empty state — the file name and its size, both
      of which the row already carries. (Already did: the sheet has shown both
      since the feature landed. Nothing to change.)
- [x] Not byte sync. That stays in `FEATURES.md`'s backlog; this is the manual
      path that makes the state recoverable in the meantime.
- [x] Tests + `FEATURES.md`.

### 5. Throw away the dead Tauri build  `[x]`

`src/`, `src-tauri/`, `index.html`, `vite.config.ts`, `tsconfig.json` — the
original TypeScript app, superseded in 0.7.0 and untouched since.

- [x] Confirm nothing live references them: `legacy_import.dart` reads the old
      **database file** at its install path, not this source tree, and the
      server has no relationship with them at all.
- [x] Tag the last commit that contains them (`legacy-tauri`) and say so in the
      commit message. Deleting history is not the point; keeping a museum in the
      working tree is what stops.
- [x] `package.json`: keep the server scripts (`server`, `token`) and drop the
      vite/tauri devDependencies and scripts. `npm run server` must still work
      afterwards — check it, do not assume.
- [x] Update the "Where the code lives" table in `CLAUDE.md`, the memory note
      that says never to edit them, and any README references.

Left on disk deliberately, because it is untracked build output and 6.5 GB of
it is not mine to delete: `src-tauri/target`, `src-tauri/gen` and `dist/`.
`rm -rf src-tauri dist` when Marco says so.

### 6. Commit  `[x]`

Steps 1–5, each as its own commit as it lands rather than one lump at the end.

- [x] 1 CI, 2 recurring events, 3 all-day, 4 locate, 5 the deletion.
- [x] Bump `app/pubspec.yaml` to 0.24.0 (the changelog entry is already written
      under that number; `package.json` is already there).

---

## Then — mobile and the calendar

Marco's list, in his order. Several of these may already be partly fixed by the
0.23.1 batch that had not been installed on the phone when they were reported
(the quick-add drag arithmetic and the quick-add commit rule in particular) —
**reproduce each on a build of current `main` before changing anything**, and
say so if a report no longer reproduces.

### 7. A horizontal swipe moves through time, not through modes  `[x]`

Today `_stepMode` maps a swipe to D/W/Y. It should move the **period**: next /
previous week in week view, day in day view, year in year view. D/W/Y stays on
the toolbar, which is where it is visible anyway.

- [x] Repoint the swipe at the existing step-forward / step-back path.
- [x] Clamp nothing — time has no ends.
- [x] `CLAUDE.md` documents the old behaviour and its justification; rewrite
      that paragraph rather than leaving it lying.

### 8. The date label gets its own line  `[x]`

In day and week view the month and date are cut off. Put the label **below** the
row with the arrows, in a smaller font, so the arrows keep their finger-sized
targets and the label gets the full width.

### 9. The event editor matches every other editor  `[x]`

Full width, against the bottom edge on a phone, drawn from `T.*` — the same
treatment the task composer got in 0.22.0, which stopped it looking like a
different application. No stock Material card.

Done by **extracting** the composer's panel into `ui/form_sheet.dart` rather
than copying it, since step 11 wanted the same thing: `showFormSheet` +
`FormSheet`, now used by all three forms. Two bugs came out of it that were not
on the list — the details card's "white rectangle" (step 11) turned out to be
Material's `OverflowBar` claiming the height, and the event form's date/time row
had been overflowing in a 340px window behind a dialog that clipped it.

### 10. Quick add: pick the block up, then drop it  `[x]`

- [x] The redesign: a long press **lifts** the block off the grid (a
      `LongPressDraggable`, so it follows the finger as a thing being carried),
      and it lands where it is dropped — on whatever day is under it, which the
      old delta-based version could never do.
- [x] **Edge zones** while dragging (`kEdgeZone`): holding a lifted block
      against the left or right edge steps the grid, immediately and then on a
      timer.
- [x] The resize grip and tap-to-remove are unchanged and still pinned.
- [x] `test/quick_add_drag_test.dart` — where a block lands, that straight down
      keeps its day, that the edges step and then stop, and that a tap still
      takes a block back.

The test found the one thing this design gets wrong by default: a block in the
first column starts its own drag *inside* the left edge zone, so picking Monday
up to move it two hours down stepped back a week before the finger moved. The
zones now arm only after the block has been somewhere that is not an edge.

### 11. Opening an event shows a full-width card, not a white rectangle  `[x]`

Reported: title, delete button, then a large empty white rectangle running to
the bottom. Reproduce, find what is claiming that space (a description box with
no intrinsic height is the first suspect), and make the card full width like the
editor in step 9.

### 12. Pinch to zoom the hour height  `[x]`

Day and week views: a pinch changes how tall an hour is drawn, clamped between
`kHourHeightMin` and `kHourHeightMax` and remembered in `settings` like the
other calendar prefs — device-local, because how far you are zoomed in is about
the screen in front of you.

The coexistence problem was the whole of it, and the answer is that the pinch is
a **`Listener`, not a `GestureDetector`**: a `ScaleGestureRecognizer` enters the
arena against the scroll view and wins it on a single finger, which would stop
the day scrolling. A Listener never competes for anything, so one finger still
means scroll and two mean zoom. The pinched instant is held still by
re-anchoring the scroll offset after the frame that draws the new height.

### 13. Quick-add blocks that vanish  `[x]` — withdrawn, and one real gap behind it

**Not a bug.** Marco: "calendar entries are not disappearing; I simply had to
scroll up." The blocks were where they were placed, above the scroll position.

There *was* a real hole next to it, found while doing step 7 and fixed there:
`commitPendingBlocks` ran from the calendar view's swipe handler, so *swiping*
to another mode wrote the pending blocks while *tapping* D/W/Y did not - and
step 7 was about to delete that swipe. The commit now lives on
`AppState.setCalendarMode`, next to the one on `setTimeBlockCalendar`, where no
caller can miss it. `test/quick_add_test.dart` pins both that and the fact that
moving through *time* keeps blocks pending, since looking at next week is not
leaving the sitting.

### 14. Side thoughts as a bubble  `[x]`

- [x] On mobile, move the side-thought entry point to a floating bubble sitting
      above the Tasks / Notes / Parked bar — the shape every chat widget on the
      web uses, and reachable with a thumb.
- [x] The open panel currently covers the **title bar**, so its close button sits
      under the concentration-sound button and you press the wrong one. The
      panel must sit below `TitleBar.height` like every other sheet, or own a
      close control that cannot collide.

Two things the build added to the plan. **Moving** the entry point means the
footer gives its own 💭 up, or the same control is in two places — which is a
third flag (`ThoughtFooter.showCaptureButton`), deliberately separate from
`onCapture`: that one says capture opens the *pane*, which is true of any touch
device, while the bubble is only drawn where the view bar is. And what the
footer has left once its button is gone is the pressure meter, so with the pile
empty it now takes no height at all rather than reserving a strip at the bottom
of a phone.

### 15. The calendar gets its own colour  `[x]`

It is not a view of the workspace you came from and should not be tinted like
one — it can show every workspace at once. Neutral chrome: greyish in dark mode,
eggshell in light. **Note the light theme does not exist yet** (it is in
`FEATURES.md`'s backlog), so define both tokens and use the dark one now.
Events keep their own calendar's colour — that is the point of the week view.

Two decisions the plan left open. The tint drops **whenever the calendar is
open** (`_calendarChrome` = `showCalendar`). It was `&& !splitsCalendar` for one
commit, on the theory that half a split window really is that workspace's list -
which was wrong in the way that matters: the widget is run at about 1140x670 and
the split starts at 813x400, so the exception was the only case that ever ran
and the change could not be seen at all. And the **title bar's accent goes with
it**, to `T.accent`
rather than to the neutral — the neutral is within a few points of `T.muted`,
so a lit control tinted with it would stop reading as lit, and leaving it the
workspace colour would have left the one coloured thing on screen belonging to
a workspace you cannot see.

### 16. Commit  `[x]`

- [x] 14 the thought bubble, 15 the calendar's own colour — each its own commit
      as it landed (`354bbc9`, `dfe4c7f`). `flutter analyze` clean,
      `flutter test` 457 passed / 6 skipped, `node --test server/` 91/91.
- [x] **Push `feature/ci-calendar-cleanup`** — done, along with `main`, the
      `legacy-tauri` tag, and the server deploy that had been waiting on it.

---

## Done

- **17** Agree on a version before exchanging anything (0.24.1) — protocol
  number on both ends, checked on `/api/health` before the first row moves,
  `SyncStatus.outdated` and an alert that names which machine is behind.
- **16** Both landed as their own commits. Branch and `main` pushed, the
  `legacy-tauri` tag with them, the server updated to `5f27a04` (it had been
  three server-affecting commits behind, missing the offset-aware compare and
  both calendar columns), and the build installed on the laptop.
- **15** Give the calendar its own colour instead of the workspace's.
  (`dfe4c7f`)
- **14** Put the side-thought button where the thumb is, and the pane where it
  cannot be pressed by mistake. (`354bbc9`)
- **7-9, 11** Put the calendar's forms on the app's own panel, and the swipe on
  the right axis. (`6015b9d`)
- **0** Release 0.23.1: an edit no longer loses to an older one, and a phone can
  reach delete. (`5a9eace`, plus `30792a2` for the planning docs.)
- **1** Build every platform in CI, not just the one that could not regress
  quietly. (`6036c0c`) — **proven** 2026-08-19: four jobs, all green, on the
  first run.
- **2** Let a block of time repeat, as one row rather than fifty-two.
  (`b69cf4e`, schema v13)
- **3** Let an event be a whole day, and stop flattening the ones that arrive as
  days. (`5f932d7`, schema v14)
- **4** Give "not on this device" a way out that does not need blob sync.
  (`65d2f6b`)
- **5** Delete the Tauri build, three years after it stopped being the app.
  (`be311fd`, tagged `legacy-tauri`)
- **6** Version bumped to 0.24.0.
