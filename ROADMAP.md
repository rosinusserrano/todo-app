# Roadmap

What is agreed but not yet in `FEATURES.md`. An item leaves this file when it
ships: the description moves into the feature list and the changelog, the
reasoning moves into the comment above the code that needed it, and the line
here becomes one line under *Shipped*. Longer-term wishes with no design behind
them live in FEATURES.md's *Ideas / backlog* section instead — this file is for
work that is about to happen.

## In progress

### 0.18.0 — reminders that say when, and keep saying it

The two backlog items that now have a design behind them. They go together
because the second is the first plus a rule, and building the rule without
somewhere to type a date first would mean shipping a recurrence you can only
start at one of five preset times.

The other three backlog items stay in the backlog on purpose. A **light theme**
is not a small change: `T` is 19 `static const` tokens read from ~346 sites, so
a runtime theme means they stop being `const` — along with the widget
constructors that use them — and that sweep needs its own design before it
needs a release. **Syncing attachment bytes** is a whole second channel beside
the JSON sync, with its own queue, retry and progress; it wants a release to
itself, not a corner of this one. **Configurable shortcuts** are genuinely
small and can be picked up any time — `shortcuts.dart` already reports failed
registration, which is the hard half — they just have no bearing on these two.

- [ ] **Reminders at an arbitrary date and time.** The objection recorded in
      the backlog — "a Material date picker is about as wide as the whole
      widget" — is now obsolete, and the calendar is what killed it:
      `_MonthTile` in `ui/calendar/year_view.dart` already draws a full month
      grid, and the year view puts one to three of them side by side inside
      this window. So the picker is a month grid we already own.
      Lift `_MonthTile` into a shared widget rather than writing a second one,
      keeping its six-week padding (`_weekRows`) — two month grids that
      disagree about where a month starts is a bug nobody would look for.
      Reached from a "Pick a date and time…" item at the foot of
      `showReminderMenu`; the presets stay first, because they are still the
      right answer most of the time.
      It is a **sheet in the shell's `Stack`**, not a `showDialog` route — a
      barrier over the title bar leaves the window undraggable — so it needs
      the usual four edits: `_clearOverlays`, the Esc ladder, the paths that
      clear the content area, and `Layout` if it wants a threshold.
      **No schema change**: `remind_at` is already a UTC instant via
      `reminderStamp`, and an arbitrary one is the same column with a wider
      range of values. → `ui/reminder_menu.dart`, `ui/calendar/year_view.dart`,
      `main.dart`.

- [ ] **Recurring reminders** ("every weekday at 09:00"). Schema v12, and the
      three edits on both sides.
      A recurrence is a rule, so store the rule: one nullable `recur` column on
      `tasks`. `remind_at` keeps its exact present meaning — the next time this
      nags — so `ReminderService`, `describeReminder`, the overdue styling and
      `NotificationService` all go on reading one instant and need no changes.

      **Checking one off completes it and spawns the next occurrence as a new
      row.** This was the open question and it is settled: an occurrence is a
      todo in its own right (today's standup is not yesterday's), so History
      needs no changes at all — the completed row lands there by having a
      `completed_at` like every other finished task, and the new row carries
      the rule and the next instant. The alternative, re-arming the same row
      and logging completions separately, means a second table and a History
      that is a union of two sources; "what did I finish" would have two
      answers, which is the shape this codebase keeps refusing.

      **The new row's uuid must be derived, not generated** — from the series
      and the occurrence instant. Spawning is a write, so it syncs, and two
      devices that both see the completion will both spawn; generated ids make
      those two different rows that sync can only keep as siblings, which is
      exactly how one account ended up with seven "Tasks" workspaces (see
      `_foldSeededDefaults` and `Calendar.forWorkspace` — same rule, third
      instance). Derived, they are one row and the second spawn merges.

      **Compute the next instant from the completed row's `remind_at` and the
      rule, never from `now`**, for the same convergence reason and because
      completing Tuesday's 09:00 task at 14:00 must still schedule Wednesday
      09:00.

      Spawn on *completion*, not on fire: an unchecked recurring task then sits
      overdue as one row instead of piling up thirty copies of a standup nobody
      attended.

      A series needs its own id (`series_uuid`, or the rule travels with each
      row) so that "stop reminding me" can reach the future rather than just
      this occurrence. On mobile, `NotificationService` should hand the OS the
      next several occurrences — a suspended phone runs no timers and nothing
      is there to spawn the next row between fires. →
      `sync/local_store.dart`, `sync/models.dart`, `app_state.dart`,
      `notifications.dart`, `ui/reminder_menu.dart`, `server/db.js`.

## Shipped

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
