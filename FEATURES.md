# Todo Widget — Features

A running list of everything the app does. Kept up to date as features land.
Newest changes are noted in the changelog at the bottom.

## Tasks

- **Add a task** — type in the top field and press Enter.
- **Check off a task** — click the circle; it plays a slide-out animation, then
  gets logged to history (not deleted).
- **Delete a task** — the ✕ on hover removes it *without* logging (a plain dismiss).
- **Empty state** — friendly "Nothing left" message when the list is clear.

## Focus mode

- **Work on one thing** (▶ on a task) — the task flies out of its row into a tile
  in the middle of the window ("hero" transition), and *everything* else goes
  away: the workspace tabs, the add field, the rest of the list and the side
  thoughts footer all dissolve. Only the title bar stays, so the window can still
  be dragged, pinned and closed.
- **Exclusive** — only one task can be in progress at a time; starting one
  releases any other.
- **Leave focus** — "Back to list", Esc, or the 🕘 button. The tile flies back to
  the exact row it came from.
- **Done** — checks the task off straight from the focus view (logged to history
  as usual); the tile drops away and the list returns.
- **Survives restarts** — the in-progress task is stored in the DB, so reopening
  the widget drops straight back into focus on it, switching workspace if needed.
- **Nudge** (toggle, bottom of the focus view) — while it's on, the tile bobs up
  and down the entire time you're focused, so it stays in the corner of your eye
  and pulls you back when you drift. Turn it off and the tile sits still. The
  setting is remembered across restarts.

## History

- **"Done recently" view** — the 🕘 button shows completed tasks, newest first,
  each with the date/time it was checked off (up to 100).
- Completed tasks are preserved across restarts.

## Side thoughts

- **Capture a thought** — the 💭 button expands a field to jot a quick note.
- **Promote to task** — the ↑ turns a thought into a real task.
- **Discard** — the ✕ throws a thought away.
- Thoughts are *never* hard-deleted; every one is kept in the DB with a
  resolved timestamp.
- **Pressure meter** — the footer bar reddens as pending thoughts pile up, and
  starts pulsing at 10 (faster the closer you get to 20). A live 💭 count shows.

## Window & look

- **Frameless, always-on-top widget** — small (340×480), transparent rounded
  corners, acrylic/blur background. A Sticky-Notes-style replacement.
- **Drag** anywhere on the title bar to move it.
- **Pin toggle** (📌) — turn always-on-top on/off.
- **Minimize** (—).
- **Close guard** (✕ / Alt+F4) — the window *refuses to close* while any task or
  side thought remains, so you're forced to move everything into your real
  planner (or check it off) first. The footer shakes red ("Clear it all first")
  when a close is refused; once the list and thoughts are empty, it closes.
- **Resizable** within sensible min bounds.
- **Custom icon** — gradient (indigo→violet) rounded tile with a white checkmark.
- **Font** — Segoe UI Variable (Windows 11 optical sizes).

## Under the hood

- **Tauri v2** (Rust backend) + vanilla TypeScript frontend (Vite).
- **SQLite persistence** — a single `tasks` table (state = `completed_at`) plus a
  `side_thoughts` table, stored in the OS app-data dir. History survives upgrades.

## Ideas / backlog (not built yet)

- Launch on Windows startup.
- System tray icon.
- Due dates or reminders.
- Light theme / theme toggle.

---

## Changelog

- **0.6.0** — Focus mode: ▶ on a task now flies it into a tile in the middle
  of the window and hides everything else, instead of just tinting the row. One
  task at a time (it used to allow several), and it survives a restart. Optional
  "Nudge" keeps the tile bobbing while you're focused.
- **0.1.3** — Restored the close guard (window won't close until all tasks and
  side thoughts are cleared) — now race-free: it re-checks the database at close
  time instead of trusting a laggy counter, so it can't wrongly block you when
  the list really is empty. Clearer "Clear it all first" feedback.
- **0.1.2** — New gradient-checkmark icon; switched to the Segoe UI Variable
  font. (Briefly removed the close guard here — restored in 0.1.3.)
- **0.1.1 / 0.1.0** — Initial tasks, history, side thoughts, always-on-top widget.
