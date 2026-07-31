# Todo Widget — Features

A running list of everything the app does. Kept up to date as features land.
Newest changes are noted in the changelog at the bottom.

## Tasks

- **Add a task** — type in the top field and press Enter.
- **Check off a task** — click the circle; it plays a slide-out animation, then
  gets logged to history (not deleted).
- **Delete a task** — the ✕ on hover removes it *without* logging (a plain dismiss).
- **Empty state** — friendly "Nothing left" message when the list is clear.
- **Park a task** — the 📥 on hover shelves it in a parked group (see below),
  taking it off the current list without deleting it.
- **Attach a document** — the 📎 on hover; see Attachments.

## Attachments

Documents attached to a task — a quote, a scan, a spec.

- **Attach** — the 📎 on a task row opens its attachment list; "Attach" picks a
  file and copies it into the app's own storage. The original is only ever read,
  and stays where it was.
- **Open / remove** — from the same list. Removing tombstones the row, so the
  removal reaches your other devices.
- **A task carrying documents shows its 📎 without hovering**, tinted in the
  workspace colour, the same way an armed reminder keeps its bell.
- **Stored content-addressed** — files are named by the SHA-256 of their
  contents rather than by their filename. Attaching the same document to two
  tasks therefore costs one copy, and a filename can never escape the storage
  directory or collide with another. Removing one of two rows sharing a file
  leaves the file alone; the bytes go when the last reference does.
- **The metadata syncs; the bytes do not.** The sync protocol is one JSON round
  trip of rows, and pushing documents through it would make every sync wait on
  the largest file anyone ever attached.
- **So "not on this device" is a real, visible state.** A document attached on
  the desktop appears on the phone as a proper named, sized entry that is dimmed
  and cannot be opened yet — rather than being hidden, or shown as broken. It
  stays removable from there, since deciding you no longer need a document
  shouldn't require being at the machine that holds it.
- **Orphaned files are swept at startup** — a row tombstoned on another device
  arrives as a merge, never as a local delete, so its bytes would otherwise sit
  on disk forever.
- The stored digest is already the address a future blob-sync endpoint would
  fetch by, so adding one later needs no migration of what is on disk.

## Parked groups

Titled shelves inside a workspace — "Backlog", "Future ideas", "Someday" — for
tasks you are deliberately not doing now. Unlike side thoughts these are
**per-workspace**: a backlog is a property of the thing you are working on.

- **Open them** — "Parked" in the ▾ views menu on the workspace bar swaps the
  content area for the parked view, the same way History and Thoughts do. Click
  the "← Parked" header, press Esc, or pick "Parked" again to go back.
- **Park a task** — the 📥 on a task row opens a picker of this workspace's
  groups, plus "New group…", which creates one and parks straight into it.
- **Unpark** — ↗ on a parked task puts it back at the *bottom* of the current
  list. ✓ checks it off from where it sits, straight into history.
- **Parking is a move, not a copy** — the same row keeps its uuid, its history
  and its reminder. Parking the task you are focused on drops focus, since
  shelving something is the opposite claim to working on it.
- **Reminders go quiet while parked** — parked means "not now", and a reminder
  firing would surface a row that is not on the list to be seen. The time stays
  stored, so unparking arms it again exactly as it was.
- **Review interval** — every group asks to be looked at on a schedule: weekly,
  monthly (the default), quarterly, yearly, or never. This is what stops a shelf
  becoming a landfill. Until the first review the clock runs from when the group
  was made, so a new group is never instantly overdue.
- **When a review comes due** — the group turns the alarm colour and shows
  "review due", and the ▾ views menu on the workspace bar gains a coloured dot,
  which is the only sign visible while the panel is closed. Opening the panel
  expands every overdue group automatically. "Mark reviewed" restarts its clock.
- **Groups collapse** — on a 340×480 window three shelves of ten items each is a
  scroll with no shape to it, so only the ones you open take up room.
