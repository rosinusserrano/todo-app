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
      `tasks`, with **`remind_at` keeping its exact present meaning — the next
      time this nags.** That is what makes the change small: `ReminderService`,
      `describeReminder`, the overdue styling and `NotificationService` all go
      on reading one instant and need no changes. The only new behaviour is
      advancing `remind_at` when it fires. The alternative — generating a row
      per occurrence — puts a hundred rows through sync for one weekly nag.
      **The advance must be computed from the stored `remind_at` and the rule,
      never from `now`.** Advancing is a write, so it syncs, and two devices
      that both notice the same due reminder will both do it; from the stored
      value the rule is deterministic and last-edit-wins converges on the same
      next occurrence, while from `now` the two devices compute different
      answers and the reminder drifts by however far apart they polled.
      On mobile, `NotificationService` must hand the OS the next several
      occurrences rather than one: a suspended phone runs no timers, so nothing
      is there to advance the rule between fires.
      **Open question to settle before building:** what checking off a
      recurring task means. History is `completed_at` on the same row, so a
      task cannot both re-arm and appear in History without a second row. The
      cheap answer is that completing it ends the recurrence — but "every
      weekday at 09:00" is exactly the kind of task you complete daily, which
      suggests the opposite. Decide this first; it is the difference between a
      column and a table. → `sync/local_store.dart`, `sync/models.dart`,
      `reminders.dart`, `notifications.dart`, `ui/reminder_menu.dart`,
      `server/db.js`.

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
