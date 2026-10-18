# Todo Widget — Features

A running list of everything the app does. Kept up to date as features land.
Newest changes are noted in the changelog at the bottom.

## Tasks

- **Add a task** — press **Add a task** at the top of the list (or the **＋**
  on the dock, or **N** on the keyboard). The line lifts off the list and flies
  to the middle of the window as a **card**, growing as it goes, with the list
  dimmed behind it. Type, and press **Enter** (or the filled ↑) to add it and
  put the card away; **Ctrl+Enter** adds it and keeps the card open for the
  next one, and **Shift+Enter** starts a new line. On a phone the keyboard's
  Done adds and closes. Enter on nothing, Esc or a tap on the dimmed list
  puts it away. Whatever was typed is kept: the line at the top of the list
  shows it, and opening the card again carries on from it. The line is there
  on every screen size, because the way to do the commonest thing in the app
  should be where the task will appear, not across the window in the dock.
- **The card's buttons**: ⚑ marks it high priority, the 🔔 sets a reminder
  (the same presets and date picker as a task's own), the coloured dot picks
  the **workspace** it goes into, and **⤢** (or Ctrl+D) opens the long form
  with everything set so far carried over. Picking another workspace keeps the
  list where it is and the card says where the task went, since it will not
  appear on screen; the choice lasts while the card is open (Ctrl+Enter).
  Priority and the reminder reset after each task.
- **Settings typed into the title.** Write a **#workspace**, a day or a
  time in the title and it is read as that setting: *call the bank tomorrow
  9:30 #Work* goes onto Work as *call the bank* with a reminder at 09:30
  tomorrow. What was recognised is highlighted in the field and shows on its
  button; the **×** on that button keeps the word in the title instead, and
  choosing that setting with its button does the same. The rules:
  - **Workspaces** need the **#**: *#Work*, *#Master thesis*, any case. A
    name without it is just a word, so *Work on the report* stays as it is.
    The longest name that fits wins, and only one is read per task.
  - **Shortcuts.** Point at a recognised *#workspace* (or put the caret in
    it, on a phone) and a **＋ Shortcut** pill appears under it: give
    *Master thesis* the shortcut *MT* and from then on *#MT* does the same
    as *#Master thesis*. A shortcut is one word and cannot be another
    workspace's name or shortcut. They sync, and the workspace's edit form
    lists them with a × to remove one.
  - **Times** need a colon, am/pm or *Uhr*: *14:30*, *9:30pm*, *3pm*, *um 16
    Uhr*, *at 9:30*, *noon*. A bare number is never a time, so *buy 2 eggs*
    stays as it is. *in 10 min*, *in 2h* are a reminder that far from now.
  - **Days**: *today*, *tomorrow*, *tonight* (18:00), *heute*, *morgen*,
    *übermorgen*, weekday names in English or German (*Friday*, *am Freitag*,
    *next Monday*), *in 3 days*, *15.10.*, *15.10.2026*, *24/12*,
    *2026-12-01*, *3 Dec*, *Dec 3rd*. Dates are day first.
  - **A time alone is today**, or tomorrow once that time has passed — a
    reminder in the past would fire the moment it was written. **A day alone
    is 09:00** that day (or the next whole hour, if that has passed).
  - A title made of nothing but keywords is kept as the title.
- **Links show as the page's title.** A web address in a task's title is
  drawn as the title of the page it points to (underlined, in the accent
  colour), and clicking it opens the page. The task itself still holds the
  address - edit the task and it is there. Each address is looked up once
  per device and remembered; until then the row shows the address shortened.
  The browser build asks the sync server, the apps ask the page directly.
- **Check off a task** — click the circle; it plays a slide-out animation, then
  gets logged to history (not deleted).
- **The actions live in a bar you ask for.** A row is a tick box, a title and
  whatever the task is carrying — nothing else. **Right-click it** with a mouse,
  or **tap its text** with a finger, and the row's actions appear as a floating
  bar over it: remind, flag, attach, unplan, park, focus, expand, edit, delete.
  They used to be drawn on the row itself — invisible until hovered on a
  desktop, and a permanent second line under every row on a phone — which meant
  that in a narrow window most of a row's width belonged to controls that were
  not on screen, and that the smallest screen in the house spent a line per task
  on buttons. The bar is drawn at the size the pointer needs, because it is no
  longer competing with the title for room.
- **Double-click a task to edit it** (mouse only). A single click still
  expands the row to read it, and the pencil in the action bar still opens the
  same editor — this is the shortcut for the case where you already know what
  you want to change. It leaves the row as it found it: the expansion the first
  click opened is put back, so nothing is waiting behind the editor when you
  close it. The single click does **not** wait to find out whether a second one
  is coming, so reading a task is as immediate as it ever was.
- **Delete a task** — the ✕ in that bar removes it *without* logging (a plain
  dismiss).
- **Empty state** — friendly "Nothing left" message when the list is clear.
- **Park a task, or move it** — the 📥 in the bar opens a picker of where it
  can go: this workspace's parked groups (see below), or **any other
  workspace** — onto its list, or onto one of its shelves. A task typed while
  the wrong list was on screen no longer has to be deleted and typed again.
- **Select several and act on them together** — **Ctrl+click** rows with a
  mouse, or pick **Select** in a row's action bar on a phone. Once one is
  selected, a plain click (or tap) on another adds it, and the add field turns
  into a bar saying how many are selected with **Done**, **Park or move** (the
  same picker, applied to all of them), **Delete** (asks first) and ✕ to clear
  — as does Esc. Selected rows are drawn in the workspace colour. Where the
  parked panel sits beside the list, dragging one selected row onto a shelf
  takes the whole selection with it. Switching workspace ends the selection.
- **Attach a document** — the 📎 in the bar; see Attachments.
- **Expand a task and read it** — ⤢ in the bar, or simply **left-click the
  title** with a mouse. The task opens *read-only*: its notes rendered as
  Markdown — headings, lists, links, maths — and a line of chips for everything
  the row can only hint at, so "Reminder tomorrow 09:00", "Every week", "Planned
  into a block", "2 documents", "Added 3 Sep 2026" are spelled out rather than
  standing for icons. Nothing in it can be changed; the pencil is next door if
  that is what you wanted. On a desktop the row **grows in place** and the list
  scrolls past it, so the tasks above and below stay where they were. On a phone
  it takes the **whole screen**, the way an open note does, and the back arrow —
  or Esc — collapses it.
- **Reorder the list** — with a mouse, drag the ⠿ grip at the **right** end of a
  row. On a phone there is no grip: **press and hold anywhere on the row** and
  drag it. The grip moved off the left edge, where it was pushing the title of
  every row in the list inwards for the sake of a control only a pointer can
  use.
- **A row still says what it is carrying, without being asked** — a red bar down
  the leading edge of a flagged task, a bell once a reminder is armed (red when
  it is overdue), a 📎 when it holds documents, a 📅 when it is planned into a
  calendar block. Those are marks, not buttons: pressing anywhere on the row
  opens the bar, which is where the matching action is.
- **The long form — Ctrl+D, or the ⤢ on the add card.** Opens a bigger
  composer for the task that needs more than a line: **notes**, a **priority
  flag**, a **reminder** and a repeat, all set before it ever reaches the list.
  The card's title (keywords taken out), priority, reminder and workspace come
  across and the caret lands straight in the notes box, so the shortcut never
  costs you what you had set. Cancelling leaves the card exactly as it was.
- **Notes stay readable.** A task carrying notes previews their first line under
  its title; expanding the row shows all of them, rendered. A note you can only
  write is a note you will not write.
- **Notes are Markdown, and open rendered.** Reopening a task that already has
  notes shows them formatted, with an *Edit* toggle (or a tap on the text) back
  to the raw source; a task with no notes yet opens straight into the field, so
  Ctrl+D still puts the caret where you were about to type. See **Markdown &
  maths**.
- **High priority** — the ⚑ in the action bar flags a task: a red bar down its leading
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
- **A task carrying documents shows its 📎 on the row**, tinted in the
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
- **And it can be resolved by hand: “Locate”.** On a row whose bytes never
  arrived, the 🌐 button asks for that file on this device and adopts it — the
  entry lights up, opens, and behaves as if it had always been here. It is safe
  because the row already names its bytes by digest: the file you pick is
  *checked*, not trusted, so it can be a copy under a different name and still
  be recognised, while a different document is refused and offered as a new
  attachment instead. Nothing about the row changes, so nothing syncs — this is
  one device catching up with itself.
- **Orphaned files are swept at startup** — a row tombstoned on another device
  arrives as a merge, never as a local delete, so its bytes would otherwise sit
  on disk forever.
- The stored digest is already the address a future blob-sync endpoint would
  fetch by, so adding one later needs no migration of what is on disk.

## Parked groups

Titled shelves inside a workspace — "Backlog", "Future ideas", "Someday" — for
tasks you are deliberately not doing now. Unlike side thoughts these are
**per-workspace**: a backlog is a property of the thing you are working on.

- **Review from the shelf's header** — every shelf carries a **Review** button
  on its title row, lit in the shelf's colour when a review is due. It opens the
  one-todo-at-a-time review directly; there is no need to expand the shelf
  first.