- **Deleting a group releases its tasks** — everything it held comes back onto
  the current list rather than going down with it. Deleting the workspace does
  cascade, the same as it always has for tasks and history.
- **Syncs** like everything else — a `parked_groups` table plus `group_uuid` on
  `tasks` (client schema v3; both the client and the sync server migrate
  existing databases in place).

## Focus mode

- **Work on one thing** (▶ on a task) — the task flies out of its row into a tile
  in the middle of the window ("hero" transition), and *everything* else goes
  away: the workspace tabs, the add field, the rest of the list and the side
  thoughts footer all dissolve. Only the title bar stays, so the window can still
  be dragged, pinned and closed.
- **Exclusive** — only one task can be in progress at a time; starting one
  releases any other.
- **Leave focus** — "Back to list" or Esc. The tile flies back to the exact row
  it came from.
- **Done** — checks the task off straight from the focus view (logged to history
  as usual); the tile drops away and the list returns.
- **Survives restarts** — the in-progress task is stored in the DB, so reopening
  the widget drops straight back into focus on it, switching workspace if needed.
- **Park a thought without leaving** (💭, next to Done) — focus mode has its own
  side-thought field, because the footer's sits behind the overlay. Capturing
  here deliberately does *not* drop you out of focus: a stray thought is exactly
  the interruption that shouldn't cost you the task you're on. The thought still
  lands in the same global list and still blocks closing. **Ctrl+Alt+H** while
  focused now opens this field rather than leaving focus, and the button carries
  the pending count so you can see the pile growing without exiting.
- **Nudge** (toggle, bottom of the focus view) — while it's on, the tile bobs up
  and down the entire time you're focused, so it stays in the corner of your eye
  and pulls you back when you drift. Turn it off and the tile sits still. The
  setting is remembered across restarts.

## Concentration sound

The 🎧 button opens a sound sheet. It sits *above* the focus overlay, because
picking something to listen to is what you do right after picking a task — so
it stays reachable while focused. The title bar stays above it, so the window
is still draggable and closable with the sheet open. One transport throughout:
one thing plays at a time, and one volume, remembered across restarts. The
headphones light up in the workspace colour while anything is playing, and go
back to outlined when it is paused — loaded but silent should not look like
playing.

**Pause without hunting for the window.** Whenever something is loaded there is
a ⏸ / ▶ button in the title bar, next to the headphones, and on Windows the same
control appears on the **taskbar thumbnail** — hover the taskbar icon and the
pause button is right there under the preview, the way it works for a music
player. Pausing keeps the source loaded, so resuming needs no second lookup and
the now-playing label stays put (marked "· paused", since the sheet may be
opened long after). Live radio is the honest exception: a stream has no stored
position, so resuming it picks up wherever the stream is *now*.

**Volume without opening the sheet** — hover the ⏸ / ▶ button and a small volume
slider drops out underneath it. It stays up while the pointer is on either the
button or the panel, with a short grace period so the gap between them can
actually be crossed; it hangs from the button's *right* edge rather than being
centred, because everything in this bar lives in its right-hand end and a
centred panel would spill off a 340px window.

- The taskbar control is Windows-only and silently absent everywhere else.
- Windows refuses to change a thumbnail toolbar while the window is hidden, and
  this widget lives in the tray, so the intended state is cached and re-applied
  whenever the window comes back — otherwise the buttons would be stale from
  whenever it was last on screen.

Three tiers, none of which need an account, an API key, or a licence:

- **Noise** — white, pink, brown and rain, *synthesised on the spot*. Nothing is
  downloaded and nothing ships in the bundle: 30 seconds of stereo noise is
  generated to a temp WAV on first use and looped. Three things make that work
  and are covered by `test/noise_test.dart`:
  - the buffer is generated with a crossfade tail folded back over its head, so
    it joins to itself with no click at the loop point (brown noise clicks badly
    without this — the test asserts the seam step never exceeds the step the
    signal already takes on its own);
  - every kind is trimmed to the same ~0.19 RMS, because raw white noise is
    three times louder than pink and the volume slider has to mean one thing;
  - the two channels are generated independently, which is what makes it sound
    wide rather than glued to the middle of your head.
