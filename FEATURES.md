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
- **The long form — Ctrl+D, or the ⤢ in the add field.** Opens a bigger
  composer for the task that needs more than a line: **notes**, a **priority
  flag** and a **reminder**, all set before it ever reaches the list. Whatever
  you had already typed comes across as the title and the caret lands straight
  in the notes box, so the shortcut never costs you the line you were writing.
  Cancelling leaves the quick field exactly as it was.
- **Notes stay readable.** A task carrying notes previews their first line under
  its title, and clicking the title reopens the composer on that task. A note
  you can only write is a note you will not write.
- **Notes are Markdown, and open rendered.** Reopening a task that already has
  notes shows them formatted, with an *Edit* toggle (or a tap on the text) back
  to the raw source; a task with no notes yet opens straight into the field, so
  Ctrl+D still puts the caret where you were about to type. See **Markdown &
  maths**.
- **High priority** — the ⚑ on hover flags a task: a red bar down its leading
  edge and a red border, so it reads as urgent from across the room. The bar is
  a separate channel from the overdue-reminder red and the focus tint, so a task
  can be flagged, overdue *and* in progress without any of the three hiding
  another. Flagging deliberately **does not reorder the list** — that order is
  yours, set by dragging, and a flag that jumped a row to the top would be a
  second sort fighting the first.

## Markdown & maths

Every long-form field in the app is **Markdown** — a task's notes, a journal
entry's body, and a calendar event's description. One dialect, one renderer,
three places.

- **The dialect is GitHub Flavored Markdown**, the one you already know:
  headings, **bold**, *italic*, ~~strikethrough~~, links, bullet and numbered
  lists, `- [x]` task lists, tables, block quotes, `code` spans and fenced code
  blocks, horizontal rules. Picking an existing dialect rather than inventing
  one is the point — notes get pasted in from somewhere else at least as often
  as they get typed here.
- **Maths, GitHub's way.** `$…$` for a formula in a sentence, `$$…$$` or a
  ```` ```math ```` fence for one on a line of its own, rendered as real LaTeX.
  `$\pi r^2$` comes out set, not quoted.
- **Money is safe.** "it costs $5, or $7 with tax" stays text: a `$` delimiter
  may not sit against a space, and a closing `$` may not be followed by a digit.
  `\$` is always a literal dollar. This matters because switching maths on
  re-reads notes that were written before it existed.
- **A formula with a typo in it shows what you typed**, in red, rather than
  vanishing or throwing. Notes are written in passing and half of them are wrong
  for a minute.
- **Read first, then edit.** Notes and journal entries open *rendered*, with a
  pencil (or a tap on the text) to get at the source; a calendar event's details
  card was already read-only, so its description simply renders. Nothing is a
  split-screen preview — this window is 340×480 by design, and half of it is not
  enough for either pane.
- **A single newline is a line break**, unlike strict Markdown, which folds it
  into a space. These are notes: a stack of bare lines is written far more often
  than a paragraph is wrapped by hand.
- **Previews are flattened, not rendered** — the notes line under a task title
  and an event's description in the agenda show the *text* of the Markdown on
  one line, so a note that opens with a heading previews as its words rather
  than as `## Trip`.
- **Links open in your browser** on a click, from any of the three surfaces.

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
- **Or drag it there.** When the window is wide enough that the parked panel
  sits *beside* the list rather than replacing it, a task can be dragged
  sideways out of the list and dropped on a group. The group lights up while the
  task is over it and opens when the task lands, so you can see where it went
  rather than watching a count tick up on a closed shelf. Any group is a target,
  open or collapsed or empty — the collapsed ones are exactly what you are most
  likely putting something away into. A vertical drag still scrolls and the ≡
  handle still reorders; only a drag *towards the panel* means "put this away".
  Narrower windows keep the 📥 picker, which works at every size.
- **Unpark one** — ↗ on a parked task puts it back at the *bottom* of the current
  list. ✓ checks it off from where it sits, straight into history.
- **Unpark the whole shelf** — ↗ on a group header puts everything on it back
  onto the list, in the order the shelf held it. **It asks first** — "All 7
  todos in "Backlog" will be put onto the active todo list" — because one press
  can move a dozen rows and there is nothing to undo it with. The group itself
  stays: emptying a backlog is not the same as deciding you no longer keep one.
  Anything checked off while it sat on the shelf stays checked off.
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

**It keeps playing with the screen off.** On iPhone the sound survives locking
the phone and switching to another app — which is the only way a two-hour
concentration sound is any use, and it is not the default: an app that says
nothing gets an audio session that the lock switch silences. The app asks for
the playback session at launch but only *takes* it when you press play, so
opening the widget never interrupts whatever you were already listening to.

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
- **Or pick an exact date and time** — the last item on the same menu, and a
  *Pick…* chip in the task composer. A month grid you can page through, day
  selected with a tap, and the time either typed or taken from a chip (09:00,
  12:00, 14:00, 18:00, 21:00). It opens on the reminder that is already armed
  rather than on today, defaults to the next round hour rather than to this
  minute, and refuses a time in the past with a visible reason instead of a
  dead button. It is the same month grid the year view draws, so the two can
  never disagree about where a month starts.