- **Open them** — "Parked" in the dock's second part (where you are) swaps the
  content area for the parked view, the same way History and Thoughts do. Click
  the "← Parked" header, press Esc, or pick "Parked" again to go back.
- **Park a task** — the 📥 in a task's action bar opens a picker of this
  workspace's groups, plus "New group…", which creates one and parks straight
  into it.
- **Or drag it there.** When the window is wide enough that the parked panel
  sits *beside* the list rather than replacing it, a task can be dragged
  sideways out of the list and dropped on a group. The group lights up while the
  task is over it and opens when the task lands, so you can see where it went
  rather than watching a count tick up on a closed shelf. Any group is a target,
  open or collapsed or empty — the collapsed ones are exactly what you are most
  likely putting something away into. A vertical drag still scrolls and the ⠿
  grip still reorders; only a drag *towards the panel* means "put this away".
  Narrower windows keep the 📥 picker, which works at every size.
- **Or add straight to a shelf.** Every open group has a one-line field at the
  foot of its own list — "Add to Backlog" — and Enter drops a new task onto that
  shelf without it ever touching the current list. This is the commonest thing
  anybody does with a backlog: think of something that is explicitly *not* for
  today and write it down. Doing that used to mean adding the task, finding it
  again, and parking it — three steps to record that you are not doing
  something. The field keeps the caret after each Enter, because these arrive in
  handfuls.
- **Unpark one** — ↗ on a parked task puts it back at the *bottom* of the current
  list. ✓ checks it off from where it sits, straight into history.
- **A task coming off a shelf keeps the shelf's name** — "Todo Widget: bigger
  buttons" — whichever way it leaves for a list: its ↗, the shelf's ↗, the move
  picker, the review, or the shelf being deleted. On the shelf the shelf was the
  context; on a list of fifty it would be gone. Moving shelf to shelf leaves the
  title alone, and an existing prefix is never doubled.
- **Finger-sized controls.** The shelf's ↗, ✓ and ⋯ are full tap targets on a
  phone, and the shelf's tasks are at body size rather than in small grey.
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
  "review due", and the dock's second part gains a red dot,
  which is the only sign visible while the panel is closed. Opening the panel
  expands every overdue group automatically.
- **Reviewing is a funnel, not a button.** "Review" on a shelf's header takes over
  the pane and shows **one task at a time**: its title, its notes, how long it
  has been sitting there ("parked 47 days ago"), an armed reminder, and a
  progress line — "3 of 11", with a dot per task. Four answers, and exactly one
  of them leaves the task where it is:
  - **Keep** — still parked. Also the **Enter** key, because the safe answer
    should be the cheap one.
  - **Do it now** — back onto the current list.
  - **Done** — checked off from here, into history.
  - **Drop** — deleted.

  You cannot reach the end without answering for every task, and **reaching the
  end is what restarts the clock**. Leaving early (Esc, or the back arrow) keeps
  every decision you already made and does *not* restart it — a shelf you got a
  third of the way through has not been reviewed. This replaced a "Mark
  reviewed" button that sat under a collapsed list of one-line rows: it was
  reachable without having read any of them, so the shelves it existed to keep
  out of landfill went to landfill anyway, with a fresh timestamp on them. An
  empty shelf is reviewed by looking at it — there is nothing to answer.
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
- **Ambience** — café, rain, city, forest, train and sea, from the Internet
  Archive's `radio-aporee-maps` collection: thousands of field recordings, all
  CC0 or public-domain-mark. Each preset is a *query*, not a fixed file, so
  tapping the same button again gives you a different café.
  - **Thirty minutes of it is kept on the device**, which is the tier that used
    to stall. A recording is finite and then looped for an hour, so every
    re-buffer was paid for over and over; a stored **bout** — the first 30
    minutes of one recording — starts instantly, cannot stall, and needs no
    network at all. Half an hour is already far longer than any sitting, and it
    is a bound, which a directory of four-hour recordings is not.
  - **Nobody waits for it.** A preset with nothing stored streams exactly as it
    always did and files a bout behind itself, so the cost is one extra
    download the first time or two a preset is used and nothing afterwards.
  - **The variety survives.** A couple of bouts are kept per preset and one is
    picked at random, because "a different café every time" is the entire
    reason a preset is a query. A preset that has one shows *on this device*
    under its name.
  - **A switch and a size**, at the foot of the Ambience list: *Keep 30 minutes
    on this device*, how many bouts are stored and roughly how much disk they
    are using, and **Clear** (which asks first — it is minutes of downloading
    and there is no undo). Turning the switch off plays as before and leaves
    what is already stored alone; those are two different acts and the sheet
    offers both.
- **Radio** — live stations from the Radio Browser directory, browsable by
  genre: ambient, drone, dub techno, minimal, techno, lo-fi. Near-duplicate
  entries for the same station are collapsed, and offline stations are filtered
  out. The three things the directory asks of clients are all honoured: a
  descriptive user agent, no hardcoded server (it falls through the documented
  mirrors), and plays reported back so its rankings stay accurate.
  - **Search** — the field above the genres searches the whole directory by
    station name ("fip", "soma", "jazz").
  - **Star a station** to keep it. **★ Saved** lists what you starred, and the
    radio tab opens there whenever anything is saved.
  - **Add a stream URL** at the foot of Saved, for a station the directory does
    not have; the name is optional. A hand-added stream is removed with its ✕,
    and its plays are not reported to the directory, which has never heard of
    it.
  - Saved and hand-added stations are kept on this device, like the volume.

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
- **Repeat it** — *Every day / weekday / week / month / year* as chips in the
  composer, and everything else behind **Repeat…**. Checking a recurring task
  off logs the one you finished to History like any other completed task and
  lays down the next occurrence; an occurrence is a todo in its own right,
  which is what lets a daily task both be *done today* and *still due
  tomorrow*.
  - "Every day at 09:00" stays at 09:00 across a daylight-saving change: the
    next occurrence is worked out in wall-clock terms, not by adding 24 hours.
  - A monthly task on the 31st lands on the 30th, or the 28th, rather than
    sliding into the next month. Same for the 29th of February, yearly.

  The **Repeat…** panel is the rest of it, and it asks two questions.

  **Measured from** — *on a schedule*, or *after it is done*.
  - *On a schedule* is the calendar's rhythm, kept whatever you do about it, and
    it is measured from the reminder (so a scheduled repeat needs one).
  - *After it is done* counts from the tick. "Clean the kitchen every two
    weeks", created on the 1st and actually done on the 8th, comes back on the
    22nd — not the 15th. Being late moves the series instead of leaving you
    behind it, and this kind needs no reminder at all: coming back onto the list
    is the whole of the nudge. It can never pile up.

  **The next one appears** — only a scheduled repeat gets to answer this, and
  the answer is what decides whether a repeat can pile up.
  - *When the last one is done* — the old behaviour, and incapable of piling up:
    there is at most one open occurrence, because making the next needs
    finishing this one. Right for a stand-up.
  - *When it is due* — created on the day, ticked or not. This is the
    rule-based half: "Send working hours to management" appears on the last day
    of every month whether or not last month's was ever sent, and a month you
    did not answer for stays on the list beside the new one saying so.
  - *A day / three days / a week before* — created early, with the due date
    still the rule's.

  **Rules a due date cannot say**, also in that panel:
  - **The last day of the month.** Not the same as "monthly" from the 31st,
    which clamps to 28 February and then, walking on from there, stays the 28th
    for ever.
  - **The first / second / third / fourth / last <weekday> of the month** —
    "first Monday", "last Friday".
  - **Every *n* days, weeks, months or years** — every three days, fortnightly,
    every six months.

  **Variables in the title and notes.** `$(month)`, `$(mon)`, `$(mm)`,
  `$(year)`, `$(yy)`, `$(day)`, `$(dd)`, `$(weekday)`, `$(wd)`, `$(date)`,
  `$(week)`, `$(quarter)` — so "Send working hours for $(month) to management"
  arrives as *September* in September and *October* in October. Offsets work
  too: `$(month-1)` is the month before, which is what "last month's hours, on
  the first" needs. Each occurrence is **written out once, against its own due
  date**, so what is in History stays what it said; the unexpanded form is kept
  behind the row and is what the composer shows you when you edit it. An
  unrecognised name is left exactly as typed.

  **Stopping a repeat** is *Once* in the composer. Where there is no open
  occurrence to open — a chore between being ticked and coming back, or a
  scheduled one before its lead — the ↻ beside the task in **History** says how
  it repeats and offers to stop it; the completed row stays in History exactly
  as it is.

  **Catching up.** A device that was off for a long time lays down the most
  recent handful of missed occurrences rather than all of them: 365 stand-ups
  nobody was going to do is not a catch-up. Two devices that both notice the
  same occurrence produce the *same row* rather than two, because an
  occurrence's id is derived from its parent and its own instant.
