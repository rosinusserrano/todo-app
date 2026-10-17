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

Marco's parked shelf "Todo Widget" (Meine Apps), gone through on 2026-10-08.
Capture comes first because it is the thing that has been "bugging me the
whole time": both quick actions, then the phone's thoughts UI, then making
adding a task visible and able to aim at any workspace. The rest is ordered
small-to-large. Design for 45-47 and 54 is in `ROADMAP.md` under *Capture
should be fast*. Dropped from the shelf: "remove concentration sounds" (Marco:
keep them). Already shipped: "double click TODO WIDGET edits task" (43).

### 62. Six from the shelf  `[~]`

Sent 2026-10-16 (screenshot of the shelf); answers and reasons in
`ROADMAP.md` under *Six from the shelf*. Built on `redesign`.

- [x] **62.1** A click on the dock's workspace goes to its task list.
- [x] **62.2** Double-click / double-tap a calendar event edits it.
- [x] **62.3** The workspace menu's rows have a submenu of their views.
- [x] **62.4** Links in task titles drawn as the page title
      (`link_titles.dart`, server `/api/link-title`).
- [x] **62.5** 🎙 dictation in the thought pane (browser build). Replaced
      by 62.7.
- [x] **62.7** 🎙 records a voice note instead of transcribing (2026-10-17):
      `audio`/`audio_ms` on thoughts and tasks (client v20, protocol 6),
      bytes through `/api/blobs` (`server/blobs.js`), played everywhere
      (`voice_notes.dart`). Recording is browser-only.
- [x] **62.8** Dock: a short tap / click on the workspace or view segment
      goes to the task list; on More and ＋ it does nothing; hold and let go
      keeps a menu open.
- [ ] **62.9** Try both on the iPhone web app (recording, playback after
      the clip has gone through the server) and the desktop app (playback).
- [~] **62.6** Merged to `main` (2026-10-16). Left: deploy the server
      (needed for link titles in the browser, and for 61's shortcuts),
      publish the web app (`server/build-web.sh /srv/todo-web`).

### 61. The add card  `[~]`

Asked for 2026-10-15; design in `ROADMAP.md` under *The add card*. Built on
the **`redesign` branch** (worktree `../todo-app-redesign`), published to the
dev site, merged to `main` once Marco has tried it.

- [x] **61.1** `task_keywords.dart`: workspace names, dates and times read
      from a title, with `test/task_keywords_test.dart`.
- [x] **61.2** `ui/task_capture.dart`: the card - the flight from the folded
      line, the scrim, the bar (priority, reminder, workspace, ⤢, add), the
      highlighted keywords and their ×, `test/task_capture_test.dart`. The
      shell's inline field and its workspace chip are gone; the composer
      takes the card's priority and reminder.
- [x] **61.3** FEATURES / CLAUDE.md / What's new; published to
      todo-dev.sniggles.de.
- [x] **61.4** Marco's first round (2026-10-16): Enter adds and closes,
      Ctrl+Enter adds and stays, Shift+Enter is a line; workspaces only with
      `#`; shortcuts (`workspaces.shortcuts`, client v19, protocol 5), added
      from a pill on the recognised word, removed in the workspace form.
- [x] **61.5** Merged `redesign` to `main` and pushed (Marco, 2026-10-16).
- [~] **61.6** Web app published from `main` (2026-10-16). Left: deploy the
      server (protocol 5, or shortcuts do not sync - `sudo
      server/update-server.sh`, Marco), `install-windows.ps1`.

### 60. Notifications from outside the app: `POST /api/notify`  `[~]`

Asked for 2026-10-16: the server's Beszel monitoring (monitor.sniggles.de)
should alert the phone through the app's Web Push, instead of email. Web Push
only - the native apps do not get it. Server only; no app change.

- [x] **60.1** `POST /api/notify` (`readNotification`, `notifyUser` in
      push.js), notify-only tokens (`tokens.scope`, refused by every route
      that does not ask for the scope), `npm run token -- notify`. Tests,
      a scratch server, Beszel's exact payload. Docs: DEPLOY.md, FEATURES.md.
- [ ] **60.2** Deploy the server (`sudo server/update-server.sh`), issue a
      notify token for Marco's account (DEPLOY.md, *Notifications from other
      things*), put the `generic://` URL into Beszel under Settings →
      Notifications, press Test.

