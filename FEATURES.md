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

## Reminders

- **Arm one** — the 🔔 on a task offers a few horizons: in 10 minutes, in 1
  hour, in 3 hours, this evening (18:00), tomorrow (09:00). Times already past
  are not offered, so a reminder can never be set into the past.
- **Always visible once set** — an armed bell stays on the row without hovering
  (it is state the task is carrying, not an action offered on demand), and its
  tooltip says when: "in 26m", "tomorrow 09:00".
- **When it comes due** — the widget puts *itself* in front of you: the window
  surfaces (from the tray, from minimised, from behind whatever you were doing),
  switches to the workspace the task lives in, and leaves focus mode if that
  would hide the task. No toast, no notification permissions — being on top of
  the screen is what this app is for.
- **Stays due** — the row turns red and keeps showing as due until the task is
  checked off or the reminder cleared. The window only surfaces once per
  reminder, though; an unfinished task will not keep interrupting you.
- **Survives being closed** — reminders live in the database, not in a timer, so
  one that came due while the app was shut or the machine asleep fires on the
  next launch instead of being silently lost.
- **Syncs** — set a reminder on the phone, it is armed on the desktop. Whether
  it has already *fired* is deliberately per-device, so the first device to
  remind you does not silence the others.
- Stored as an instant (UTC), so a reminder still means the right moment after
  crossing a timezone.

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
- **Global shortcuts** (desktop) — **Ctrl+Alt+T** jumps straight into the
  add-task field and **Ctrl+Alt+H** into the side-thought field, from anywhere,
  even when the widget is minimised or behind another window. Both raise the
  window and leave focus mode first, since the capture fields sit behind the
  focus overlay. If another application already owns a combination, the footer
  says so rather than leaving a dead shortcut.
- **Esc** leaves focus mode; **Ctrl+Enter** in either capture field keeps it
  open to chain another entry, plain **Enter** closes it.
- **System tray icon** (desktop) — the widget lives in the notification area.
  Left-click brings it back from hidden, minimised or buried; right-click gives
  Show / Hide / Add task / Quit. **Hide** is the tray's own trick: unlike
  minimize it drops the widget out of the taskbar entirely, with the tray icon
  as the way back. **Quit** goes through the same close guard as ✕ and Alt+F4 —
  it is not a back door around it, and if pending side thoughts block the quit
  the window surfaces itself to say so rather than silently ignoring the click.
- **Start with Windows** (toggle in Settings) — opens the widget when you sign
  in. Windows itself owns this setting (the `Run` key), so turning it off in
  Task Manager's Startup tab is reflected here; if a machine policy refuses the
  change, the switch shows what actually took effect rather than what was asked.
- **Resizable** within sensible min bounds.
- **Custom icon** — gradient (indigo→violet) rounded tile with a white checkmark.
- **Font** — Segoe UI Variable (Windows 11 optical sizes).

## Sync (self-hosted)

- **Your own server** — `npm run server` starts a sync server on any machine.
  It prints its LAN addresses and an access token on first run. Nothing is sent
  anywhere else; there is no hosted service.
- **Connect a device** — the ☁ button takes a server address and token, with a
  "Test" that checks reachability separately from the token, so a wrong address
  reports itself as a wrong address.
- **Offline first** — the app always reads and writes its own local database.
  Sync is a background reconcile, never something the UI waits for.
- **Conflicts** — last edit wins per row. Deletes travel as tombstones, so a
  removal on one device actually reaches the others. Focus mode stays globally
  exclusive even when two devices each focused a different task while offline.

## Platforms

- **Windows** — the always-on-top widget described above.
- **iOS / Android** — the same lists and data, without the window chrome
  (always-on-top has no meaning on a phone). Installed on iPhone from an
  unsigned build signed locally with Sideloadly or AltStore.

## Under the hood

- **Flutter** (Dart) for all platforms, replacing the Tauri v2 + TypeScript
  build. The Windows widget keeps its frameless, transparent, acrylic,
  always-on-top window via `window_manager` and `flutter_acrylic`.
- **SQLite persistence** on every device — `workspaces`, `tasks` and
  `side_thoughts`. Rows are keyed by UUID and carry `updated_at` and
  `deleted_at`, which is what makes them syncable; the old autoincrement ids
  collided as soon as two devices were offline at once.
- **Sync server** — Node + Express + SQLite under `server/`.

## Ideas / backlog (not built yet)

- Light theme / theme toggle.
- Configurable shortcut combinations (currently fixed at Ctrl+Alt+T / Ctrl+Alt+H).
- Reminders at an arbitrary date/time — currently presets only, because a
  Material date picker is about as wide as the whole widget.
- Recurring reminders ("every weekday at 09:00").

---

## Changelog

- **0.9.0** — Reminders. A task can be told to nag at one of a few horizons;
  when it comes due the widget surfaces itself and the row stays red until it is
  dealt with. Reminders sync between devices and are stored in the database
  rather than a timer, so one that came due while the app was closed still
  fires. Adds `remind_at` to `tasks` — both the client (schema v2) and the sync
  server migrate existing databases in place.
- **0.8.0** — The widget now has a life outside its window: a system tray icon
  (show / hide / add task / quit, with Quit still answering to the close guard)
  and a "Start with Windows" toggle in Settings. Hiding to the tray is new —
  previously the only way to get it off screen was minimize, which left it in
  the taskbar.
- **0.7.0** — Went cross-platform. Rewrote the client in Flutter (Windows, iOS,
  Android) and added a self-hosted sync server so the same lists follow you
  between devices, syncing automatically. Deleting a task now leaves a
  tombstone instead of dropping the row, so deletes actually propagate, and
  deleting a workspace takes its tasks with it. Global shortcuts are back.
  iOS builds are produced by CI as an unsigned .ipa for local signing.
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