- **Repeat it** — *Every day / weekday / week / month / year*, in the composer,
  offered once a reminder is set (a rule with nothing to count from would never
  produce a second occurrence). Checking a recurring task off does two things:
  the one you finished goes to History like any other completed task, and the
  next occurrence appears on the list, armed for the next time the rule comes
  round. An occurrence is a todo in its own right, which is what lets a daily
  task both be *done today* and *still due tomorrow*.
  - The next one is laid down when you **check the last one off**, not when the
    reminder fires — so a recurring task you have been ignoring sits there as
    one overdue row rather than thirty copies.
  - "Every day at 09:00" stays at 09:00 across a daylight-saving change: the
    next occurrence is worked out in wall-clock terms, not by adding 24 hours.
  - A monthly task on the 31st lands on the 30th, or the 28th, rather than
    sliding into the next month. Same for the 29th of February, yearly.
  - Turning it off is *Once* in the composer, which stops the series — there is
    only ever one occurrence in front of you, so there is nothing else to
    cancel.
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
  - Creating only happens on **empty** grid. A click or press on an existing
    event opens that event and nothing else.
- **Click an entry to read it; right-click for what to do with it.** A plain
  click opens a **details card** — when it runs and for how long, its calendar,
  its reminder rule, the description, what is planned into it and what is
  attached — with *Edit*, *Todos* and *Delete* named on it. Clicking used to
  open the edit form outright, which answered the rarer of the two reasons for
  clicking and put a form full of live fields one keystroke away from changing
  something nobody meant to touch. **Right-click** (or **long-press** on a
  phone) skips the card and offers the same actions directly. Both work on the
  hour grid, on the multi-day band and in the agenda.
- **Time-block mode** (⚡ in the header) is for laying out a whole week at once.
  Pick a calendar once from the strip of chips that appears under the header, and
  from then on every drag saves an event straight away, titled after that
  calendar — no form, no dismissing anything. Planning a week is the same gesture
  twenty times over and nineteen of the titles are the same word, so the editor
  in between is twenty dismissals. The draft under the pointer is drawn in the
  target's colour and carries its name, so you can see what a drag is about to
  become. Switching target is one tap on another chip; ⚡ again, or the ✕ on the
  strip, leaves the mode. Anything a block needs beyond a span — a note, a
  reminder, a different title — is one tap on the block afterwards.
- **An event is** a title (required), plus an optional description, an optional
  attachment, todos planned into it, and a start and end. Its blob on the grid
  shows the title, the first lines of the description, a count of its open
  todos, and a paperclip if a file is attached. The description is **Markdown**
  and renders as such on the details card (see **Markdown & maths**).
- **Plan todos into a block.** Open a saved event and tick tasks from the
  workspace's open list — planning is choosing among things you have already
  decided to do, so there is nothing to type. A planned task **stays on the
  list** (it is not parked; saying *when* should not make it harder to see) and
  wears a small calendar mark, which is also the way to take it back out. A task
  is in at most one block, so ticking it somewhere else moves it; a task planned
  elsewhere says so rather than being hidden. Deleting the block releases its
  todos — they are still things to do, they have only lost the time set aside
  for them.
- **A block can have a list of its own — "Sublist".** Rather than only choosing
  among tasks you already have, you can write a block's todos straight into it:
  the sheet has an add field at the top ("print the slides") and folds the rest
  of the workspace's open list underneath, one tap each to take one in. It is
  reached from the "Now" tile when the running block is empty, from the session
  view, and from *Todos* in an event's right-click menu. Nothing new is stored —
  a sublist is simply the tasks pointing at that block.
- **"Now" — the session view.** While a block is running, a banner appears above
  the task list saying what it is, when it ends and how much is left on it.
  Opening it shows **only** the todos planned into that block, with a live
  countdown — the payoff for planning a week, and the answer to "what am I meant
  to be doing right now" without going to look for it. Check them off, or ▶ one
  into focus mode, from there.
  - **The tile switches workspace with you.** A block names a workspace through
    its calendar, and it is the one control in the app that talks about a
    workspace other than the one on screen — so pressing it takes you there,
    rather than showing that block's todos beside a different list.
  - If the running block has **nothing** planned into it, the tile does not open
    an empty view; it stays on your list and offers **Sublist** instead.
  - There is no permanent button for it because for most of the day there is no
    answer: the way in appears when a block starts and the view hands the
    content area back when the last one ends. Esc closes it like the other
    views.
  - It ignores the calendar's scope and hidden filters — those are about what
    you want to *look at*, and this is about what time it is. A block on
    another workspace's calendar shows, and says whose it is.
  - Overlapping blocks are all listed, each with its own todos. Two things
    really can be scheduled at once, and choosing one for you would be a guess.
  - A parked task drops out of its session (shelving says "not now") but keeps
    its plan, so unparking puts it back in the block.
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
- **On a big window the calendar opens *beside* the list, and you can drag onto
  it.** Past about 810px wide the calendar stops replacing the window: the task
  list keeps the left-hand column (with its workspace bar and its add field) and
  the calendar takes the rest. **Drag a task onto a block** to plan it into that
  block — the block lights up as you come over it, and letting go is the same
  thing ticking it in the event editor does, reached from where you are actually
  looking at the task. Dragging *down* still scrolls the list and the ≡ handle
  still reorders it; only a drag towards the calendar means "plan this". Like
  every other adaptation here this is a size, not a mode — there is nothing to
  switch on, and below that width the calendar behaves exactly as it always has.