### 59. Collections  `[~]`

Agreed with Marco 2026-10-13 (name, per workspace, text / link / number /
checkbox fields). The design is in `ROADMAP.md` under *Collections*; this is
only the order. Built on `main`, like the shopping list.

- [x] **59.1** Design written down and agreed.
- [x] **59.2** Store: `collections`, `collection_fields`, `collection_entries`
      (client v18, `_create` and `_upgrade`, models, migration fixture
      rollbacks), server tables + `TABLES` + `TABLE_SINCE` at protocol 4,
      client holds them back from a server below 4. Tests both sides.
- [x] **59.3** `AppState`: `showCollections` in the view set, load the
      workspace's collections / fields / entries, save a collection with its
      fields (diffed), add / edit / delete / tick entries, the workspace
      cascade, refresh on a sync merge.
- [x] **59.4** The screens (`ui/collections.dart`): the list of collections,
      a collection (table when wide, rows when narrow, search, sort), the
      collection form (fields, types, starters), the entry form (Enter jumps
      to the next typed field; on the last it adds and starts the next).
- [x] **59.5** The doors: `WorkspaceView.collections` in the dock, the ▾ menu,
      the rail (full and strip), the Esc ladder, `_selectView` / `_showTasks`
      / `_jumpToAddTask`.
- [x] **59.6** `FEATURES.md` (section + changelog), `CLAUDE.md` architecture
      note, analyze clean, tests green, commit.
- [ ] **59.7** Deploy the server (protocol 4), publish the web build,
      `install-windows.ps1`; Marco tries it with his recipes.

### 58. The redesign  `[~]`

Asked for 2026-10-12. Worked on in the **`redesign` branch**, checked out as the
worktree `../todo-app-redesign`, and tried on the phone at the dev site (see
58.1). 58.1-58.3 merged to `main` and published to the web app on 2026-10-12;
later rounds go the same way (branch, dev site, then main). Reasoning is in `ROADMAP.md` under *The redesign*.

- [x] **58.1** A dev copy of everything: `server/setup-dev.sh <domain>` - a
      second server on a snapshot of the live database, its own web root, a
      Caddy site. Publish with `server/build-web.sh /srv/todo-dev-web`.
- [x] **58.1b** Marco ran `sudo server/setup-dev.sh todo-dev.sniggles.de`;
      first build published (restart needed once: the server only looks for
      a web build at startup).
- [x] **58.2** The dock (`ui/dock.dart`): one bar of three filled segments on a
      phone - workspace / where / more - press, slide up, let go; slide right
      for a row's second action. Replaces the workspace bar, the view bar and
      the title bar's calendar / list / settings buttons on touch.
- [x] **58.2b** A fourth, narrow ＋ segment: Add a task / Add a thought (the
      quick actions). The slide-right add/write on Tasks and Thoughts went
      with it; slide-right is now only Edit on a workspace.