- **Ambience** — café, rain, city, forest, train and sea, streamed from the
  Internet Archive's `radio-aporee-maps` collection: thousands of field
  recordings, all CC0 or public-domain-mark. Each preset is a *query*, not a
  fixed file, so tapping the same button again gives you a different café.
- **Radio** — live stations from the Radio Browser directory, browsable by
  genre: ambient, drone, dub techno, minimal, techno, lo-fi. Near-duplicate
  entries for the same station are collapsed, and offline stations are filtered
  out. The three things the directory asks of clients are all honoured: a
  descriptive user agent, no hardcoded server (it falls through the documented
  mirrors), and plays reported back so its rankings stay accurate.

## Reminders

- **Arm one** — the 🔔 on a task offers a few horizons: in 10 minutes, in 1
  hour, in 3 hours, this evening (18:00), tomorrow (09:00). Times already past
  are not offered, so a reminder can never be set into the past.
- **Always visible once set** — an armed bell stays on the row without hovering
  (it is state the task is carrying, not an action offered on demand), and its
  tooltip says when: "in 26m", "tomorrow 09:00".
- **When it comes due, on desktop** — the widget puts *itself* in front of you:
  the window surfaces (from the tray, from minimised, from behind whatever you
  were doing), switches to the workspace the task lives in, and leaves focus
  mode if that would hide the task. No toast, no notification permissions —
  being on top of the screen is what this app is for.
- **When it comes due, on mobile** — a real OS notification, because the desktop
  answer does not carry to a phone: iOS and Android suspend the app's timers the
  moment it goes to the background and never let it raise itself to the front,
  so a reminder not handed to the OS in advance simply would not arrive. Tapping
  the notification opens the app on that task, in its workspace.
  - Scheduled ahead of time from the armed reminders, and the whole schedule is
    rebuilt on any change — including reminders merged in by sync, which no
    local write path would ever see.
  - Exact rather than batched into a doze window, since a reminder is a moment
    you picked. It survives a reboot, and it degrades to an inexact alarm if
    Android's exact-alarm permission is refused.
  - Declining the notification permission is not fatal: the app falls back to
    exactly its desktop behaviour, showing the row as due once opened.
- **Parked tasks stay quiet** — see Parked groups.
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

## Calendar

- **Three views: day, week, year.** There is deliberately no month view — the
  year is twelve months drawn at once, so a single month would be the same
  thing with less on it. D / W / Y in the header switches between them, and the
  choice is remembered.
- **Drag to create.** Drag down a column from the start time to the end time and
  the event form opens with the times already filled in, so the only thing left
  to type is the title. Drags snap to 15 minutes, and dragging upwards works —
  it is normalised rather than rejected.
  - On a **phone** it is press-and-hold, then drag: a plain one-finger drag has
    to scroll the day, which is the only way to reach the rest of it.
- **An event is** a title (required), plus an optional description, an optional
  attachment, and a start and end. Its blob on the grid shows the title, the
  first lines of the description, and a paperclip if a file is attached.
- **A calendar per workspace, plus your own.** Every workspace has a calendar in
  its own colour, and you can add free-standing ones — "Workout", "Gigs" — that
  belong to no workspace and pick their own colour. The filter menu switches
  between *this workspace* and *all workspaces*, and individual calendars can be
  unticked to get them off the screen without deleting anything.
- **Everything in the colour it belongs to**, which is the point of the week
  view: one glance says how much of the week is work, and how much is not.
- **Multi-day events sit in a band above the grid**, one bar spanning the days
  they cover, with the start and end times at its ends. A block running from
  Tuesday morning to Thursday evening has no single column to live in, and
  slicing it into three would read as three separate events.