- **Always visible once set** — an armed bell stays on the row (it is state the
  task is carrying, not an action offered on demand). What it says is in the
  action bar and in the expanded view: "in 26m", "tomorrow 09:00".
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
- **It has its own colour, and it is not a workspace's.** Every other view is a
  view of one workspace and the window is tinted with that workspace's colour to
  say so. The calendar can show every workspace at once, so whenever it is open
  the tint drops out for a neutral grey and the lit controls in the title bar go
  with it — beside the task list as well as full window. Blocks keep their *own*
  calendar's colour — telling them apart is what the week view is for, and a
  window mixed 16% into one of those colours was working against it. Which
  workspace you are in is still on the bar, in the coloured pill that says its
  name.
- **Blocks are solid, and stand up off the grid.** Each event is one block of
  its calendar's colour sitting on a darker edge along its right and bottom,
  with its text in a deep shade of that colour, like everything else on a
  coloured fill. It used to be a pale tint with a saturated stripe down the
  left. **A long title stands up**: when it does not fit across a narrow block
  and the block is tall enough to say more of it sideways, it runs down the
  left edge, top to bottom — "Dentist appointment" in a phone's week column was
  "Den…" lying down. The all-day band and the list view use the same blocks.
- **Drag to create.** Drag down a column from the start time to the end time and
  the event form opens with the times already filled in, so the only thing left
  to type is the title. Drags snap to 15 minutes, and dragging upwards works —
  it is normalised rather than rejected. **The quarter hour you press in is
  where it starts, and the one you let go in is included**: down a few minutes
  past 10, up a few minutes before 12, and it is 10:00–12:00. It used to round
  to the nearest line, so a finger landing at 10:08 started the block at 10:15.
  - On a **phone** it is press-and-hold, then drag: a plain one-finger drag has
    to scroll the day, which is the only way to reach the rest of it.
  - Creating only happens on **empty** grid. A click or press on an existing
    event opens that event and nothing else.
- **Click an event to read it, double-click (or double-tap) to edit it.** The
  details card opens on the first click; a second one straight after turns it
  into the edit form. For its first instant the card ignores clicks, so the
  second half of a double-click can never land on Delete. Subscribed events
  have nothing to edit and just close.
- **Edit mode** (the ✎ pencil in the calendar's header; **Ctrl+E** on a
  desktop) is where blocks are changed by hand: moved, stretched, and laid
  down fast. Outside it a block only opens and a drag only opens the editor,
  so a stray drag across the week cannot move a meeting. It replaced the ⚡
  quick-add mode, and everything that mode did is part of it.
- **Stretch an event by an end.** In edit mode, the top and bottom edges of a
  block are handles: with a mouse the edge lightens as the pointer comes over
  it (and the cursor turns to ↕); on a phone it lightens as you touch it.
  Drag it up or down and the block is drawn at its new length, with the new
  times, over the original (which fades while you drag); let go and the
  block starts or ends there, on the nearest quarter hour. An end cannot be
  dragged past the other one. A repeating event stretches as a whole series;
  one from a subscribed calendar has no handles.
- **Move an event by carrying it** (in edit mode). With a mouse, **drag** a
  block anywhere - another hour, another day; on a phone, **press and hold**
  it until it lifts (it ticks), then drag. An outline under it shows the quarter hour and day it
  will land on, with the new times; let go and it is moved, the same length as
  before. Hold it against the left or right edge to carry it into the next or
  previous week. A repeating event moves as a whole series, by the same
  distance; one from a subscribed calendar stays where its feed puts it. On a
  phone, a held block let go without moving still opens its menu, which is
  what a long press on it always did.
- **The event form and the details card are the app's own panel**, not a
  Material dialog: full width against the bottom edge on a phone, a centred
  card on a desktop, in the colour of the calendar they belong to. On a phone
  the card used to show its title, a Delete button and then a tall empty
  rectangle running to the bottom of the screen, with everything it was meant
  to be answering squeezed out of view.
- **Click an entry to read it; right-click for what to do with it.** A plain
  click opens a **details card** — when it runs and for how long, its calendar,
  its reminder rule, the description, what is planned into it and what is
  attached — with *Edit*, *Todos* and *Delete* named on it. Clicking used to
  open the edit form outright, which answered the rarer of the two reasons for
  clicking and put a form full of live fields one keystroke away from changing
  something nobody meant to touch. **Right-click** (or **long-press** on a
  phone, and let go without moving) skips the card and offers the same actions
  directly. Both work on the
  hour grid, on the multi-day band and in the agenda.
- **Go to the workspace a block belongs to.** When an entry is on a
  workspace's own calendar, the details card and the right-click menu offer
  *Go to workspace*. Beside the task list the calendar stays open and the list
  switches; where the calendar has the whole window it closes onto that list.
- **Laying out a whole week at once** is edit mode too. The strip of chips under
  the header says which calendar new blocks go on ("New blocks on"), and every
  drag on empty grid saves an event straight away, titled after that
  calendar — no form, no dismissing anything. Planning a week is the same gesture
  twenty times over and nineteen of the titles are the same word, so the editor
  in between is twenty dismissals. The draft under the pointer is drawn in the
  target's colour and carries its name, so you can see what a drag is about to
  become. Switching target is one tap on another chip; ✎ again, Ctrl+E, or the
  ✕ on the strip, leaves the mode. Anything a block needs beyond a span — a note, a
  reminder, a different title — is one tap on the block afterwards.
- **A block can run past midnight.** 22:00 to 04:00 is a night, and it is drawn
  as one: two hours at the foot of one day and four at the head of the next,
  cut square where midnight divides them so the halves read as one block. Only
  a block with a whole day *inside* it — midnight to midnight, so a conference
  or a holiday — goes into the multi-day band at the top, since that is the one
  that would otherwise be 24 hours of scrolling past the same thing. Picking an
  end time earlier than the start means the next day, so an overnight block
  takes two taps rather than a trip through the date picker.
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
  - A block with **nothing** planned into it says so and leaves it there:
    planning is choosing among todos you already have, and both ways of doing
    it are in the calendar.
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
- **A block can repeat** — every day, every weekday, every week, month or year.
  Pick the rule in the event form and the block appears on every occurrence,
  with a ↻ on it and its rule named on the details card. It stays **one entry**:
  the occurrences are drawn from the rule rather than written out, so renaming
  a stand-up renames all of them and nothing has to be tidied up afterwards.
  Editing or deleting any occurrence therefore applies to the whole series, and
  both say so — the form under the rule, and a confirmation before a delete
  that names how it repeats. Changing a single occurrence is not in this
  version; it needs somewhere to record the exception, and silently editing the
  series instead would be the version of that you find out about late.
  A monthly block on the 31st stays on the 31st — February does not drag it
  back to the 28th for good — and a 09:00 block still reads 09:00 on the far
  side of a daylight-saving change.
- **A whole day, or a run of days.** An *All day* switch on the event form
  turns off the times and keeps the dates, and the block moves into the band
  above the grid — where a birthday, a public holiday or a week away belongs,
  rather than as a 24-hour column blocking out the day underneath it. The days
  read inclusively: 17 to 22 August is six days off, not five and a midnight.
  All-day blocks do **not** inherit their calendar's reminder rule, because
  "an hour before" means an hour before a meeting — inherited, every birthday
  would wake you at 23:00 the night before. Set a lead on the block itself and
  it is honoured.
- **Notification rules belong to the calendar** — Workout can warn you ten
  minutes ahead while Work warns you an hour ahead — because that is the level
  the answer actually varies at. Any single event can override its calendar,
  including down to silence.