- [x] **58.3** Rows without tiles (`ui/list_rule.dart`): tasks, notes, thoughts.
- [ ] **58.4** Marco tries 58.2-58.3 on the phone; changes from that.
- [x] **58.8** Second pass after a walk through every screen on the dev copy
      (with Marco's data) and a look at Dribbble: large view titles with counts
      (`PanelHeader`, `T.fsTitle`), a display face for chrome (Space Grotesk,
      `T.fontDisplay`), tonal ink on coloured fills (`T.inkOn`), parked groups
      as sections (title alone on its line, controls in fixed slots, rules),
      History without strike-through and with rules, the dock painted down
      into the home indicator's strip (`Dock.underhang`), dimmed segments fade
      their fill not their label, counts in the segment corner, the menu's
      "current" bar no longer shifts its row, no window frame on touch, the
      list's add field unboxed.
- [x] **58.9** Marco tried 58.8 on the dev site; merged to `main` 2026-10-13.
- [x] **58.10** Round 3, merged to `main` 2026-10-13: the shopping list
      stays in Edit while a new list is typed; the calendar swipe draws the
      neighbouring week/day (`calendarLoadRange` loads one step either side,
      `TimeSwipe.builder`, a shared scroll offset); press-to-create takes the
      quarter hour pressed (floor, slots both ends included); events are solid
      `RaisedFace` blocks on a `T.edgeOf` edge with `T.inkOn` text, and a long
      title stands up in a tall narrow block. Merge to `main` once tried.
      Needs `sudo systemctl restart todo-sync-dev` for the dev server to speak
      protocol 4.
- [x] **58.11** Round 4, merged to `main` 2026-10-13: the dock at every size
      (bottom when narrow; top, side or bottom past `Layout.hasRail`, picked
      in Settings as `AppState.wideDock`), replacing the workspace bar, the
      rail, the view bar and the title bar's calendar / list / settings;
      calendar events carried to a new time or day (`EventBlock.movable`,
      `AppState.moveEvent`; mouse drags at once, touch holds first); and
      Ctrl+Alt+H opening the capture pane where the footer is not drawn.
      Then: dock menus open on mouse hover, and a top dock sits in the title
      bar beside the name.
      Merge to `main` with 58.10 once tried.
- [x] **58.12** Marco keeps the Top / Side / Bottom setting (2026-10-14), so
      the old bars went: `ui/workspace_bar.dart`, `ui/view_bar.dart`,
      `ui/workspace_rail.dart`, their tests and `AppState.railCollapsed`.
      `WorkspaceView` + `kViewOrder` are in `ui/workspace_view.dart`, the form
      in `ui/workspace_form.dart`; `Layout.hasRail` is `isWide`.
- [x] **58.13** Round 5, the shelf of 2026-10-14, merged to `main` and
      published 2026-10-14:
      - calendar edit mode (✎, Ctrl+E) replaces ⚡ quick add; moving blocks
        only in it; stretching a block by its top or bottom edge
        (`_ResizeGrip`, `AppState.resizeEvent`), edge lightens on hover/touch;
      - the now line above the blocks;
      - every thought capture opens `ThoughtSheet`, desktop included, Enter
        saves + closes, Ctrl+Enter saves + another, Shift+Enter newline;
      - a mouse click on the dock's workspace segment opens the add field;
      - window presets in the title bar, desktop only (`window_spots.dart`);
        redone 2026-10-15 as hover-open *modes*: no presets but Full
        screen, the window saved as it is under a name.
      Then: `viewport-fit=cover` only for the home-screen web app (in a
      Firefox tab on iOS the dock sat under the browser's toolbar), and a
      stretched block's preview drawn solid over the faded original.
- [ ] **58.5** The rest of the tiles: shopping list items, the sheets and
      forms, the task action bar.
- [x] **58.6** Decide what the desktop and the narrow window get: the dock,
      everywhere (58.11).
- [x] **58.7** First round merged to `main` (changelog under 0.29.0) and the
      web app published.

### 57. The shopping list  `[~]`

Agreed with Marco 2026-10-12. The design is in `ROADMAP.md` under *The shopping
list*; this is only the order.

- [x] **57.1** Design written down and agreed.
- [x] **57.2** Store: `lists` + `list_items` (client v17, `_create` and
      `_upgrade`, models, migration fixture rollbacks), server tables + `TABLES`
      + `TABLE_SINCE` at protocol 3, client holds them back from a server below
      3. Tests both sides.
- [x] **57.3** `AppState`: the current list (newest unarchived), add / retitle /
      delete / reorder / tick / untick items, rename, finish (archive), the
      archive, "also open" lists from an offline conflict.
- [x] **57.4** The list screen: Use and Edit modes, the big Edit / Done and
      Finished buttons, ticked items sliding into the Ticked section and back,
      the empty "New list" start, and the quiet "Archived lists →" with its
      read-only view.
- [x] **57.5** The title-bar icon beside the calendar's; the list takes the
      whole content area like the calendar does (add it to `_clearOverlays`
      and the Esc ladder).
- [x] **57.6** Opening on the list: launch, every lifecycle resume on phone and
      web, tray-show / un-minimise on desktop (not focus). Never over a
      half-typed field.
- [x] **57.7** `FEATURES.md` (section + changelog), `CLAUDE.md` architecture
      note, analyze clean, tests green, commit.
- [ ] **57.8** Deploy the server (protocol 3), publish the web build,
      `install-windows.ps1`; try it in a shop on the phone.

### 56. Subscribed calendars, and the week slides  `[~]`

Asked for 2026-10-11/12. Design is *Step 0* in `ROADMAP.md` (Google calendar
section). Committed; this supersedes the stashed .ics work 32.2 mentions (that
stash was never found in this clone - drop it rather than pop it).

- [x] **56.1** The week/day/year swipe slides (`ui/calendar/time_swipe.dart`).
- [x] **56.2** Subscribe to an .ics / webcal address, into a new calendar or
      merged into an existing one; read-only events, refreshed every 30 min,
      RRULE/EXDATE/RECURRENCE-ID expanded per instance (`sync/feeds.dart`,
      `sync/rrule.dart`, `ui/calendar/subscribe_form.dart`, client v16).
- [x] **56.3** The web build fetches through the server (`/api/feed`,
      `server/feeds.js`, SSRF-checked). Wire protocol 2.
- [x] **56.4** Fix: protocol 2's first deploy broke every un-updated device -
      a pulled `feed_uuid` column failed their whole merge. The server now
      withholds columns a client's protocol does not cover (`COLUMN_SINCE`),
      the client announces its protocol and drops unknown columns, and v16
      re-pulls once.
- [ ] **56.5** Deploy the server again (`sudo server/update-server.sh`), publish
      the web build, `install-windows.ps1`; check the Uni subscription shows
      read-only on every device.

### 55. Zoom, and the web app on an iPhone  `[~]`

Asked for 2026-10-09/10, after the shelf list. Built, analyze clean, tests
green, not committed; each needs a look on the phone.

- [x] **55.1** A zoom setting (Settings, Ctrl +/−/0 on desktop), 80-150%,
      device-local, on top of the phone's own enlargement (`UiScale.zoom`).
- [x] **55.2** The web app kept off the home indicator: Flutter's web
      engine reports no safe area, so the bar sat on it and the swipe up went
      home (`web_safe_area.dart`, `viewport-fit=cover` in index.html).
- [x] **55.3** Home Screen icon: a 180px `apple-touch-icon.png` at the root,
      and the server no longer answers a missing file with the page.
- [x] **55.4** Notifications by Web Push for the web app (`server/push.js`,
      `web/push_sw.js`, Settings → Notifications). Server tests and a scratch
      server pass; not yet tried with a real browser.
- [ ] **55.5** Deploy the server (`sudo server/update-server.sh`), publish the
      web build, re-add the Home Screen icon, turn notifications on, Test.

### 44. The "Add task" and "Park a thought" quick actions do nothing  `[~]`

Reported on iOS. Fixed in `main.dart` and committed 2026-10-09 (together
with the web build); waiting on a device check.

- [x] **44.1** Cause, cold start: iOS hands the launching shortcut over as
      soon as the handler is installed, in `initState`, before the first
      build. `_layout` was still its desktop default, so "Park a thought" went
      to the footer field a phone does not draw. Every entry now goes through
      `_afterLayout`, which waits for `endOfFrame` until `_laidOut`.
- [x] **44.2** Cause, warm start: `_jumpToAddTask` opened the field without
      leaving what stands where it is drawn - the full-window calendar, a task
      expanded to the screen, a selection's bar, an open capture pane. It now
      clears all four (and the session view) before `_openAdd`.
- [ ] **44.3** Check on the iPhone, cold (app killed) and warm, both entries.
      No automated test: nothing pumps `WidgetShell` (window_manager, tray),
      and the cause was the ordering against the first frame.

### 45. Thoughts on a phone: a tab, a swipe up, a plain sheet  `[~]`

Done and committed 2026-10-09. The swipe up still wants a check on the
iPhone, against the system's go-home gesture.

- [x] **45.1** `kBarViews`: Thoughts replaces History in the bar (Tasks,
      Notes, Parked, Thoughts). The swipe between views follows for free.
- [x] **45.2** History moves to the settings sheet: one row, "History", that
      closes the sheet and opens the view. The ▾ menu on desktop keeps it.
- [x] **45.3** The Thoughts entry pulses with the pile (`ThoughtPulse`, the
      same escalation the desktop footer uses) and carries the count.
- [x] **45.4** A swipe up on the view bar opens the capture sheet (distance or
      velocity, as the bubble's was). Must start on the bar, above the iOS
      home indicator, so it does not fight the system's go-home gesture.
- [x] **45.5** While the Thoughts view is open, a one-line hint just above the
      bar: "Slide up to add a thought".
- [x] **45.6** `ThoughtSheet` goes plain: no 💭, no title, no "What just came
      to mind…" - a field, the caret in it, a close. The quick action's
      "Note on <task>" use keeps its title, since that one has to say which
      task.
- [x] **45.7** `ThoughtBubble` is removed; `ThoughtFooter` stays for desktop.
      Tests updated (thought bubble / footer tests, view bar order),
      CLAUDE.md's thought-bubble paragraphs rewritten.

Items 46-54: done, analyze clean, 598 tests green, committed 2026-10-09.

### 46. Adding a task is visible wherever the list is  `[x]`

- [x] **46.1** A "＋ Add task" line at the head of the task list on every
      layout, which becomes the add field in place when pressed (same
      `_adding` state; N and the bar's ＋ still open it). On wide windows this
      is what replaces "the ＋ is over in the rail".

### 47. The add field can aim at another workspace  `[x]`

- [x] **47.1** A workspace chip at the start of the open add field, defaulting
      to the current one; tapping it picks another. The task is written there
      and the list does not switch (a confirmation line says where it went).
- [x] **47.2** `AppState.addTask(..., workspaceUuid:)`; test.

### 48. Moving out of a shelf keeps the shelf's name  `[x]`

- [x] **48.1** When a task leaves a parked group for a workspace list - the
      group's ↗, a task's ↗, the move picker, the review's "to list" - its
      title is prefixed "<Group>: ". Not when moving shelf to shelf, and not
      twice if the prefix is already there.
- [x] **48.2** Test in `parked_test.dart`.

### 49. Select several thoughts and move them  `[x]`

Two items on the shelf, one feature.

- [x] **49.1** Selection in the thoughts panel, as on the task list (Ctrl+click
      / "Select" on touch).
- [x] **49.2** Move the selection through `move_picker.dart` to any
      workspace's list or shelf: each thought becomes a task there and is
      resolved, in one pass (`AppState.moveThoughts`). Test.

### 50. Double-click a note to edit it  `[x]`

- [x] **50.1** Journal list: double-click opens the editor directly, single
      click still opens the reader at once - the same hand-rolled timer as
      `_clickText` in `task_row.dart`, not `onDoubleTap`. Test.

### 51. View tabs in the narrow desktop window  `[x]`

- [x] **51.1** Show `ViewBar` (at the bottom, as on the phone) on a narrow
      desktop window instead of hiding the views behind the ▾ menu. Gate it
      in `Layout`, not on `touch`. (`Layout.hasViewBar`. The ▾ stays under a
      pointer - it holds History. The footer keeps its 💭 under a pointer and
      drops its meter, which the bar now carries.)

### 52. Workspace tiles: hover to expand, a pen to edit  `[x]`

- [x] **52.1** Desktop, narrow window: a workspace tile expands on hover; a ✎
      beside each title opens the editor; clicking the current workspace's
      title no longer does (`workspace_bar.dart:97`,
      `workspace_rail.dart:122` / `:246`). Read as: collapsed-rail dots expand
      into a name + ✎ tile on hover; full-rail rows show ✎ on hover; the
      bar's pill opens the switcher from its name and grows a ✎ on hover, and
      the switcher has "Edit …" for touch. **Marco to confirm this reading.**

### 53. Bigger controls in the shelf and thought editors  `[x]`

- [x] **53.1** Parked-group and thought edit controls at `Layout.tapTarget`,
      and their text at the body size rather than meta - "everything larger,
      font size too".

### 54. `[[ ]]` links between tasks and notes - design only  `[x]`

- [x] **54.1** Roadmap entry first (ROADMAP.md, *Next*: `[[ ]]` links) (link by title or id, rename, autocomplete,
      what a dangling link shows). No code until Marco has read it.

---

## Done — the 2026-09-17 list

Ten items, agreed 2026-09-17. Ordered so the bug goes first, the small ones
bank value next, and the two that rearrange the shell (the split and
multi-select) land when the rest is green. Item 3 is a moodboard to choose
from, not an implementation - the layout change waits for Marco's pick.
Item 43 was asked for on 2026-09-18, after the rest was done.

### 33. A note being written is never lost  `[x]`

- [x] **33.1** The secondary view carries a `GlobalKey` in `main.dart`, so it
      keeps its State when a resize moves it between the stacked column, the
      split row and the rail's row (all three reparent it).
- [x] **33.2** `JournalView` saves an open, changed, non-empty draft when it is
      disposed - the workspace switch closes every view, and the calendar does
      too. `onSave` is bound to the workspace the note was opened in, so the
      save cannot land in the workspace just switched to.
- [x] **33.3** Tests: resize across the split with the editor open keeps the
      text; switching workspace writes the draft into the old workspace.

### 34. Thoughts are not in the workspace's colour  `[x]`

- [x] **34.1** Bubble, capture sheet and footer use `T.accent`; the window drops
      the tint while the thoughts view owns the content area (same rule as the
      calendar's neutral chrome).

### 35. Review a shelf without expanding it  `[x]`

- [x] **35.1** Review button on the shelf card's header row, not only inside the
      expanded card.

### 36. Calendar from the home-screen quick action  `[x]`

- [x] **36.1** Fourth `ShortcutItem` (iOS budget is four), opens the calendar.

### 37. Jump from an event to its workspace  `[x]`

- [x] **37.1** `EventAction.openWorkspace` on the details card and the context
      menu, only when the event's calendar is a workspace calendar.

### 38. Collapse the rail  `[x]`

- [x] **38.1** `WorkspaceRail.collapsed`: colour dots + view icons, toggle at
      the top, stored in `settings` (`ui:railCollapsed`).

### 39. The split between the list and a view is adjustable  `[x]`

- [x] **39.1** `ui/split_pane.dart`: a draggable divider (fraction stored in
      `settings`), double-click resets. Dragged to the left edge, or its
      chevron pressed, the task pane collapses and the view has the whole
      width; a thin strip brings it back. Used by both the views' split and
      the calendar's, with separate fractions and one shared fold.

### 40. Select several tasks and move them together  `[x]`

- [x] **40.1** Ctrl+click toggles a row into a selection (Select in the action
      bar on touch); Esc clears it.
- [x] **40.2** `ui/selection_bar.dart` in place of the add field: complete,
      delete (confirmed), and one park-or-move picker. `AppState.moveTasks` - one pass, sort orders
      appended, `group_uuid` set or cleared.
- [x] **40.3** `AppState.groupsByWorkspace()` (a query per workspace, no
      store change) feeds `ui/move_picker.dart`, which also replaced the
      single-task park picker. `test/multi_select_test.dart`.

### 41. Radio favourites, custom stations, search  `[x]`

- [x] **41.1** Favourites and custom stations stored device-locally in
      `settings` as JSON. Search against Radio Browser `stations/search`.
      `sound/radio_library.dart`; `RadioBrowser.parseStations` shared by the
      genre list and the search. `test/radio_library_test.dart`.
- [x] **41.2** Sound sheet: star on a station, a Favourites row, a search field,
      and "Add a stream URL".

### 42. Layout moodboard, then A1 + B1  `[x]`

- [x] **42.1** Artifact with options for the add-task button and a compact
      calendar header: https://claude.ai/artifact/AnDvzbfL43g6xKtefVtMN7
      (A1-A3 for the add field, B1-B3 for the header; A1 + B1 recommended).
- [x] **42.2** Marco picked **A1 + B1**. A1: `_adding` in the shell, ＋ on
      `WorkspaceBar` and `WorkspaceRail` (`onAddTask`), N on desktop. B1: the
      touch header is one row - `‹ date ›`, `_ModeCycle`, and `_FilterMenu`
      as ⋯ carrying Today and quick add. Desktop header unchanged.

### 43. Double-click a task to edit it  `[x]`

Asked for on 2026-09-18, after the moodboard work. A mouse had no cheap way
into the composer once editing became the pencil in the action bar.

- [x] **43.1** `_clickText` in `task_row.dart`: the first left-click expands as
      before and arms a `Timer(kDoubleTapTimeout)`; one arriving while that is
      live puts the expansion back and calls `onOpen`. Deliberately *not*
      `GestureDetector.onDoubleTap` - that shares an arena with the tap and
      would delay every expansion by the double-click window (measured: the
      single tap does not fire for 300ms). Pointer only; touch still opens the
      action bar. `test/touch_task_row_test.dart` pins both halves, and the
      `click` helper in it waits the window out so two taps in a test are two
      clicks.

---

## Done — 0.28.0, six things from 2026-09-09

Six items, agreed 2026-09-09. Ordered by risk rather than by the order they
were asked in: the four small ones bank value first, and recurrence - which is
a schema change on both ends of the wire - goes last so the rest is already
green when it lands. Reasoning in `ROADMAP.md`.

### 26. Land on the list when you switch workspace  `[x]`

- [x] **26.1** `AppState.selectWorkspace` closes *every* view, thoughts
      included, via `_closeOtherViews()`. Test in `widget_test.dart`.

### 27. A note on a phone stops closing itself  `[x]`

- [x] **27.1** `ui/content_slot.dart`: one key and an unconditional `Stack`, so
      the content area keeps its element when `_takesScreen` removes the bar
      above and the view bar and footer below it. The rebuild was throwing away
      `JournalView`'s State, which is what holds which rung it is on.
- [x] **27.2** `test/content_slot_test.dart` - fails without the key.

### 28. Add straight to a parked shelf  `[x]`

- [x] **28.1** `AppState.addTask` takes `groupUuid`. One write, not
      add-then-park.
- [x] **28.2** `_AddToShelf` at the foot of an open group, caret kept after
      each Enter.

### 29. Reviewing a shelf is a funnel  `[x]`

- [x] **29.1** `ui/parked_review.dart` - one task per screen, four answers,
      progress line, Enter is Keep.
- [x] **29.2** A rung of `ParkedPanel` (snapshot queue, Esc walks back), not a
      view of its own. `markGroupReviewed` fires at the end, never on the way
      in - except on an empty shelf, which is finished by being looked at.
- [x] **29.3** Tests in `parked_panel_test.dart`.

### 30. Keep 30 minutes of the concentration sound on the device  `[x]`

- [x] **30.1** `sound/ambience_cache.dart` - a bout is a byte prefix of the
      chosen recording, sized from the archive metadata's `length`/`size`, kept
      in a directory beside the database under an LRU byte budget.
- [x] **30.2** `SoundService.playAmbience` plays a cached bout instantly when
      there is one and fills the cache in the background when there is not, so
      variety survives ("a different cafe every time" is the preset's whole
      point).
- [x] **30.3** A line in the sound sheet: how much is stored, and a way to
      clear it.
- [x] **30.4** Tests for the bookkeeping, with the fetch injected.

### 31. Recurring todos, two kinds  `[x]`

- [x] **31.1** Vocabulary: `Recur` parses `monthly-last`, `monthly-<n>-<wd>`
      and `every-<n><unit>` alongside the five it already knows.
- [x] **31.2** Schema v15 - `recur_from`, `recur_lead`, `recur_text`,
      `recur_notes` on `tasks`; the same four in `server/db.js` (schema,
      `addColumn`, `TABLES`). Optional columns, so `PROTOCOL` does **not**
      move.
- [x] **31.3** `$(month)`-style variables, expanded against the occurrence's
      own due date at the moment the row is written.
- [x] **31.4** One spawner, called from `completeTask` and from the reminder
      sweep, idempotent through the derived uuid - which is what lets a
      schedule rule create its next todo whether or not the last one was ever
      ticked.
- [x] **31.5** UI: the composer's Repeats row gains **Custom...**, and the
      editor behind it covers both kinds plus the lead time.
- [x] **31.6** Tests on both sides; `node --test server/`.

### 32. Release  `[~]`

- [x] **32.1** Version bump to 0.28.0+15, `FEATURES.md` changelog,
      `ROADMAP.md` *Shipped*.
- [x] **32.2** **Server deployed** 2026-09-09 - marco-apps at `5262256`, all
      four v15 columns present on the live database, 126 task rows intact,
      backup at `/var/lib/todo-sync/backups/sync-20260909-104254.db`. It had
      been sitting three releases behind at `5dc947e`.
      - **Note for the next deploy from that box:** ~680 lines of unpushed
        subscribed-.ics work were in the way and are now `stash@{0}` in
        `~/todo-app` on marco-apps, and exist nowhere else. `git stash pop`
        before pulling there again. It calls itself client **v15**, which is
        this release's number - renumber it to v16 before it lands, or a
        database that reaches 15 by one route never runs the other's migration.
- [x] **32.3a** `install-windows.ps1` - 0.28.0+15 installed and running.
- [ ] **32.3b** Put it on the phone. Most of 0.25.0, 0.26.0 and 0.27.0 has still
      only been judged on a desktop, and 0.28.0's repeat panel is a form with a
      lot in it at 390pt.

---

## Done — 0.27.0, one scale and quieter colour

Agreed 2026-09-07, after five directions were drawn at true size and compared.
`flutter analyze` clean, `flutter test` 498 passed / 6 skipped. Nothing here
touches the server, the wire or the schema. Reasoning in `ROADMAP.md`.

- [x] **25.1** Token layer in `theme.dart`: `radius` (one number), `s1`-`s5`,
      `fsBody`/`fsLabel`/`fsMeta`/`fsMenu`, `wNormal`/`wMedium`, and the two
      stated escapes `wStrong` (content emphasis) and `fsGrid` (text sized by
      the calendar's geometry, not by the scale).
- [x] **25.2** Colour split: `danger` is destructive only; `warn` is the warm
      amber for an overdue reminder or a retrying sync; `flagged` is the
      priority bar; `ok` replaces a raw hex that had gone stale.
- [x] **25.3** `workspaceColors` at ~60% chroma, same hues and order, and
      `tintedBackground` from 16% to 6%.
- [x] **25.4** Every widget repointed at the tokens - the task row, both bars,
      the shell, the sheets, the panels and the calendar. `T.fsGrid` exists
      because the pending calendar block overflowed by 5px when its labels went
      onto the general scale, which is the test suite catching exactly the
      thing it should.

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