- **Notification rules belong to the calendar** — Workout can warn you ten
  minutes ahead while Work warns you an hour ahead — because that is the level
  the answer actually varies at. Any single event can override its calendar,
  including down to silence.
- **The window grows to fit.** On desktop, opening the calendar resizes the
  widget to something a week grid fits in and puts your old size back when you
  close it. At 340px a day column is 43 pixels wide, which is not enough to read
  a title in, let alone drag out a span.
- Deleting a workspace takes its calendar and everything on it; deleting a
  free-standing calendar takes its events. A workspace calendar cannot be
  deleted on its own — the workspace is the way to do that.

## History

- **"Done recently" view** — "History" in the ▾ views menu on the workspace bar
  shows completed tasks, newest first, each with the date/time it was checked off
  (up to 100). Click the "← Done recently" header or press Esc to go back.
- Completed tasks are preserved across restarts.

## Journal / Notes

A quiet place to write, per workspace — plaintext by default, with **optional**
password encryption. Reached from the ▾ **views menu on the workspace bar**
(not the title bar): "Notes". Two things shape it: it is **quiet** (so a glance
at the screen gives nothing away) and its lock is **opt-in**.

- **Deliberately low-key** — a plain "Notes" pane in the same muted greys as the
  rest of the widget: no "journal/diary" wording, no emoji, no warm colours, no
  day-grouped timeline. It reads as an ordinary notes pane in a todo app.
- **No password needed** — by default it opens straight to the list and stores
  notes as plain text. Nothing forces a password on you.
- **Optional password + encryption** — the 🔓 button on the list sets a
  password. From then on each entry's **title and body are AES-256-GCM
  encrypted** under a key derived from it (PBKDF2-HMAC-SHA256), and **existing
  entries are re-encrypted** on the spot — the database holds only ciphertext, so
  opening `todo.db` reveals nothing and the sync server relays blobs it cannot
  read. It then opens to a plain unlock field; a **Lock** button and every app
  restart re-lock it. A **Remove password** button decrypts everything back to
  plaintext. **If you forget the password, those entries cannot be recovered.**
- **Per-entry state** — each row records whether it is encrypted, so mixed and
  synced states stay honest: a device without the password shows an encrypted
  row as a **Locked** placeholder rather than garbage, and can still keep its own
  plaintext notes.
- **Title + body editor** — creating or opening an entry replaces the list with
  a plain full-pane editor: a title line, a body area, and **Cancel / Save**
  (plus **Delete** when editing). Esc backs out of the editor first, then the
  journal.
- **Timestamped, newest-first** — the list shows each entry's title and a plain
  "Jul 20, 14:32" stamp. Editing changes the words but **not the timestamp** —
  the log records when a thing was written, not when it was later edited. Saving
  an entry emptied of both title and body deletes it.
- **Tombstoned deletes** — removing an entry marks it deleted rather than
  dropping it, so the removal reaches your other devices instead of resurrecting
  on the next sync.
- **Per-workspace**, like parked groups and unlike the global side thoughts: the
  notes belong to the thing you are working on, reload on every workspace switch,
  and go with the workspace if you delete it.
- Notes, History, Thoughts and Parked are mutually exclusive — the content area
  holds exactly one view. It syncs via a `journal_entries` table with `title`,
  `text` and an `encrypted` flag (schema v7). When encryption is on, the password
  salt and verifier are device-local, so a second device needs its own setup with
  the same password to open entries synced to it — the entries travel, the key
  material does not.

## Side thoughts

- **Capture a thought** — the 💭 button on the *left* of the footer expands a
  field to jot a quick note.
- **Review them on demand** — the 💭 count on the *right* of the footer opens
  the parked-thoughts panel, which slides up and **takes over the content area
  in place of the tasks**. Thoughts are not shown otherwise: a parked thought is
  something you deal with deliberately, not a list that should be eating room
  above your tasks the whole time. Press it again (or Esc) to go back.
  The two 💭 controls do different jobs — left captures, right reviews.
