# Roadmap

What is agreed but not yet in `FEATURES.md`. An item leaves this file when it
ships: the description moves into the feature list and the changelog, the
reasoning moves into the comment above the code that needed it, and the line
here becomes one line under *Shipped*. Longer-term wishes with no design behind
them live in FEATURES.md's *Ideas / backlog* section instead — this file is for
work that is about to happen.

## In progress

*Nothing queued.*

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