- **On a big window the calendar opens *beside* the list, and you can drag onto
  it.** Past about 810px wide the calendar stops replacing the window: the task
  list keeps the left-hand column (under the workspace's name, with its add field) and
  the calendar takes the rest. **Drag a task onto a block** to plan it into that
  block — the block lights up as you come over it, and letting go is the same
  thing ticking it in the event editor does, reached from where you are actually
  looking at the task. Dragging *down* still scrolls the list and the ⠿ grip
  still reorders it; only a drag towards the calendar means "plan this". Like
  every other adaptation here this is a size, not a mode — there is nothing to
  switch on, and below that width the calendar behaves exactly as it always has.
- **On a phone, swipe to move through time** — the next and previous week in
  the week view, day in the day view, year in the year view. The swipe used to
  change D/W/Y, which is the setting you touch once a session; where you are in
  time is the question you ask twenty times, and it meant reaching for the ‹ ›
  at the top of the screen each time. **The page follows your finger, and the
  next week (or day) is already there beside it**: drag a little to glance at
  what is coming and let go to spring back, or flick / drag past about a third
  of the width to go there. Both neighbours are loaded with the page you are
  on, so the glimpse is never empty, and they are drawn at the hour you are
  scrolled to. The year view slides without a neighbour.
- **On a phone the header is one line**: ‹ the date ›, a chip showing the view
  (D, W or Y — tap it for the next), the ✎ for edit mode (lit while it is
  on), and ⋯. **Tap the date to go back to today.** ⋯ holds Today and the
  calendar filter, new calendar and import. The title bar's calendar button
  closes the calendar. It was three rows; the grid gets that height back.
- **Drag a placed block anywhere, including onto another day.** In edit mode, a long press lifts a block off the grid — it follows your finger as a
  thing being carried — and it lands where you let go, on whatever day is under
  it. Hold it against the left or right edge and the grid moves under it a week
  (or a day, or a year) at a time, which is how a block reaches a day that is
  not on screen. The edges only wake up once the block has been somewhere that
  is not an edge, so picking up Monday's block to move it two hours down does
  not send you back a week.
- **Zoom the day.** Two fingers on a phone, **Ctrl and the wheel** with a
  mouse: an hour gets taller or shorter, from a compressed overview down to a
  day you can drop a 15-minute block into precisely. Whatever is under your
  fingers — or under the pointer — stays where it is while the grid grows
  around it. A plain wheel still scrolls the day, and the zoom is remembered
  per device: it is about the screen in front of you, so it is not synced.
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
- **A repeating event comes across as a repeating block** when the .ics said
  something this app can also say: every day, every weekday, every week, month
  or year, with no end date and no interval. The import list names the rule it
  found.
- **An all-day event stays an all-day event.** A public holiday or a booking
  that covers a date rather than a time used to arrive as a block from midnight
  to midnight; it now comes in as the whole day it was.
- **Anything more elaborate is imported once**, and both the list and the
  resulting description say so — a six-week course, every second Tuesday, the
  third Thursday of the month. Rounding those to the nearest rule this app has
  would be wrong every week rather than once, on a calendar you have started to
  trust.
- Handles what real producers actually emit: folded long lines, escaped commas
  and newlines, all-day dates with their exclusive end, `DURATION` instead of an
  end time, quoted `TZID` parameters, and both CRLF and LF. A malformed event in
  a file of five costs that one event, not the import.
- Times written as UTC are converted; times written without a zone keep their
  reading, which is what a printed ticket means.

## Subscribed calendars

- **Subscribe to a calendar by its address** from the calendar's tune menu:
  paste a `webcal://` or `https://….ics` link (Google: Settings → the
  calendar → *Secret address in iCal format*; Outlook, iCloud and Fastmail
  publish one too). The address is checked first and the form shows how many
  events it found and the next few, so a page link instead of the iCal one is
  caught before anything is written.
- **A new calendar, or merged into one you have.** By default the events get a
  calendar of their own, named after the feed. They can instead go into any
  existing calendar, a workspace's included, beside the blocks already there.
- **Read-only, and stays in step.** Subscribed events cannot be edited or
  deleted here: the card says where they came from. Refreshed every 30
  minutes while the app runs (5 after a failure), or on demand. Moved and
  cancelled meetings, repeat rules of any shape and time zones come across as
  the source has them. A failed refresh keeps what was there and says why.
- **Quiet by default**, since the calendar's own app is probably alerting
  already; a switch per subscription turns notifications on.
- **Subscribing syncs**, so every device has it. Unsubscribing removes the
  feed's events everywhere, and the calendar too if subscribing made it and
  nothing else is on it. Your own events in a merged calendar stay.
- In the browser the sync server fetches the calendar (calendar services do
  not let a web page fetch them directly). It refuses private-network
  addresses unless `TODO_FEED_ALLOW_PRIVATE=1`, and anything that is not a
  calendar.

## Shopping list

One throwaway list - a shopping list, a packing list - behind the basket on the
title bar, beside the calendar. It belongs to no workspace and takes the whole
window while it is open.

- **The app opens on it.** While there is a list, launching the app opens on
  it, and so does every return to it: unlocking the phone, coming back from
  another app or browser tab. Moving around *inside* the app does not: go to
  Tasks and come back when you like. On the desktop widget, which is always
  open, it is launching and bringing the window back from the tray or from
  being minimised that count, not clicking on it. It never takes the screen
  from something being written (an open form, a half-typed task, a thought),
  nor from focus mode.
- **Two modes.** *Use* shows only the items, with large rows: a tap ticks.
  Nothing there edits or deletes. *Edit* has an add field at the top (Enter
  adds and keeps the caret), retitling in place, ✕ to delete, a handle to
  reorder, and the list's name. The big **Edit / Done** button switches; Done
  saves. An empty list opens in Edit, and **stays there while you type the
  list**: Enter, next item, Enter, until Done. It used to drop into Use the
  moment the first item was in.
- **Ticked items slide down** into a greyed *Ticked* section below what is
  left, newest first. Tap one to untick it and it slides back to its place.
- **Finished** archives the list as it is, and the next list starts empty. It
  is the green button once everything is ticked, and quieter before. Finished
  lists are under a small *Archived lists →* at the top: read-only, deletable.
- **Synced**, so a list written at the desk is open on the phone in the shop.
  If two devices each start a list offline, the newer is the list and the other
  shows as "Also open", to merge in or finish. Needs the server updated
  (sync protocol 3); until then the list stays on the device it was written on.

## Collections

Per workspace, beside Notes and Parked: lists where you decide the **fields**
first and then add **entries** - recipes (name, link), movies (title, year,
seen), books, anything kept with the same few details each time. Reached from
the dock (where you are → *Collections*).

- **Four kinds of field**: **text**, **link**, **number** and **checkbox**. A
  link field gets the URL keyboard, a number field the number keyboard (a
  comma counts as a decimal point), a checkbox is a tap. Every value is kept
  as text, so changing a field's kind never loses anything.
- **Adding is typed straight through.** Each field is one line; Enter (or the
  keyboard's Next) jumps to the next field, past any checkbox. Enter on the
  **last** field adds the entry and clears the form with the caret back at the
  top, so several go in one sitting; a line at the top says what was just
  added. *Add* (or Ctrl+Enter) adds and closes; Enter on an empty form closes
  it. Cancel throws away only what is not added yet.
- **A table where there is room**, a column per field: click a header to sort
  on it, again to reverse; a checkbox column ticks in place. **On a phone**
  each entry is a row - the first field large, the others on one quiet line
  under it, a link as its site's name with a ↗ to open it - and the first
  checkbox field is the row's tick box ("seen" ticked off from the list). The
  sort button above does what the headers do.
- **Search** across every field, from the line above the entries.
- **Tap an entry to edit it**, or delete it from there. A link opens in the
  browser from its own ↗.
- **Fields and name** (the sliders button in the header): rename, retype, reorder with the
  arrows, remove, add. Removing a field that has something in it asks first. A
  new collection starts with one *Name* field, or from a starter: *Recipes*
  (Name, Link) or *Movies* (Title, Year, Seen).
- **Synced**, and deleted with their workspace. Needs the server updated (sync
  protocol 4); until then collections stay on the device they were made on.

## History

- **"Done recently" view** — "History" in the dock's second part (where you are)
  shows completed tasks, newest first, each with the date/time it was checked off
  (up to 100). Click the "← Done recently" header or press Esc to go back.
- Completed tasks are preserved across restarts.

## Journal / Notes

A quiet place to write, per workspace — plaintext by default, with **optional**
password encryption. Reached from the dock's second part (where you are):
"Notes". Two things shape it: it is **quiet** (so a glance
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
- **A note being written is never lost.** Leaving the editor any way other than
  Cancel keeps what was typed: switching workspace, opening the calendar, or
  closing the pane from the views menu saves the draft into the workspace it
  was written in. Widening the window until the task list appears beside a note
  no longer resets the pane either — the editor stays open with the caret where
  it was. A draft cleared to nothing is left alone rather than saved, because
  saving empty fields deletes the entry.
- **Per-entry state** — each row records whether it is encrypted, so mixed and
  synced states stay honest: a device without the password shows an encrypted
  row as a **Locked** placeholder rather than garbage, and can still keep its own
  plaintext notes.
- **Title + body editor** — creating an entry replaces the list with a plain
  full-pane editor: a title line, a body area, and **Cancel / Save** (plus
  **Delete** when editing).
- **Opening an entry reads it.** Picking one from the list renders its body as
  Markdown (see **Markdown & maths**) under its title; the ✎ in the header, or a
  tap on the text, turns it back into the two fields. **Double-click** an entry
  in the list to go straight to the fields. A *new* entry skips
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
- **On a phone an open note takes the whole screen** — the dock and the footer
  step aside for it, and the note's own back arrow is
  the way out. It used to *look* like the note refusing to open: the chrome
  disappearing rearranged the widget tree around the pane, which threw away the
  pane's own idea of which rung it was on, and the note snapped back to the list
  one frame after being opened. It stays open now.
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
- **Say a thought.** In the browser build (the iPhone web app, Chrome,
  Edge, Firefox, Safari) the thought pane has a 🎙 button: tap it to record,
  tap again to stop. The recording waits above the buttons - ▶ to listen
  back, × to throw it away - and Save keeps it, with whatever you typed or
  with nothing typed at all. It is **recorded, not transcribed**: the
  browser's speech recognition garbled too much to be worth keeping. Saving
  while it records stops it and keeps what was said. A thought holds one
  recording, so 🎙 again asks before it replaces the one you have.
- **Listen to it anywhere.** A thought with a recording shows a ▶ with its
  length in the pile, on every device, the desktop app included: the
  recording goes up to your sync server with the next sync and other devices
  fetch it the first time it is played (and keep it, up to ~100 MB). One
  recorded offline says *Not on the server yet* until the phone syncs.
  Turned into a task, the recording goes with it - the task shows a 🎙 mark
  and plays it from its details - and one with nothing typed is called
  *Voice note (0:42)*. Recording is browser-only for now; the apps play.
- **Not in the workspace's colour.** Thoughts are one pile for every workspace,
  so the Thoughts entry, the capture pane and the footer's meter are drawn in the app's
  own blue, and the window drops its workspace tint while the pile is open — the
  same neutral the calendar uses, for the same reason.
- **On a phone the bottom bar is the whole thing.** Thoughts is its fourth
  entry — Tasks / Notes / Parked / Thoughts — and History moved into Settings
  to make room (it is looked back at, not used all day). The footer bar is
  simply **not drawn** there, at any pile size, so the view bar carries
  everything it used to say:
  - **Slide the bar up** to write a thought, from any view. The bar lifts with
    the finger and drops back if you change your mind; while the pile is open a
    line just above the bar says "Slide up to add a thought".
  - **The count rides on the Thoughts entry**, and the whole bar warms towards
    the alarm colour and begins to pulse as the pile grows — the same
    escalation on the same numbers the footer bar runs under a pointer.
  - **The capture pane is plain**: a field and the keyboard, no title, no
    prompt, no emoji.
- **Move them anywhere.** The folder icon on a thought sends it to this list,
  another workspace's list, or any shelf. **Select several** — Ctrl+click, or a
  long press on a phone, then plain clicks add more — and move or discard them
  together. A moved thought becomes a task there and is resolved, not deleted.
- **Review them on demand** — the 💭 count on the *right* of the footer (the
  Thoughts entry in the bottom bar, on a phone) opens the parked-thoughts panel, which slides up and **takes over the content area
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
  workspace, and switching workspace does not clear it. It does now *close* the
  panel, along with every other view: picking a workspace is asking what is on
  that list, and it should answer with the list. The count in the footer and on
  the bottom bar still says how many are waiting, and one press brings them back.
  Parked groups are the per-workspace equivalent.
- **Switching workspace is not blocked by them.** It used to be, on the theory
  that the close guard's rule should apply everywhere. That was the wrong guard:
  since thoughts are global, moving between workspaces cannot hide or lose one,
  and all the block did was make the app feel stuck during the one activity —
  looking around your own lists — that tells you where a parked thought belongs.
  Closing still blocks; that is the path where the pile leaves the screen.
- **Pressure meter** — with the switch block gone, the control carries the
  whole signal, and it escalates harder than it used to: it tints from the first
  thought, starts pulsing at 4, and reaches full intensity and its fastest pulse
  at 12. Past that the count is boxed in the alarm colour and grown, rather than
  merely tinted. The live 💭 count is always visible even though the thoughts
  themselves are not, so the pile can nag you without occupying the window. The
  footer bar and the phone's bottom bar run the same escalation off the same
  numbers — it is one signal, drawn wherever the layout put the control.

## Getting around

- **One bar, in four parts**, which touch: the **workspace**
  you are in (filled in its colour), **where** in it you are (Tasks, Notes,
  Collections, Parked or History), **More** - everything that belongs to no workspace:
  the calendar, the shopping list, side thoughts and settings - and a narrow
  **＋** at the end for writing something down: *Add a task* or *Add a
  thought*.
- **Where it sits.** Along the bottom wherever the window is narrow - a phone,
  the desktop widget at its own size. In a wide window (~560px and up) it goes
  **across the top** or **down the left side**: *Settings → Dock in a wide
  window* picks Top, Side or Bottom, remembered on this device. Along the top
  it sits in the title bar itself, beside the app's name, rather than in a
  second bar under it. Over a top bar the menus drop down, with the row nearest the bar the same one a bottom bar
  puts nearest; down the side they open to the right, and the labels stand up,
  reading top to bottom.
- **With a mouse, rest on a part** and its menu opens; move along the bar and
  the next one opens at once; move away from both the part and its menu and
  it closes. Passing over the bar on the way somewhere else opens nothing.
  Click a row to go there - the row under the pointer lights. **Clicking the
  workspace part or the view part itself goes to the task list** of the
  workspace you are in (out of Notes, Parked and the rest, with nothing
  focused); clicking More or ＋ does nothing - their menus are the hover's.
  Pressing and sliding works with a mouse as it does with a finger.
- **Press, slide up, let go.** Touching a part opens its menu upward. Slide your
  finger to a row - it lights, and the phone ticks - and let go to go there.
  Let go anywhere off the menu and nothing happens. Sliding along the bar
  itself switches to the neighbouring menu without lifting.
- **Slide right to edit a workspace.** Each workspace row has a pencil at its
  right-hand end; carry your finger onto it and the row says "Edit …" - let go
  there to edit it.
- **A workspace's views, straight from the workspace menu.** Each workspace
  row has a ▸ and a little menu beside it: Tasks, Notes, Collections, Parked,
  History. With a mouse, rest on the row; with a finger, hold on the row for a
  moment and slide across (or long-press it in a held-open menu). Picking
  one switches workspace and opens that view in one go.
- **Hover or hold for the menu, tap or click for the part itself.** A menu
  opens on a mouse resting on its part, or a finger holding it (or sliding
  off it); a quick tap shows no menu at all. What a tap or click does:
  - **the workspace** goes to its task list;
  - **the view** goes to the top of the view it names - out of a collection
    to the collections, out of a note to the notes, out of a shelf's review
    to the shelves;
  - **More** opens its menu, and a second tap closes it;
  - **＋** opens the add card.

  To pick from a menu without sliding, **hold the part for a moment and let
  go**: the menu stays up and a second tap picks. Tap anywhere above it to
  close it.
- The pile of side thoughts shows on **More**: its count, and the same tint and
  pulse as it grows that the old bar had. A red dot there means sync needs you.
- It replaces the workspace pill at the top, the old four-icon bar, the
  desktop's workspace rail, and the calendar, list and settings buttons on the
  title bar. It stays put over the
  calendar and the list, so leaving either is picking where to go.
- **The bar reaches the bottom edge.** Under the iPhone's home indicator the
  four parts carry on in their own colours, rather than stopping above a band
  of bare background.
- **Text on a colour is that colour, deeper**: a pastel red workspace is
  labelled in a deep red, a mint one in deep green - never plain black.
- **Every view has a title**, large, with how many things are in it: the task
  list under the workspace's name (in its colour), then Parked, Notes,
  Thoughts, History, the shopping list.
- **Lists without boxes.** Tasks, notes and thoughts are no longer tiles: each
  row sits on the window's own colour, with a short bar between rows that stops
  before the edges. A row is filled only when the fill says something -
  selected, overdue, or the one you are focused on.

## Window & look

- **What's new, once per update.** After an update the app opens a box
  listing what changed, in plain words; *Got it* (or tapping outside) closes
  it and it does not come back until the next update. Each device shows it
  once, on its own. A fresh install shows nothing - there is nothing for it to
  have changed from.
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
- **Window modes** (the □ beside Minimize, Windows app) — your own window
  arrangements, one click each. Move and resize the window the way you like
  it, rest the mouse on the □ and choose *Save this window…*, and give it a
  name; from then on that name is in the list that drops down, with a little
  picture of where the window goes, and clicking it puts the window back
  exactly there at exactly that size. Saving under a name you already have
  replaces that one; the × on a row (under the mouse) removes it. There are
  no presets except **Full screen**. If the screen a mode was saved on is
  gone (a monitor unplugged), it lands in the same place in proportion on
  the screen the window is on. Kept per device.
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
  add-task field and **Ctrl+Alt+H** opens the thought pane, from anywhere,
  even when the widget is minimised or behind another window. Both raise the
  window and clear the sound sheet first. **Ctrl+Alt+T** also leaves focus mode,
  since the add field sits behind the focus overlay; **Ctrl+Alt+H** no longer
  does, because focus mode has its own thought field. If another application
  already owns a combination, the footer says so rather than leaving a dead
  shortcut.
- **The thought pane is the same everywhere.** Ctrl+Alt+H and the dock's
  *Add a thought* open it over whatever is on screen, on a desktop as on a
  phone; it used to be the small field at the foot of the list on most
  screens and the pane only on the calendar. With a keyboard, **Enter** saves
  the thought and closes the pane (back to where you were), **Ctrl+Enter**
  saves it and clears the pane for the next one, and **Shift+Enter** is a new
  line. Esc closes it without saving. On a phone the keyboard's return is
  still a new line, with *Save* and *Save & another* under the thumb. It opens
  ready to type: the caret is in the field, and on a phone the keyboard comes
  up with it.
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
- **Zoom** (Settings, or **Ctrl +** / **Ctrl −** / **Ctrl 0** on desktop) —
  draws the whole widget larger or smaller, text, icons and spacing together,
  from 80% to 150% in steps of ten. It is remembered per device, so the phone
  and the desktop can each have their own. On a phone it comes on top of the
  enlargement the phone already gets. The window stays the size it was, so
  zooming in gives the layout less room and a narrow window takes its narrow
  shape (the view bar at the bottom, say). Zoom stops before the layout gets
  narrower than the smallest window the app allows. In a browser the shortcuts
  are left to the browser's own zoom. Tap the percentage in Settings to go back
  to 100%.
- **Resizable** within sensible min bounds.
- **Custom icon** — gradient (indigo→violet) rounded tile with a white checkmark,
  on every platform: taskbar, tray, iOS home screen, Android launcher. iOS gets
  a full-bleed variant, since it applies its own rounded mask and a tile inside
  a tile looks like a mistake; the tray art drops most of the padding, which is
  wasted at the 16px the notification area actually draws.
- **One set of design tokens** — the widget is drawn from a single scale
  rather than from numbers picked per control: one corner radius, one spacing
  scale (4/8/12/16/24), four type sizes and two weights. It replaced six
  radii, six font sizes inside a 4.5-point range, and paddings chosen widget by
  widget — so the add field's fill now lands exactly over the task rows' fills
  instead of being a pixel out, and a task's text sits the same distance from
  the window edge as everything else. Two deliberate exceptions: **bold** in a
  note is genuinely bold, and text drawn *inside* the calendar grid has its own
  smaller size, because a 15-minute block's height is its duration and the type
  has to fit what the clock chose.
- **Colour says one thing at a time** — red means destructive and nothing else.
  An overdue reminder and a sync that will retry are warm amber (attention, not
  alarm), a flagged task keeps its own muted red bar, and the workspace palette
  runs at about 60% of its old saturation with the window tint down from 16% to
  6%. Same eight hues in the same order, so a workspace is still the colour you
  know it by — the window has just stopped glowing in it.
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
  workspace list and the views sit behind the dock along the bottom (see
  *Getting around*), and the calendar
  shows the compact week grid and the single-column year described above.
- **~300px — the week grid gives way to the agenda**, below which seven columns
  stop being columns. Widen it and the grid comes straight back.
- **~560px and 400px tall — the dock moves off the bottom**, across the top
  or down the left side, whichever Settings says. A wide window is aimed at
  with a mouse, not reached by a thumb. (This used to be where the workspace
  bar unrolled into a rail; the dock replaced both.)
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
- **Move the boundary, or fold the list away.** Wherever the task list sits
  beside something — a panel, or the calendar — the line between them can be
  **dragged**, and **double-clicking** it puts it back. Drag it all the way to
  the left, or press the ‹ that appears while the pointer is on it, and the
  list **folds into a narrow strip**, so the notes (or the week grid) have the
  whole width; the strip's button unfolds it. Both are remembered on this device:
  the position as a proportion, so resizing the window keeps it, separately for
  panels and for the calendar, and the fold as one preference for both. Folding
  never resets the pane beside it — a note being edited stays open.
- **The task column stops at 620px.** Beyond that the extra room goes to the
  second pane: a tick box 900 pixels from the end of its own line
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
- **The app and the server agree on a version before they exchange anything.**
  Both ends declare what version of *sync itself* they speak — not the app's
  release number and not the server's, since almost every release leaves the
  wire exactly as it was. If they can talk, nothing is said about it. If they
  cannot, the app stops syncing and says which machine is behind: **Update the
  app** when the server has moved on without it, **Update the server** when it
  is the other way round, with both version numbers shown. Nothing is lost while
  it waits — every edit still saves locally and queues, and the moment the two
  match again the queue goes up on its own. It also rechecks on its own, so
  deploying the server is enough; nothing has to be restarted or re-entered.
  The reason it exists: the 0.24.0 server was a few commits behind for a while,
  so repeating and all-day events synced with those two fields silently dropped.
  There was no symptom to see, on either machine.
- **A server that has never heard of any of this still works**, and is treated
  as the original version — which is what let the check be switched on without
  every device and server having to be updated on the same day.
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
- **Notifications from outside the app** — `POST /api/notify` with a title and
  a body sends them as a notification to every device that has Web Push on, so
  the server's monitoring (or any script with a webhook) can reach your phone.
  `npm run token -- notify <user-id>` issues a token that can do that and
  nothing else: it is refused by every other route, so leaking it costs at most
  some unwanted notifications. Listed as *notify only*; revoked like any other.
  How to call it: `server/DEPLOY.md`, *Notifications from other things*.

## Platforms

- **Windows** — the always-on-top widget described above.
- **iOS / Android** — the same lists and data, without the window chrome
  (always-on-top has no meaning on a phone). Installed on iPhone from an
  unsigned build signed locally with Sideloadly or AltStore.
- **Web** — the same app in a browser, served by the sync server itself at its
  own address (todo.sniggles.de), so there is no certificate to renew and
  a deploy reaches the phone on the next reload. "Add to Home Screen" on iOS
  gives it an icon and a full-screen window. The sync screen starts with the
  page's own address filled in; only the token is typed, once per browser.
  Edits from other devices arrive live, as they do everywhere else.
  - Tasks, workspaces, shelves, the calendar, notes (encryption included),
    thoughts and history all work.
  - **Notifications by Web Push**, switched on per device under Settings →
    Notifications. The server sends them, so task reminders and calendar
    alerts arrive with the app closed, on the lock screen, like the native
    app's. On an iPhone this needs iOS 16.4 or later and the app opened from
    the Home Screen (Safari itself cannot receive them); *Test* sends one on
    the spot. They follow the native rules: a parked task stays quiet, an
    event uses its own lead or its calendar's, an all-day event only
    notifies if it was given its own lead.
  - **Not in the browser:** concentration sound, attachments (rows from other
    devices still sync; there is nowhere to keep the bytes), home-screen quick
    actions, the tray, global hotkeys and always-on-top.
  - **The icon** is the app's own on the iPhone Home Screen. It used to be
    a letter, because iOS asks for `/apple-touch-icon.png` and got the page.
    Remove the old icon and add the app again to pick it up: iOS never
    refreshes a home-screen icon by itself.
  - The browser keeps its own database (IndexedDB), so it is one more device as
    far as sync is concerned, and clearing the site's data is a reinstall.
- **Home-screen quick actions** — long-press the app icon for "Add task",
  "Park a thought" and **"Calendar"**, which opens straight onto the calendar
  (and stays there if the app was already showing it). Both land in the running app with the caret already in the
  right field; this is the phone's counterpart to the Ctrl+Alt+T / Ctrl+Alt+H
  global shortcuts, and it exists for the same reason — capture speed. (Not a
  WidgetKit home-screen *widget*, which is a separate app extension and cannot
  host a text field at all.)
- **The menu names the task you are on.** Put a task into focus mode and a third
  entry appears in it — *Note on “rewrite the importer”* — which opens a
  full-screen field and **appends** what you write to that task's notes. It is
  the same pane a side thought is written in, pointed somewhere else: one line,
  saved, the phone back in your pocket, without finding the task first. The
  entry follows focus mode, so it changes when you change task and goes away
  when nothing is in focus.
  - It is **appended**, never overwritten, and the row is re-read at the moment
    you save. The menu is stored by the operating system and outlives the app,
    so the line can arrive long after anything else was written to that task —
    including from another device.
  - A stale entry is therefore possible (the task was finished on the laptop an
    hour ago). Pressing it then opens the ordinary add field rather than doing
    nothing: you meant to write something down.
  - iOS shows at most four entries, so three is the whole budget.
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
- **A list that belongs to a block of time.** Shipped in 0.17.0 as *Sublist* and
  **removed again in 0.25.0**: writing a block's todos into a sheet of their own
  put a second add field in the app, reachable from three places, and in use it
  was mostly in the way. Planning — ticking todos you already have into a block,
  or dragging one onto it — is untouched and is what the feature was competing
  with. If it comes back it needs a different shape: probably somewhere on the
  block itself rather than a sheet, and an answer to what a todo written into a
  block *is* when the block is deleted.

---

## Changelog

- **0.29.0** — *(in progress)*
  - **From the shelf**: a click on the dock's workspace goes to its task list
    (not the add field); the workspace menu has each workspace's views in a
    submenu; double-click a calendar event to edit it; links in task titles
    show the page's title (server: `/api/link-title`).
  - **Voice notes**: the thought pane's 🎙 records instead of transcribing,
    and a thought or task with a recording plays it on every device. Rows
    gain `audio` / `audio_ms` (client v20, sync protocol 6); the bytes go
    through the server's new `/api/blobs/:sha256`, kept per account.
  - **Dock taps**: a short tap or click on the workspace goes to its task
    list, on the view to the top of that view, on More opens its menu, on ＋
    the add card; no menu flashes on a tap any more, it waits for a hold or a
    slide. Holding a part and letting go leaves its menu open.
  - Recording a second voice note in the thought pane asks before it
    replaces the first.
  - **A new way to add a task**: *Add a task* opens a card in the middle of
    the screen with buttons for priority, a reminder, the workspace and the
    long form; a #workspace (or its shortcut, e.g. *#MT*), a day or a time
    typed into the title sets them; Enter adds and closes, Ctrl+Enter adds
    and stays, Shift+Enter is a new line (see *Tasks*). Workspaces gain
    `shortcuts` (client v19, sync protocol 5).
  - **Notifications from outside the app** (server): `POST /api/notify` and
    notify-only tokens, for the server's monitoring to alert the phone.
  - **What's new**: a box after every update says what changed.
  - **The thought pane opens ready to type**, with the keyboard up on a
    phone; it used to open with nothing focused.
  - **The phone's bottom bar is new**: workspace, where, more and ＋ (add a
    task or a thought); press, slide up to where you want to go, let go. Slide
    right on a workspace to edit it. See *Getting around*.
  - **No more tiles**: tasks, notes and thoughts are separated by short bars
    instead of each sitting in its own box.
  - **A second design pass**: every view opens under a large title with its
    count (the task list under its workspace's name, in its colour); titles,
    the bottom bar and group names are set in Space Grotesk; parked groups are
    sections with the title on its own line and the controls in one column
    under it; History lost its strike-through; the bottom bar runs down under
    the iPhone's home indicator; labels on a coloured block are a deep shade
    of that colour instead of black; no more frame around the app on a phone.
  - **The dock on every screen, and events that move**: the bottom bar is the
    navigation on the desktop too - along the bottom of the widget, across the
    top (in the title bar, beside the name) or down the side of a wide window
    (Settings picks), and with a mouse its menus open on hover; the workspace
    bar, the rail and the title bar's calendar / list / settings buttons are
    gone. Calendar events can be dragged to another time or day (a mouse drags
    straight away, a finger holds first). Ctrl+Alt+H works on the calendar
    and the shopping list: it opens the thought pane over them.
  - **Edit mode, and the rest of the shelf**: the calendar's ⚡ quick add is now
    an **edit mode** (✎, or Ctrl+E on a desktop) - blocks move and, new,
    **stretch by their top or bottom edge** only while it is on, so a stray
    drag cannot move a meeting. The red line for now is drawn over the blocks
    instead of under them. On a desktop a new thought always opens the thought
    pane (Enter saves and closes, Ctrl+Enter saves and starts another,
    Shift+Enter is a new line). A click on the dock's workspace goes to the
    add field. The title bar has **window modes**: arrange the window, save it
    under a name, and it is one click from then on (plus Full screen). A sideways swipe on the list walks the same
    views the dock lists (Tasks, Notes, Collections, Parked, History). The old
    workspace bar, rail and view bar are gone from the code too.
  - **Calendar and list touches**: the next and previous week show beside the
    one you are on as you swipe, so a short drag is a glance; pressing to
    create starts in the quarter hour you pressed, not the nearest one; events
    are solid blocks with a darker edge, and a long title stands up in a tall
    narrow block; a new shopping list stays in Edit while you type it.
  - **No more stuck zoom on an iPhone**: tapping into a text field in the web
    app no longer zooms the page in, which it then could not be pinched back
    out of.
  - **Collections**: per-workspace lists with fields you define first - text,
    link, number, checkbox - for recipes, movies and the like. Adding an entry
    is typed straight through: Enter moves to the next field and, on the last,
    adds it and starts the next. A table on a wide window, rows with a tick box
    on a phone, search and sort. Needs the server updated (protocol 4).
  - **Shopping list**: one throwaway list on the title bar that the app opens
    on every time, with a tick-only mode for the shop, ticked items that slide
    down, and Finished to archive it. Needs the server updated (protocol 3).
  - **Fixed: updating the server stopped un-updated devices syncing.** Since
    protocol 2 the server only sends an app the fields it can store.
  - **Subscribe to calendars by address** (Google, Outlook, iCloud…), into a
    new calendar or merged into an existing one. Read-only, refreshed every
    half hour. **Needs the server updated too** (sync protocol 2); until then
    the subscription stays on the device that made it.
  - **Swiping the calendar slides**: the week follows your finger and the next
    one slides in, instead of jumping.
  - **Zoom**: make the whole widget larger or smaller, from Settings or with
    Ctrl +/−/0 on desktop.
  - **Notifications in the web app**, by Web Push from the sync server:
    reminders and calendar alerts with the app closed. Settings →
    Notifications, per device. Needs the server updated too.
  - **The web app's Home Screen icon** is the app icon, not a letter.
  - **The web app keeps clear of the iPhone's home indicator.** The bottom bar
    sat on top of it, so sliding the bar up to add a thought sent you to the
    home screen instead.
  - **A web version**, served by the sync server: open the server's address in
    any browser, or add it to the iPhone home screen instead of sideloading.
    See *Platforms*.
  - **Notes survive whatever closes them.** A half-written note used to vanish
    when the workspace was switched or the window was widened past the point
    where the list appears beside it. Both now keep it.
  - **Thoughts in a neutral colour**, since the pile belongs to no workspace.
  - **Review a shelf from its header**, without expanding it first.
  - **A Calendar entry in the home-screen quick actions.**
  - **Go to workspace** from a calendar entry that belongs to one.
  - **The sidebar collapses** to workspace dots and view icons.
  - **Select several tasks** with Ctrl+click (Select on a phone) and complete,
    delete, park or move them at once — **to another workspace's list or
    shelves** as well as this one's. The single-task park picker offers the
    other workspaces too.
  - **Add a task from a ＋**, not a permanent field: on the workspace bar, the
    rail, or N.
  - **"Add a task" at the top of the list**, on every screen size.
  - **Add to another workspace** from the add field's coloured dot, without
    switching to it.
  - **Tasks coming off a shelf keep its name**, as "Shelf: task".
  - **Move side thoughts** to any workspace's list or shelf, one at a time or
    several selected together.
  - **Double-click a note** to edit it.
  - **The narrow desktop window has the bottom view bar** too: Tasks / Notes /
    Parked / Thoughts, one click each.
  - **Editing a workspace is a ✎**, shown on hover, rather than a click on its
    name; the name now opens the switcher. Collapsed-rail dots expand on hover.
  - **Bigger controls and text** on parked shelves and side thoughts.
  - **Thoughts on a phone are a tab in the bottom bar**, in place of the
    floating bubble: slide the bar up to write one, and the bar pulses as the
    pile grows. History moved into Settings. The capture pane is plain - no
    title, no prompt.
  - **The "Add task" and "Park a thought" quick actions work** from a cold
    start, and "Add task" no longer opens its field behind the calendar or a
    task that has the screen.
  - **The calendar header is one line on a phone** — ‹ date ›, a view chip and
    ⋯ — instead of three rows.
  - **Radio: search, stars and your own streams.** Search the directory by
    name, star stations into a Saved list, and add a stream by URL.
  - **Double-click a task to edit it** on desktop, without going through the
    action bar.
  - **The split is yours to move.** Drag the line between the list and a panel
    or the calendar, or fold the list away to give the other side the width.
- **0.28.0** — **Todos that arrive on their own, a shelf you have to read, and
  the sound stops stalling.** Six things, one release.
  - **Recurring todos, in the two shapes that were actually wanted.** A repeat
    can now be measured **from the schedule** or **from when it was last
    ticked**: "clean the kitchen every two weeks", created on the 1st and done
    on the 8th, comes back on the 22nd rather than the 15th. And a scheduled
    repeat can say **when the next one appears** — when the last is done (the
    old behaviour, which can never pile up), when it falls due whether or not
    it was ticked, or a day / three days / a week early with the due date still
    the rule's. That second setting is what makes "Send working hours to
    management, last day of every month" a todo that turns up on its own.
  - **Rules a due date could not say**: the last day of the month (which is not
    "monthly" from the 31st — that clamps to 28 February and then stays there),
    the first/second/third/fourth/last weekday of the month, and every *n*
    days, weeks, months or years.
  - **Variables in the title and notes** — `$(month)`, `$(date)`, `$(week)`,
    `$(quarter)` and the rest, with offsets like `$(month-1)`. Each occurrence
    is written out once against its own due date, so History keeps saying what
    it said.
  - **Add straight to a parked shelf.** An open group has its own one-line
    field. Recording that something is explicitly *not* for today used to mean
    adding it to the list, finding it, and parking it.
  - **Reviewing a shelf is a funnel, not a button.** One task at a time with
    what a decision needs — its notes, "parked 47 days ago", an armed reminder —
    and four answers: Keep (also Enter), Do it now, Done, Drop. Reaching the end
    is what restarts the group's clock; leaving half way keeps the decisions and
    not the clock. *Mark reviewed* could be pressed without having read
    anything, so the shelves it existed to protect went to landfill with a fresh
    timestamp on them.
  - **Thirty minutes of the ambience is kept on the device.** A field recording
    is finite and then looped for an hour, so every stall was paid for over and
    over. The first play of a preset streams as before and files a bout behind
    itself; after that it starts instantly and needs no network. A couple of
    bouts are kept per preset and one is picked at random, so "a different café
    every time" survives. A switch, a size and a **Clear** are at the foot of
    the Ambience list.
  - **Switching workspace lands on that workspace's list.** Every view closes
    now, thoughts included — the pile is still there, and its count is still on
    the footer and the bubble.
  - **Opening a note on a phone no longer closes it again.** Hiding the chrome
    around the note was rearranging the widget tree underneath it, which threw
    away the pane's own idea of which rung it was on.

- **0.27.0** — **Quieter, and on a scale.**
  A look pass, no behaviour changes. Five directions were drawn at true size
  and compared before anything was written; this is the one that keeps today's
  shape and puts a real system under it.
  - **One radius, one spacing scale, four type sizes, two weights.** Six radii
    and six font sizes inside a 4.5-point range became one and four. Paddings
    now come from a 4/8/12/16/24 scale instead of being chosen per control, so
    things that should line up do.
  - **The colour is turned down.** Workspace colours run at about 60% of their
    old saturation — same hues, same order, so your workspaces are still the
    colours you know — and the window tint behind them drops from 16% to 6%.
  - **Red means destructive now, and only that.** An overdue reminder and a
    failed-but-retrying sync are a warm amber; a flagged task keeps a muted red
    bar of its own. Previously one full-strength red said "this will be gone
    for ever" and "this was due at nine" in the same window.
  - **Notes preview half a point larger** (11 rather than 10.5), which is the
    size below which the fallback faces on Android stop hinting cleanly.

- **0.26.0** — **The task row gives its width back.**
  One change, at both sizes: the actions came off the row and into a bar you
  ask for.
  - **Right-click a task** (or **tap its text** on a phone) and its actions
    appear as a floating bar over the row. Nothing is drawn on the row itself
    any more. The desktop icons were invisible until hovered but **still took
    their space**, so in a narrow window most of a row's width belonged to
    controls that were not on screen; the phone's bar was a permanent second
    line under every task, and a third one on a task that carried everything.
  - **Editing is the pencil in that bar**, on both. A left-click on the title
    with a mouse now *expands* the task instead of opening the editor.
  - **Expand a task to read it** — ⤢ in the bar. Notes rendered as Markdown,
    and everything the row can only hint at spelled out: "Reminder tomorrow
    09:00", "Every week", "Planned into a block", "2 documents". Read-only.
    A desktop row grows in place and the list scrolls past it; on a phone it
    takes the whole screen and the back arrow or Esc collapses it.
  - **Reordering on a phone is a press and hold** anywhere on the row, and the
    six-dot grip is gone from it — a permanent mark for a gesture that needs no
    target. With a mouse the grip moved to the **right** end of the row, off the
    left edge where it was indenting the title of every task in the list.
  - **A row still shows what it is carrying** without being asked: the flagged
    task's red bar, an armed bell, a 📎 for documents, a 📅 for a planned block.
    Those are marks now, not buttons.

- **0.25.0** — **A night is a night, and a phone stops repeating itself.**
  Six things, five of them from using the app on a phone for a week.
  - **A block of time can cross midnight and still be a block of time.** 22:00
    to 04:00 is drawn where it happens — two hours at the foot of one day, four
    at the head of the next, cut square where midnight divides them — instead of
    being promoted into the all-day band, which printed neither the hour it
    started nor the hour it ended. Anything ending *at* 00:00 stays in the day
    it started, and only a block with a whole day inside it (a conference, a
    holiday) still goes to the band. Picking an end time earlier than the start
    now means the next day, so an overnight block is two taps rather than a trip
    through the date picker.
  - **The side-thought bar is gone from the phone.** It was a third strip of
    chrome along the bottom edge, below the view bar, saying what a badge could
    say. The bubble carries all of it now: the count sits on its shoulder, the
    circle warms and pulses as the pile grows, and a **swipe up** opens the pile
    — the bubble lifts with your finger and drops back if you change your mind.
  - **The quick-action menu names the task you are on.** Long-press the app icon
    while a task is in focus and there is an entry for it; it opens one field
    and appends what you write to that task's notes. The line is appended to
    whatever the row says at that moment, not to the copy the app was holding,
    because the menu outlives the app and the press can arrive hours later.
  - **Ctrl and the wheel zoom the calendar's timeline**, which pinching has done
    on a phone since 0.24.0 and a mouse had no way to ask for. The hour under
    the pointer stays put; a plain wheel still scrolls the day.
  - **"Add workspace…" works from the dropdown.** On a window too narrow for the
    rail that entry was the only way to make a workspace, and pressing it did
    nothing whatever — the menu reported the press as a dismissal and threw it
    away.
  - **Block sublists are removed.** Writing a block's todos into a sheet of
    their own was reachable from three places and mostly in the way; planning —
    ticking in todos you already have, or dragging one onto a block — is
    untouched, and is what it was competing with. It is in the backlog with a
    note on what it would need to come back.
- **0.24.1** — **The app and the server check they still speak the same
  language.** Both ends now declare a version of the sync protocol itself, and
  if they disagree the app stops syncing and says which of the two has to be
  updated, naming both numbers. This has a specific origin: the sync server here
  ran a few commits behind for a while, and repeating and all-day events went up
  with those two fields silently dropped — no error, no symptom, nothing on
  either machine that would ever have said so. Nothing is lost while the two
  disagree: edits still save, the queue still fills, the app re-checks on its
  own and everything goes up the moment a deploy fixes it. A server too old to
  know about the check is read as the original version and keeps working, so
  turning this on did not require updating everything at once.
- **0.24.0** — **A block of time can repeat.** A stand-up every weekday, rent
  on the 1st, a birthday: pick the rule in the event form and it is on the grid
  every time it comes round, marked with a ↻ and named on its details card.
  It is still **one entry** — the occurrences are worked out from the rule
  rather than written into the database — so renaming it renames every one of
  them, and a year of Mondays costs one row rather than fifty-two. What follows
  from that is stated rather than hidden: editing or deleting an occurrence is
  editing or deleting the series, the form says so under the rule, and a delete
  asks first and names how the block repeats. Changing one occurrence on its own
  is deliberately not in this version.
  Two details that are wrong in a lot of calendars: a monthly block on the 31st
  stays on the 31st instead of being dragged back to the 28th by the first
  February it meets, and a 09:00 block still reads 09:00 after the clocks change.
  **Importing an .ics brings the rule with it**, when the file said something
  this app can also say — every day, weekday, week, month or year. A rule with
  an end date, an interval or a “second Tuesday” in it still imports as one
  block and still says so, because approximating it would be wrong every week
  instead of once.
  **An event can be a whole day.** A birthday, a public holiday, a week away:
  the *All day* switch drops the times and the block moves into the band above
  the grid, instead of standing as a 24-hour column with nothing behind it.
  All-day blocks stay quiet unless you give that one a lead time of its own —
  a calendar's “an hour before” rule is about meetings, and inheriting it
  would have every birthday going off at 23:00 the night before. All-day
  events in an imported .ics are no longer flattened into midnight-to-midnight
  blocks either.
  **An attachment whose file never arrived can be pointed at it.** “Not on
  this device” was a dead end until blob sync exists; the new *Locate* button
  on such a row asks for the file here and adopts it if it really is the same
  document — which the stored SHA-256 can prove, so a copy under a different
  name still counts and a different file is refused rather than quietly filed
  under the wrong name on one device.
  **On a phone, swiping the calendar moves through time** rather than switching
  day/week/year — the setting you change once a session was on the gesture you
  make twenty times, while moving a week meant reaching for the ‹ › at the top
  of the screen. **The date also gets a line of its own**, so a day view shows
  "Tuesday, 18 August 2026" instead of clipping it beside four controls.
  **Opening a calendar entry no longer shows a white rectangle.** The details
  card and the event form were the last two Material dialogs in the app: on a
  phone the card's four actions took the whole height and left the title, a
  Delete button and a tall empty slab where the answers should have been. Both
  now open as the same panel every other form uses — full width against the
  bottom edge, in the colour of the calendar they belong to, pushed clear by
  the keyboard rather than covered by it. The date and time buttons inside the
  form also stop overflowing in a 340px window, which they had been doing
  behind a dialog that clipped them silently.
  **A quick-add block can be picked up and put down somewhere else.** Dragging
  one used to move it only within its own column, and it moved by re-laying
  itself out under your finger rather than being carried; putting Tuesday's
  block on Wednesday meant deleting it and placing it again. A long press now
  lifts it, it lands where it is dropped, and holding it against the left or
  right edge walks the grid under it so it can reach a day that is off screen.
  **Pinching the day and week views zooms them**, from a compressed overview to
  a grid you can place a 15-minute block on, remembered per device.
  **The calendar stops borrowing the colour of the workspace you opened it
  from.** It is the one view that is not about a single workspace — it can show
  all of them at once, each block in its own calendar's colour — and a window
  tinted 16% into one of those colours was quietly competing with exactly the
  distinction the week view exists to draw. It takes a neutral grey while it has
  it is open, beside the task list as well as full window.
  **Writing down a side thought on a phone is a bubble over the list**, sitting
  just above the bottom bar where the thumb already is, instead of a 15px 💭 in
  the thinnest strip at the very bottom of the screen. It is the only capture
  button there — the footer gives its own up rather than putting the same
  control in two places — and with nothing pending the footer takes no height
  at all, so the row goes back to the tasks. **The pane it opens also stops
  below the title bar**: it used to be drawn underneath it, which put its ✕
  exactly under the concentration-sound button, so closing what you had just
  written started a rain sample instead.
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