- **Promote to task** — the ↑ turns a thought into a real task.
- **Discard** — the ✕ throws a thought away.
- The panel closes itself when the last thought is cleared. It has to: the count
  badge that opens it is hidden at zero, so an empty panel would strand you in a
  view with no way back to the tasks.
- Thoughts, History and Parked are mutually exclusive — the content area holds
  exactly one view, which is what keeps a 340×480 window legible.
- Thoughts are *never* hard-deleted; every one is kept in the DB with a
  resolved timestamp.
- **Global, not per-workspace** — one pile, seen and captured from every
  workspace, and switching workspace neither hides it nor clears it. Parked
  groups are the per-workspace equivalent.
- **Switching workspace is not blocked by them.** It used to be, on the theory
  that the close guard's rule should apply everywhere. That was the wrong guard:
  since thoughts are global, moving between workspaces cannot hide or lose one,
  and all the block did was make the app feel stuck during the one activity —
  looking around your own lists — that tells you where a parked thought belongs.
  Closing still blocks; that is the path where the pile leaves the screen.
- **Pressure meter** — with the switch block gone, the footer bar carries the
  whole signal, and it escalates harder than it used to: it tints from the first
  thought, starts pulsing at 4, and reaches full intensity and its fastest pulse
  at 12. Past that the count is boxed in the alarm colour and grown, rather than
  merely tinted. The live 💭 count is always visible even though the thoughts
  themselves are not, so the pile can nag you without occupying the window.

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
  window and clear the sound sheet first. **Ctrl+Alt+T** also leaves focus mode,
  since the add field sits behind the focus overlay; **Ctrl+Alt+H** no longer
  does, because focus mode has its own thought field. If another application
  already owns a combination, the footer says so rather than leaving a dead
  shortcut.
- **Esc** unwinds one layer at a time — the sound sheet, then the focus-mode
  thought field, then focus mode, then the parked-thoughts panel.
  **Ctrl+Enter** in any capture field
  keeps it open to chain another entry, plain **Enter** closes it.
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
- **Custom icon** — gradient (indigo→violet) rounded tile with a white checkmark,
  on every platform: taskbar, tray, iOS home screen, Android launcher. iOS gets
  a full-bleed variant, since it applies its own rounded mask and a tile inside
  a tile looks like a mistake; the tray art drops most of the padding, which is
  wasted at the 16px the notification area actually draws.
- **Font** — Segoe UI Variable (Windows 11 optical sizes).

## Sync (self-hosted)

- **Your own server** — `npm run server` starts a sync server on any machine.
  It prints its LAN addresses and an access token on first run. Nothing is sent
  anywhere else; there is no hosted service.
- **Connect a device** — the ⚙ settings button opens a panel that takes a server
  address and token, with a "Test" that checks reachability separately from the
  token, so a wrong address reports itself as a wrong address. The gear's colour
  still carries sync health, so a silent failure stays visible.
- **Offline first** — the app always reads and writes its own local database.
  Sync is a background reconcile, never something the UI waits for.
- **Works with the server off** — which, for a self-hosted server, is whenever
  the machine hosting it is off. Writes go to the local database and are flagged
  until a sync accepts them; the flag lives in the database, not in memory, so
  the queue survives quitting the app or a crash. When the server comes back the
  next sync carries everything out, oldest edits included.
- **You can see the queue** — while the server is unreachable, the settings panel
  says how many changes are waiting ("3 changes waiting"), so a failed sync reads
  as *queued* rather than *lost*.
- **Syncs on wake** — returning to the app pushes immediately instead of waiting
  out the poll. This is mostly for phones, which suspend timers in the background:
  a phone that was offline all night syncs on unlock, not a minute later. It is
  rate-limited so alt-tabbing back to the desktop widget doesn't sync every time.