- **The calendar fits the window you have.** Opening it never moves or resizes
  the widget. Instead the views change shape:
  - The **week stays a week** — seven real columns you can drag on — right down
    to phone width. It gets there by tightening rather than by dropping a day:
    the hour gutter narrows and loses its ":00", the day names become initials
    (`M 27`), and a block shows its title alone. That is the same trade every
    phone calendar makes, and it is what a 393pt iPhone shows.
  - Below about 300px — the widget dragged down to its smallest — the **week
    becomes an agenda**: the same seven days stacked, each event on a line of
    its own with its times beside it. Days with nothing on them still appear,
    marked *free*, because which days are clear is half of what you came to find
    out. A **+** on each day header makes an event there, and tapping the day
    drops into its grid where dragging works.
  - The **year reflows**, from four months across down to a single column of
    twelve — a year as one scrolling strip of months, which is how it fits in a
    340px widget. Every month tile is drawn on a six-week grid whether its month
    needs one or not, so tiles side by side are the same height rather than
    ragged.
  - The grid comes back on its own the moment the window is wide enough for
    seven readable columns. Make the window big and it stays big.
- Deleting a workspace takes its calendar and everything on it; deleting a
  free-standing calendar takes its events. A workspace calendar cannot be
  deleted on its own — the workspace is the way to do that.

## Importing calendar files

- **Import .ics** from the calendar's tune menu. Reads what other applications
  produce - a mail client's invite, a booking confirmation, a train ticket -
  and adds the events to a calendar you pick.