- **Conflicts** — last edit wins per row. Deletes travel as tombstones, so a
  removal on one device actually reaches the others. Focus mode stays globally
  exclusive even when two devices each focused a different task while offline.

## Platforms

- **Windows** — the always-on-top widget described above.
- **iOS / Android** — the same lists and data, without the window chrome
  (always-on-top has no meaning on a phone). Installed on iPhone from an
  unsigned build signed locally with Sideloadly or AltStore.
- **Home-screen quick actions** — long-press the app icon for "Add task" and
  "Park a thought". Both land in the running app with the caret already in the
  right field; this is the phone's counterpart to the Ctrl+Alt+T / Ctrl+Alt+H
  global shortcuts, and it exists for the same reason — capture speed. (Not a
  WidgetKit home-screen *widget*, which is a separate app extension and cannot
  host a text field at all.)
- **Sized for a thumb on the phone** — the layout is deliberately the same one
  as on the desktop, drawn about a quarter larger. It is one zoom applied to
  the whole widget rather than a second set of mobile paddings, so the two
  builds cannot drift apart a font size at a time. Content also keeps clear of
  the status bar and the home indicator, while the tinted background still runs
  to the edges of the screen.

## Coming from the old version

- **The Tauri database is imported automatically** — the first launch of the
  Flutter build finds the old app's `todo.db`, copies workspaces, tasks and
  side thoughts across, and records that it did so, so it never runs twice. The
  old file is only ever read: if anything goes wrong the original is still sat
  where it always was.
- Completed tasks keep the timestamp they were checked off at rather than being
  stamped with the import. History is the reason this app exists, and an import
  that reset it would migrate the data while destroying the point of it.
- Imported rows are marked as local changes, so years of history reach the sync
  server and the phone the same way a new task does.
- The empty "Tasks" workspace the fresh install creates stays put alongside the
  imported ones — deleting a workspace cascades to its tasks, which is not
  something a migration should decide on its own. Remove it in the app.

## Under the hood

- **Flutter** (Dart) for all platforms, replacing the Tauri v2 + TypeScript
  build. The Windows widget keeps its frameless, transparent, acrylic,
  always-on-top window via `window_manager` and `flutter_acrylic`.
- **SQLite persistence** on every device — `workspaces`, `tasks`,
  `parked_groups`, `attachments`, `side_thoughts` and `journal_entries`. Rows
  are keyed by UUID and carry `updated_at` and
  `deleted_at`, which is what makes them syncable; the old autoincrement ids
  collided as soon as two devices were offline at once.
- **Sync server** — Node + Express + SQLite under `server/`.
- **Audio** — `media_kit` (libmpv). Picked over the lighter alternatives because
  live internet radio is the hard case: Icecast/Shoutcast servers serve AAC+ and
  HLS and send headers that trip up Media Foundation. It costs roughly 30-40MB
  of bundled native libraries, which is the price of stations that actually
  play.

## Ideas / backlog (not built yet)

- Light theme / theme toggle.
- Configurable shortcut combinations (currently fixed at Ctrl+Alt+T / Ctrl+Alt+H).
- Reminders at an arbitrary date/time — currently presets only, because a
  Material date picker is about as wide as the whole widget.
- Recurring reminders ("every weekday at 09:00").
- **Syncing attachment bytes.** Needs a second channel beside the JSON sync —
  `PUT/GET /blob/:sha256`, content-addressed, plus an upload/download queue with
  its own retry and progress. The metadata layer is built for it already: the
  digest is the address, and "not on this device" is the state it would clear.

---

## Changelog

- **0.13.1** — **The phone build actually fits the phone now.** Two bugs, which
  together were why most of the controls on iOS could not be tapped. The zoom
  wrapped the app in a `SizedBox`, which cannot override the tight constraints
  it is handed — so the layout ran at the full screen width and was then
  magnified by 1.28, painting about a fifth of the width and height off the edge
  of the screen. Nothing warned about it: a transform does not report overflow.
  And the zoom was a flat 1.28 regardless of screen, which left a 375pt phone
  only 293 points to lay out in — narrower than the 340 window every size in the
  app was picked against. The zoom is now the largest one that still leaves the
  layout its design width, capped at 1.28, so the widget fills the screen
  exactly on every phone and is never squeezed below the size it was drawn for.
  Also: `server/start-server.ps1` and `server/start-server.sh` start the sync
  server from anywhere, install dependencies on first run, and say what to do
  about the firewall; and the server's address list now drops link-local
  addresses and puts the likely-right one first.

- **0.13.0** — **The calendar.** Day, week and year views, with events you make
  by dragging from a start time to an end time. Every workspace gets a calendar
  in its own colour and you can add free-standing ones alongside them
  ("Workout"), so a week reads as a picture of where the time actually goes —
  which was the point of building it. Multi-day events get a spanning band above
  the grid rather than being sliced into one block per day. Notification rules
  sit on the calendar, where the answer varies, and any event can override its
  own. Two structural notes: a workspace's calendar deliberately carries that
  workspace's uuid, so two devices provisioning it offline produce one row
  rather than two; and on desktop the widget grows to fit the grid and shrinks
  back on the way out, because a seven-column week does not fit in 340px.

- **0.12.4** — **Trusting the offline queue.** Writing with the sync server off
  already worked — every write goes to the local database first and carries a
  flag until the server accepts it — but nothing said so, and two gaps made it
  less reliable than it looked. The settings panel now reports the queue depth
  when a sync fails ("Cannot reach server… 3 changes waiting"), which is the
  difference between *queued* and *lost*. And the app now syncs when it returns
  to the foreground: a suspended phone runs no timers, so a phone that spent the
  night offline used to sit for another minute after unlock before pushing
  anything. That resume is rate-limited, because desktop reports the same
  lifecycle event on every focus change and an always-on-top widget is focused
  constantly. The queue itself is unchanged — it was always the `dirty` column,
  which is why it survives a crash.

- **0.12.3** — **A visible way out of Notes, Parked and History.** These three
  take over the content area, and nothing on screen said how to get back — Esc
  worked and re-picking the menu item closed them, but neither was discoverable.
  The header label at the top of each view is now the back control itself
  ("← Parked", "← Notes", "← Done recently"), which puts the way out on the very
  thing that says where you are and costs no extra row. Two gaps closed
  alongside it: **Esc now closes History** (it handled thoughts, parked and the
  journal, but History had been left out of the unwind chain), and the ▾ views
  menu now **ticks and tints whichever view is open**, so closing it from there
  is findable too — with the ▾ itself tinting while any view is open. Not the
  workspace tab: that is the edit control, and it answers "which workspace", not
  "which view".

- **0.12.2** — **Pause the sound from the taskbar.** The concentration sound
  gained a real pause (as opposed to only stop), surfaced two ways: a ⏸ / ▶
  button in the title bar beside the headphones whenever something is loaded,
  and — on Windows — a matching button on the taskbar thumbnail, so hovering the
  taskbar icon silences it without bringing the widget forward. Pausing keeps
  the source loaded; the now-playing label stays and says "· paused". The
  headphones now only fill in while audio is actually running. Hovering the
  transport button drops out a **volume slider**, so the level is adjustable
  without opening the sheet either. The **pin** now lights in the workspace
  colour rather than the fixed theme accent, so every lit control in the title
  bar reads as one family.

- **0.12.1** — **Workspace bar tidy.** The bar now shows only the *active*
  workspace as a tab, with a ▾ switcher tucked into that tab's right edge
  listing the others — a fixed width no matter how many workspaces exist,
  instead of a row that scrolled once there were more than a few. Clicking the
  name still opens the workspace for editing; the arrow, divided off inside the
  same outline, opens the switcher. It sits *inside* the pill rather than beside
  it so it cannot be mistaken for the free-standing ▾ views menu further along
  the bar — two loose arrows in one 340px row read as two of the same control.
  In the title bar the ☁ sync button became a ⚙
  settings gear (it always opened Settings, where sync lives); the gear still
  tints with sync health.