- **Nothing is written until you say so.** The events are listed with their
  times, you choose the destination calendar (defaulting to the current
  workspace's own), and only then are they saved. An import that happened
  silently into whichever calendar was in front of you is the sort of thing
  discovered three weeks later.
- An imported block is an **ordinary event** in every respect - no "imported"
  flag, no separate handling. Location and description come across as the
  event's description.
- **A repeating event is imported once**, and both the list and the resulting
  description say so. The series cannot be stored, and importing one occurrence
  while saying nothing would be the version of this you find out about late.
- Handles what real producers actually emit: folded long lines, escaped commas
  and newlines, all-day dates with their exclusive end, `DURATION` instead of an
  end time, quoted `TZID` parameters, and both CRLF and LF. A malformed event in
  a file of five costs that one event, not the import.
- Times written as UTC are converted; times written without a zone keep their
  reading, which is what a printed ticket means.

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
- **Title + body editor** — creating an entry replaces the list with a plain
  full-pane editor: a title line, a body area, and **Cancel / Save** (plus
  **Delete** when editing).
- **Opening an entry reads it.** Picking one from the list renders its body as
  Markdown (see **Markdown & maths**) under its title; the ✎ in the header, or a
  tap on the text, turns it back into the two fields. A *new* entry skips
  straight to the fields, because there is nothing to read yet. Esc walks back
  down the same ladder it walked up — editor → reader → list → tasks.
- **Keys, for writing without reaching for the mouse:**
  - **Ctrl+Enter** — from the title down to the body. (Enter does the same, and
    Tab is left to ordinary focus traversal.)
  - **Ctrl+S** — save and read what you just wrote. The **Save** button does
    this too.
  - **Ctrl+Alt+S** — save and go back to the list, for an entry that is finished
    rather than one you want to re-read.

  Saving an entry emptied of both fields deletes it, so those keys land on the
  list rather than on a rendering of nothing.
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
- **Pin toggle** (📌) — turn always-on-top on/off. The pin is *held*, not just
  set once: always-on-top is a Windows style bit that other applications can
  take away — one of them going full screen makes Windows strip it from every
  other window, and nothing puts it back when that application quits. So the
  widget re-asserts it whenever it notices the bit missing (on the same 20-second
  poll the reminders use, and immediately when you click back onto the widget).
  Without that, closing something like Windows Photo Viewer left the widget an
  ordinary window that still called itself pinned, and it stayed behind
  everything until the app was restarted.
- **Minimize** (—).
- **Close guard** (✕ / Alt+F4) — the window *refuses to close* while any task or
  side thought remains, so you're forced to move everything into your real
  planner (or check it off) first. The footer shakes red ("Clear it all first")
  when a close is refused; once the list and thoughts are empty, it closes.
- **A "Closing…" state while it goes.** Tearing the window down is not instant —
  the engine, the acrylic surface and the audio player all come down with it —
  and the widget used to spend that time sitting there looking alive and
  apparently ignoring the ✕. It now dims and says what it is doing, and a second
  click on ✕ or Alt+F4 is swallowed rather than starting a second teardown.
  Anything still playing is stopped first, since an open network stream is the
  one part of the wait that can be got out of the way in advance.
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

## Adapting to the window

The widget is one window that ranges from a 260px sliver in the corner of a
screen, through the 340×480 it was designed against, to a half-screen panel on a
big monitor — and it is the same window the whole time. Rather than each view
guessing at its own thresholds, every size-dependent decision lives in one
place, and follows two rules: **no size takes a feature away** (it changes
shape instead), and **extra width buys more at once, not bigger** — nothing is
simply stretched.

- **340px and up — the widget as designed.** Nothing below is missing here; the
  workspace list and the views sit behind the two ▾ menus, and the calendar
  shows the compact week grid and the single-column year described above.
- **~300px — the week grid gives way to the agenda**, below which seven columns
  stop being columns. Widen it and the grid comes straight back.
- **~560px and 400px tall — the workspace bar unrolls into a side rail.** The
  same controls, no longer behind a press: every workspace listed down the left,
  and Tasks / Notes / Parked / History as permanent entries, with the count of
  pending side thoughts and the parked-review dot where you can see them.
  Clicking a workspace switches to it, clicking the one you are on edits it —
  exactly the tab's behaviour. Narrow the window and the bar comes back.
- **~810px — the calendar stops covering the tasks.** It opens beside the list
  rather than taking the window, which is also the only arrangement in which a
  task can be dragged onto a block (both ends of that gesture have to be on
  screen at once). The threshold is the list at its design width plus a week
  grid whose seven columns are still roomy — neither half is squeezed to make
  room for the other. The calendar half measures *itself*, so the week's shape
  is decided by the space the calendar actually got rather than by the window.
- **~900px — the panels stop covering the tasks.** Notes, Parked, History and
  the thoughts pile open *beside* the task list instead of replacing it, so
  reviewing what you parked no longer costs you sight of what you are meant to
  be doing.
- **The task column stops at 620px.** Beyond that the extra room goes to the
  rail and the second pane: a tick box 900 pixels from the end of its own line
  is a worse checklist, not a bigger one. The focus tile is capped the same way
  and stays centred — a task title stretched across a wide window is a line you
  have to sweep your head along.
- The **phone zoom** sits underneath all of this: sizes are picked against a
  340px layout and the whole widget is drawn larger on a phone, so a phone
  reports the width its layout actually runs at and gets the same decisions a
  desktop window of that width would.

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
- **Changes appear at once** — tick something off on the phone and the desktop
  updates in about a second, rather than on the next poll. The server holds an
  open connection to each running device and tells the *others* when your
  account has moved; they then run the ordinary sync. Nothing about the data
  travels down that connection — it is a nudge, not a second way for rows to
  arrive — so a device that cannot hold it open (an older server, a proxy that
  buffers, a phone in a tunnel) is exactly as correct as before, just up to a
  minute slower. The settings panel says "Live." when it is connected.
- **It notices when the server is not the one it was talking to** — a rebuilt
  database, a restore from an older backup, or a different account at the same
  address. Each device tracks which server and account its local rows were last
  accepted by; when that stops matching it re-offers everything it has instead
  of assuming a row it once uploaded is still there. Without this the two sides
  could sit there permanently disagreeing and both look healthy: the device
  believes every row is sent, the server has never heard of most of them, and a
  new phone set up against it pulls the fragment and looks fine.
- **Syncs on wake** — returning to the app pushes immediately instead of waiting
  out the poll. This is mostly for phones, which suspend timers in the background:
  a phone that was offline all night syncs on unlock, not a minute later. It is
  rate-limited so alt-tabbing back to the desktop widget doesn't sync every time.
- **Conflicts** — last edit wins per row. Deletes travel as tombstones, so a
  removal on one device actually reaches the others. Focus mode stays globally
  exclusive even when two devices each focused a different task while offline.
- **More than one person per server** — give someone their own account and they
  get their own tasks, workspaces, journal and calendar on your server. Nothing
  is shared, and neither of you can see the other's rows. It is one server and
  one database, partitioned by account — not a shared list.
- **You are the admin, and you invite people from the app** — whoever signs in
  with the token the server printed is an admin of it. Settings then grows a
  *People on this server* panel: add someone, and it shows their token once, to
  copy and hand over. They enter it in their own Settings, with the same address.
  The panel also lists everyone, shows when each device last synced, revokes a
  token, and deletes an account with everything in it.
  - It only appears for an admin, and the server checks again on every action —
    an ordinary account cannot reach any of it.
  - Safety rails on the things you cannot undo from inside the app: you cannot
    delete your own account, cannot revoke the token you are using right now,
    and cannot delete another admin without dropping their admin first.
- **One token per device — optional, not required** — the same token works on as
  many devices as you like. Splitting them buys two things: a lost phone can be
  revoked without re-entering anything on your other devices, and the listing
  shows which device is actually syncing. "Add a device" issues another.
- **Tokens are stored hashed**, so a token is shown exactly once, when it is
  issued. If one is lost the fix is to issue another and revoke the old.
- **Nothing changes for an existing setup** — the token the server has always
  printed keeps working and keeps pointing at the same data; it is simply the
  first account, and now an admin one.
- **Also from the command line** — `npm run token -- add "Alice"`, `list`,
  `revoke <token-id>`, `admin <user-id> [on|off]`. Same operations as the panel,
  and the way back in if nobody can sign in at all.

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

Wishes with no design behind them yet. Once one has a shape, it moves to
`ROADMAP.md` and leaves this list — **arbitrary date/time and recurring
reminders are both there now**, queued for 0.18.0.

- Light theme / theme toggle.
- Configurable shortcut combinations (currently fixed at Ctrl+Alt+T / Ctrl+Alt+H).
- **Syncing attachment bytes.** Needs a second channel beside the JSON sync —
  `PUT/GET /blob/:sha256`, content-addressed, plus an upload/download queue with
  its own retry and progress. The metadata layer is built for it already: the
  digest is the address, and "not on this device" is the state it would clear.

---

## Changelog

- **0.23.1** — **Fixes.** An edit made on a device in another timezone could
  lose to an *older* edit made elsewhere, and lose silently. Timestamps were
  written as a bare wall-clock reading with no timezone on it, so "which of
  these two edits is newer" was answered by comparing the two clock faces:
  a phone in New York editing at 09:30 lost to a desktop in Madrid that had
  edited half an hour *earlier* at 15:00. Stamps now carry their offset and
  both the app and the server compare them as real instants. Existing rows are
  unaffected — the clock-face part of a stamp is unchanged, so nothing reorders.
  **The action bar on a phone no longer runs off the edge of the screen.** A
  task with a reminder, a flag, an attachment, a plan and notes asked for nine
  finger-sized controls on a row about 340 units wide; the last of them, delete,
  was clipped. The bar now starts at the edge of the row rather than indented
  under the title, which is a whole control's worth of room back, and wraps to a
  second line rather than shrinking targets below a fingertip when even that is
  not enough.
  **Quick add no longer loses an afternoon's planning to the wrong control.**
  Blocks laid out with the bolt were written when the bolt went off, but turning
  the mode off from the calendar strip instead left them behind with nothing to
  belong to, and closing the calendar then discarded them; switching the strip
  to another calendar filed them under that one's name. Committing now happens
  wherever the target changes, so there is no way out of the mode that drops
  them.
  **Dragging a quick-add block works again.** Long-press-dragging one moved it
  by the whole distance travelled *on every frame*, so it shot away from the
  finger, and the grip at the bottom ignored anything slower than a flick.
  **Android builds again.** The build had been failing outright - reminders need
  library desugaring switched on, and the Gradle plugin the project had moved to
  cannot compile several of its own dependencies. Nothing caught it because CI
  builds iOS only.
  Also: the sync event stream no longer reports a connection that arrives after
  it was told to stop, and the two date pickers no longer risk a crash when the
  sheet under them closes first.

- **0.23.0** — **The calendar fits on a phone.** Its toolbar was one row trying
  to hold nine controls across 390pt, and what got squeezed was the label saying
  where you are — "August 2026" showed as "Au…". It is two rows on a phone now:
  the date and the way through it on one, the quick-add bolt, D/W/Y and the
  filter on the other, each a finger-sized target instead of a 24px one.
  **Swiping left and right switches day, week and year.**
  **Quick add lays out a week without an editor between every block.** With the
  bolt on, tapping the grid drops an hour where you tapped — as an outline, not
  an event, because nothing is written yet. Keep tapping, then drag blocks to
  move them, drag the grip at the bottom to change their length, and tap one to
  take it back. Turning the bolt off writes them all, titled after the calendar
  they were placed on. Leaving the calendar or switching view writes them too:
  there is one rule, so a block you laid down is never lost by leaving in a way
  you did not think of.

- **0.22.1** — **Navigation moved to where the thumb is.** The four content
  views — Tasks, Notes, Parked, History — are a bar of icons along the bottom
  edge on a phone, instead of a ▾ menu at the top corner that hid which views
  even existed. **Swiping left and right** moves between them in the same order,
  so the bar says what there is and the swipe is the cheap way through it.
  Tasks is an entry in its own right rather than "nothing selected": the way
  back should be as visible as the way in. The ends do not wrap.
  **Writing a side thought no longer shows everybody your tasks.** The moment
  this feature is most used is the one that matters — someone recommends a book
  and you pull your phone out — and the inline field left the whole workspace on
  screen behind the keyboard. On a phone it now takes the screen: nothing but
  what you are writing, with "Save & another" for when the recommendations keep
  coming.
  **A note opened for reading or writing gets the screen too**, instead of a
  paragraph of text squeezed between the workspace pill, the view bar and the
  footer. And the permanent **+ for a new workspace is gone** from the bar,
  where it spent a slot next to controls used constantly; it is now
  "Add workspace…" at the bottom of the workspace menu, which was already the
  place that answers "which workspace".

- **0.22.0** — **Every action on a task is reachable with a thumb.** On a phone
  the row's controls were drawn behind a hover state, and a fingertip does not
  hover — so setting a reminder, flagging, parking, focusing, attaching and
  deleting were not small, they were *absent*, with no gesture that would ever
  reveal them. Touch now gets those actions as a real bar under the task title,
  always visible and finger-sized, and **tapping a task expands it in place** to
  show its notes rendered rather than previewed on one line. Editing moved to
  its own pencil, since the tap it used to use now does something better. The
  mouse is untouched: nine controls still fit across a 340px window precisely
  because they stay invisible until the pointer is on the row.
  **The task editor stopped looking like a different application.** It was an
  `AlertDialog`, so it arrived as a small grey card in the middle of the screen
  in stock Material purple and blue, cropped by the keyboard, with the priority
  row cut off. It is now drawn from the same tokens as Settings, in the
  workspace's own colour: full width and against the bottom edge on a phone,
  a centred column on a desktop, pushed clear by the keyboard rather than
  covered by it. Settings, the sound sheet and the block sublist now **slide up
  and back down** instead of appearing and vanishing between two frames, all on
  one shared duration — and the title bar's calendar, settings and headphone
  buttons are finger-sized on touch, where they used to be 27pt targets.

- **0.21.0** — **Sync tells you when something changed instead of waiting to be
  asked.** The 60-second poll was the only thing that ever noticed a change from
  another device, so ticking a task off on the phone left the desktop stale for
  up to a minute. The server now keeps an open event stream per running device
  (`GET /api/events`) and, whenever a push actually writes rows, tells that
  account's *other* devices; they run the sync they would have run anyway. The
  stream carries no rows at all — deliberately, so there is still exactly one
  path data takes into the database and one place conflicts are resolved — which
  is also why losing the connection costs latency and nothing else. The poll
  stays underneath as the backstop, the device that pushed is left out of its own
  broadcast, and a server without the route turns the feature off rather than
  becoming a client that retries forever. Behind a reverse proxy it needs one
  line of config (`flush_interval -1` in Caddy, `proxy_buffering off` in nginx);
  without it, sync degrades to exactly the old behaviour rather than breaking.
  **A device now knows which server its rows were accepted by.** The `dirty`
  flag only ever meant "*a* server has taken this row", which is the same thing
  as "this server has taken it" right up until the server changes — and then it
  is silently wrong in the worst possible way. Repointing the app at a rebuilt
  database left every local row simultaneously already-sent here and unheard-of
  there, so nothing pushed them, ever; only rows edited afterwards went up. Both
  ends stayed internally consistent, neither reported a problem, and a second
  device set up against the new server dutifully pulled the fragment and looked
  like sync was working. Two independent signals now catch it: the server's
  cursor going *backwards* (impossible on a database that issued the old one) and
  a stored fingerprint of the server address and account. Either one re-arms
  every local row for upload. A re-arm that turns out to be unnecessary is
  free — the merge already resolves ties in favour of the incumbent, so an
  in-sync database writes nothing and wakes nobody.
  **The concentration sounds keep playing when the phone locks.** iOS gives an
  app that never says otherwise an audio session the lock switch silences, which
  is right for a game and wrong for the one thing here whose whole job is to run
  while you are not looking at the screen. The app now claims the playback
  session and the background-audio entitlement — but only *activates* it when
  you actually press play, so launching the widget does not stop your music.

- **0.20.0** — **The pin stays pinned.** Always-on-top is a Windows style bit
  (`WS_EX_TOPMOST`) and it was set exactly once, at startup — but it is not ours
  alone to hold: another application going full screen makes Windows strip it
  from everyone else, and nothing restores it when that application exits.
  Closing Windows Photo Viewer therefore left the widget an ordinary window that
  still said "pinned", behind everything, until the app was restarted. It is now
  *re-asserted* rather than set: the reminder poll already had a clock, so it
  checks the bit and puts it back when it has gone, and clicking onto the widget
  repairs it at once instead of up to twenty seconds later. Read before written,
  because the underlying `SetWindowPos` also activates the window and doing that
  every twenty seconds would be its own bug.
  **Tasks move onto a shelf and off it again without a menu.**
  With the window wide enough for the parked panel to sit *beside* the list
  (`Layout.splitsContent`), a task can be **dragged out of the list onto a
  group** — the same gesture, and the same drag source, that already plans a
  task into a calendar block, which is why there is now one `Draggable` and one
  `TaskDropTarget` between them rather than a second copy of each. The group
  lights up under the pointer and **opens when the task lands**: on a collapsed
  shelf the only other visible change is a count going up by one, which is too
  quiet an ending for a gesture. Narrower windows are unchanged and keep the 📥
  picker — no size takes a feature away, but a shortcut that needs two things on
  screen at once needs them on screen.
  Going the other way, **↗ on a group header puts the whole shelf back onto the
  list**, behind a confirmation that names the count: one press moving a dozen
  rows with nothing to undo it is exactly the case a modal is for. The shelf
  survives (that is what makes it different from deleting the group, which also
  releases its tasks), the order it held is preserved, and anything checked off
  while parked stays checked off. The per-task ↗ is unchanged.
- **0.19.0** — **Markdown, with maths, wherever there is more than a line to
  write**: a task's notes, a journal entry's body, a calendar event's
  description. The dialect is **GitHub Flavored Markdown** including its maths —
  `$…$` inline, `$$…$$` and ```` ```math ```` on their own, rendered as real
  LaTeX. Deliberately not a dialect of our own: notes arrive pasted from
  somewhere else as often as they are typed here, and the useful property is
  that they already look right when they land. The `$` rules are pandoc's, so
  "it costs $5, or $7 with tax" is still money and every note written before
  today reads the same as it did.
  Rendering something that was only ever a text field needs somewhere to put it,
  and the answer is a **read state** rather than a split preview — half of a
  340×480 window is not enough for either pane. Notes and journal entries now
  *open rendered* and take a pencil (or a tap on the text) to edit; something
  with nothing in it yet still opens straight into the field, so Ctrl+D and the
  ✎ both put the caret exactly where they used to. The event details card was
  already the read-only half of a read/write split, so its description simply
  renders.
  The journal's editor also grew the keys it was missing: **Ctrl+Enter** from
  the title to the body, **Ctrl+S** to save and read, **Ctrl+Alt+S** to save and
  go back to the list. Esc now walks back down a ladder — editor, reader, list,
  tasks — instead of out of one door.
  Previews stay previews: the notes line under a task title and an event's
  description in the agenda are *flattened* to their words, so a note that opens
  with a heading no longer previews as `## Trip`. No schema change — this is
  entirely how the text already in the database is drawn.
- **0.18.0** — **Reminders that say when, and keep saying it.** Two changes,
  both about a reminder being able to express what you meant.
  **An exact date and time**, from the foot of the reminder menu or the *Pick…*
  chip in the composer. This was in the backlog for a long time behind the
  objection that a date picker wants roughly this whole 340px window — which
  the calendar had already disproved, since the year view draws one to three
  month grids side by side in it. So the picker uses *that* grid, lifted into
  one place both now share: a second month grid that disagreed with the first
  about where a month starts would be a bug nobody would think to look for.
  **Recurring reminders** — every day, weekday, week, month or year. Checking
  one off completes that row into History and lays down the next occurrence as
  a new task, because an occurrence is a todo in its own right; that is what
  lets a daily task be done today and still due tomorrow without History having
  to learn anything new. The successor's id is *derived* from the one before it
  and the moment it is due, so two devices that both see the completion produce
  the same row instead of two. Wall-clock arithmetic, so 09:00 stays 09:00
  across a daylight-saving change, and a monthly task on the 31st clamps to the
  end of a shorter month rather than sliding into the next one.
  Adds `recur` to `tasks` (schema v12; client and server both migrate in
  place).
  Also fixes three things found reviewing 0.17.0: Ctrl+Enter in the task
  composer never fired, Sound and Settings opened *underneath* an open sublist,
  and tapping the "Now" tile of a block with nothing planned into it could
  switch workspace and then open nothing.
- **0.17.0** — **The list and the calendar, pointed at each other.** Six
  changes, five of them on the seam between the two.
  **The calendar opens beside the task list** on a window past ~810px instead of
  taking it over, and a task can be **dragged straight onto a block** to plan it
  into that block. Not a mode: it is a threshold like every other adaptation
  here, and a drag towards the calendar is the one gesture that means "plan
  this" — dragging down still scrolls, the ≡ handle still reorders.
  **Clicking a calendar entry now reads it** rather than opening the edit form:
  a details card saying when it runs, for how long, whose calendar it is on,
  what is planned into it and what is attached, with Edit / Todos / Delete named
  on it. **Right-click, or long-press on a phone**, skips the card and offers
  those directly — on the grid, the multi-day band and the agenda alike.
  **A block can be given a list of its own.** The "Now" tile switches to the
  block's workspace when you press it, and when the running block has nothing in
  it the tile offers **Sublist** instead of opening an empty view: an add field
  for todos that only exist because of that block, with the rest of the
  workspace's list folded underneath, one tap each to take one in.
  **Ctrl+D opens the long form of a task** — notes, a priority flag and a
  reminder in one place, carrying over whatever was already typed and landing
  the caret in the notes box. The ⤢ in the add field is the same door for a
  phone. Notes preview under the task's title and clicking the title reopens the
  form, so they are readable rather than write-only.
  **High priority**: ⚑ on a row flags it, drawn as a red bar down the leading
  edge plus a red border — a separate channel from the overdue red and the focus
  tint, so a task can be all three at once. It does not reorder anything.
  Adds `notes` and `priority` to `tasks` (schema v11; client and server both
  migrate in place).
- **0.16.1** — **The week is a week on a phone too.** It used to fall back to
  the stacked agenda at anything under ~470px, which is every phone — so an
  iPhone never saw the actual grid. The grid now has a compact shape (narrow
  hour gutter, weekday initials, title-only blocks) and seven columns of ~45px
  fit at phone width, which is what every phone calendar shows. The agenda is
  still there for the widget squeezed below ~300px.

  **Clicking a calendar event no longer creates one as well.**
  Opening a block in the day or week grid also dropped a fresh 15-minute event
  underneath the editor — in time-block mode it was saved outright, so tidying
  up a week left a trail of stray blocks. Creating now sits below the blocks
  rather than around them, so a click on an event only opens it and a click on
  empty grid still creates.

- **0.16.0** — **Todos belong to blocks of time now, and "Now" shows you the
  ones you are in.** Open a calendar event and tick tasks from the workspace's
  list to plan them into it; the event's blob then carries a count, and the task
  keeps its place on the list with a small calendar mark. When a block is
  running, a banner above the list says what it is and what is left on it, and
  opening it gives a view of *only* that block's todos with a countdown to its
  end. It appears when a block starts and goes away when the last one ends,
  because for most of the day there is nothing for it to say. Deleting a block
  releases its todos rather than taking them with it.

  Schema v10 on both sides (`tasks.event_uuid`) — an older sync server picks the
  column up on start, and an older client simply sees tasks that are not planned
  into anything.

- **0.15.2** — **Time-block mode**, for laying out a week in one sitting. ⚡ in
  the calendar header puts a strip of calendar chips under it; pick one and every
  drag saves a block straight away, titled after that calendar, with no form in
  between. The draft under the pointer wears the target's colour and name so you
  can see what you are about to write. Switching target is one tap; ⚡ again
  leaves the mode, and a block that needs more than a span is still one tap away
  from the full editor.

  Also: **month tiles in the year view are all the same height** — every tile is
  drawn on a six-week grid whether its month needs one or not, so a 4-week
  February no longer leaves a hole beside its neighbours. And **closing says it
  is closing**: the teardown of the window is not instant, and the widget now
  dims with a spinner instead of appearing to ignore the ✕.

- **0.15.1** — **Fixed the duplicate "Tasks" workspaces.** Every fresh database
  seeded its first workspace with a freshly generated id, so a new phone, a
  reinstall or a test run each produced a *different* row that happened to be
  called "Tasks" — and sync, correctly, kept them all, because they were never
  two versions of one row. The seeded workspace now has a fixed id, so every
  device that starts fresh seeds the *same* row and they merge into one. On
  upgrade, the duplicates already on your devices are folded together: their
  tasks, notes, shelves and events move onto the surviving workspace and the
  empties are removed, which then syncs to your other devices. A workspace you
  renamed or recoloured is yours and is left alone.

- **0.15.0** — **The sync server takes more than one person, and you invite them
  from the app.** Each access token now belongs to an account, and every row is
  scoped to the account that pushed it, so someone else gets their own tasks,
  journal and calendar on your server rather than a second seat at yours.
  Whoever holds the token the server prints is its admin: Settings grows a
  *People on this server* panel that adds an account, shows its token once to
  hand over, lists who is on the server and when each device last synced,
  revokes a token and deletes an account. Tokens are stored as hashes — printed
  once, never recoverable — and can be one per device, which is optional but
  means a lost phone is revoked on its own. `npm run token` does all of it from
  the command line too, for when nobody can sign in.

  Existing setups are untouched: the token the server has always printed is now
  simply the first account's, still pointing at the same data. Also fixes a
  cursor that would have made every client sync pointlessly whenever a
  *different* account wrote; each account's cursor is now its own.

  **Settings is a sheet now, not a dialog.** It used to be a modal route, whose
  barrier covered the title bar — so with Settings open the window could not be
  dragged, pinned or closed, and its contents were squeezed into a smear at
  short window heights instead of scrolling. It now sits below the title bar
  like the sound sheet, leaving the bar live, and its body scrolls.

- **0.14.0** — **The layout adapts to the window instead of the window adapting
  to the layout.** Opening the calendar used to resize the widget to 920×640 and
  centre it, which fixed the week grid by moving the window: a widget pinned to
  a corner jumped into the middle of the screen at a size nobody chose. It no
  longer touches the window. The views change shape instead — the week falls
  back to a stacked agenda when seven columns would be unreadable, and the year
  reflows from four months across down to a single column, which is how twelve
  months fit in 340px. Both come back as grids the moment there is room.

  The same idea runs the other way at the top end: past ~560px the workspace bar
  unrolls into a side rail with every workspace and every view permanently on
  screen, and past ~900px Notes, Parked, History and the thoughts pile open
  *beside* the task list rather than covering it. The task column and the focus
  tile are capped, so the extra width buys more at once rather than longer
  lines. All of it comes from one place (`layout.dart`) rather than each view
  picking its own breakpoints, and none of it is a platform check — a 400px
  window behaves the same whether it is a phone or a shrunken desktop widget.

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
  rather than two; and on desktop the widget grew to fit the grid and shrank
  back on the way out, because a seven-column week does not fit in 340px —
  replaced in 0.14.0 by views that fit the window instead.

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