- **0.12.0** — **Journal / Notes**, and a tidy of where per-workspace views
  live. A per-workspace place to write, deliberately low-key — a plain "Notes"
  pane in the widget's own muted greys, no diary chrome — so a glance at the
  screen gives nothing away. Plaintext by default; a password is **optional** and
  turns on encryption (AES-256-GCM under a PBKDF2 key), re-encrypting existing
  entries so the `todo.db` file and the sync server hold only ciphertext, with a
  Lock button, re-lock on restart, and a Remove-password path back to plaintext.
  Each row records whether it is encrypted, so a device without the password
  shows encrypted rows as "Locked" rather than garbage. Entries have a title and
  a body, edited in a plain full-pane in-app editor with Cancel / Save, are
  timestamped newest-first (editing keeps the original stamp), and tombstone on
  delete. Per-workspace like parked groups (cascaded when a workspace is
  deleted). Adds a `journal_entries` table with `title`, `text` and an
  `encrypted` flag (schema v7; client and server migrate in place). **Notes,
  Parked and History** now live in a ▾ menu on the **workspace bar** rather than
  the title bar — they are about the current workspace, not the window — leaving
  the title bar to the window/global controls (sync, sound, pin, minimize,
  close).
- **0.11.0** — Five things, mostly about what happens to work you are *not*
  doing right now.
  **Attachments**: documents on a task, stored content-addressed so the same
  file attached twice costs one copy. The row syncs, the bytes stay device-local
  — so an attachment made on the desktop shows on the phone as a real named
  entry marked "not on this device", rather than being hidden or looking broken.
  Adds an `attachments` table (schema v4).
  **Parked groups**: titled shelves per workspace ("Backlog", "Future ideas")
  that take tasks off the current list without deleting them, each with a review
  interval — monthly by default — after which the group says so, in the panel
  and as a dot on the title bar. Deleting a group releases its tasks rather than
  taking them with it. Adds `parked_groups` and `group_uuid` on `tasks` (schema
  v3; client and server both migrate in place).
  **Mobile reminders** now fire as real OS notifications, scheduled ahead of
  time and rebuilt from the database on every change, because a phone will not
  let the app surface itself the way the desktop widget does.
  **Home-screen quick actions** on iOS and Android — long-press the icon to add
  a task or park a thought, the phone's version of the global shortcuts.
  **Side thoughts no longer block switching workspace.** They are global, so
  switching cannot lose one; the block only punished looking around your own
  lists. The footer's pressure meter escalates earlier and harder to compensate,
  and closing still blocks.
- **0.10.0** — Concentration sound. A 🎧 sheet with three tiers — synthesised
  white/pink/brown/rain noise, public-domain field recordings from the Internet
  Archive, and live radio from the Radio Browser directory — all key-free and
  licence-free, and reachable from inside focus mode. Focus mode also gained its
  own side-thought field, so parking a stray thought no longer costs you the
  task you're on, and the focus tile now keeps clear of the window edges instead
  of snapping to full width the moment its flight ended. Parked thoughts stopped
  living permanently above the task list: the 💭 count in the footer now opens
  them as a panel that replaces the tasks, and the footer is just the bar again.
- **0.9.2** — The app finally looks like itself on every platform: the
  indigo→violet checkmark replaces the placeholder Flutter logo in the taskbar,
  the tray, the iOS home screen and the Android launcher. Databases written by
  the old Tauri build are imported automatically on first launch, so the
  history from before the rewrite is back — and syncs to the phone with
  everything else.
- **0.9.1** — Made the phone build fit the phone: everything is drawn ~28%
  larger, and the title bar no longer sits underneath the iOS status bar.
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
