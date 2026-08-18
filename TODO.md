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

Steps 0-6 are done; the mobile and calendar list below is what is next. See
*Done* for what landed.

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

### 1. CI builds more than iOS  `[~]`

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
- [ ] Push the branch and watch the run go green before calling it done.
      **Not done yet — the workflow is unverified until it has run once.**

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

### 7. A horizontal swipe moves through time, not through modes  `[ ]`

Today `_stepMode` maps a swipe to D/W/Y. It should move the **period**: next /
previous week in week view, day in day view, year in year view. D/W/Y stays on
the toolbar, which is where it is visible anyway.

- [ ] Repoint the swipe at the existing step-forward / step-back path.
- [ ] Clamp nothing — time has no ends.
- [ ] `CLAUDE.md` documents the old behaviour and its justification; rewrite
      that paragraph rather than leaving it lying.

### 8. The date label gets its own line  `[ ]`

In day and week view the month and date are cut off. Put the label **below** the
row with the arrows, in a smaller font, so the arrows keep their finger-sized
targets and the label gets the full width.

### 9. The event editor matches every other editor  `[ ]`

Full width, against the bottom edge on a phone, drawn from `T.*` — the same
treatment the task composer got in 0.22.0, which stopped it looking like a
different application. No stock Material card.

### 10. Quick add: pick the block up, then drop it  `[ ]`

- [ ] Resizing stops while the finger is still moving. Find out whether the
      0.23.1 grip fix covers it; if not, the recogniser is losing the pointer.
- [ ] Moving runs faster than the finger — the delta bug 0.23.1 fixed. Verify on
      current main first.
- [ ] Then the redesign Marco asked for: a long press **lifts** the block off
      the grid (it follows the finger as a dragged object, not as a block being
      re-laid-out every frame), and it lands where it is dropped.
- [ ] **Edge zones** while dragging: holding a lifted block against the left or
      right edge steps the grid one day / one week, so a block can be moved
      across the boundary of what is on screen.

### 11. Opening an event shows a full-width card, not a white rectangle  `[ ]`

Reported: title, delete button, then a large empty white rectangle running to
the bottom. Reproduce, find what is claiming that space (a description box with
no intrinsic height is the first suspect), and make the card full width like the
editor in step 9.

### 12. Pinch to zoom the hour height  `[ ]`

Day and week views: a pinch changes how tall an hour is drawn. One stored value,
clamped, remembered in `settings` like the other calendar prefs. Note it has to
coexist with the vertical scroll and with the long-press-drag to create.

### 13. Quick-add blocks that vanish  `[ ]`

Reported: blocks laid out with the bolt disappear after moving to the next week
or the year view, and pressing the bolt again does not save them. The 0.23.1
commit-rule fix addresses one cause of this; reproduce on current main, and if
it survives, the suspects are (a) blocks held for a window that is no longer on
screen, (b) a commit path that clears the list before the write completes.
**This one is data loss — it gets a test either way.**

### 14. Side thoughts as a bubble  `[ ]`

- [ ] On mobile, move the side-thought entry point to a floating bubble sitting
      above the Tasks / Notes / Parked bar — the shape every chat widget on the
      web uses, and reachable with a thumb.
- [ ] The open panel currently covers the **title bar**, so its close button sits
      under the concentration-sound button and you press the wrong one. The
      panel must sit below `TitleBar.height` like every other sheet, or own a
      close control that cannot collide.

### 15. The calendar gets its own colour  `[ ]`

It is not a view of the workspace you came from and should not be tinted like
one — it can show every workspace at once. Neutral chrome: greyish in dark mode,
eggshell in light. **Note the light theme does not exist yet** (it is in
`FEATURES.md`'s backlog), so define both tokens and use the dark one now.
Events keep their own calendar's colour — that is the point of the week view.

### 16. Commit  `[ ]`

---

## Done

- **0** Release 0.23.1: an edit no longer loses to an older one, and a phone can
  reach delete. (`5a9eace`, plus `30792a2` for the planning docs.)
- **1** Build every platform in CI, not just the one that could not regress
  quietly. (`6036c0c`) — **not yet proven**: the workflow has never run, because
  the branch has not been pushed.
- **2** Let a block of time repeat, as one row rather than fifty-two.
  (`b69cf4e`, schema v13)
- **3** Let an event be a whole day, and stop flattening the ones that arrive as
  days. (`5f932d7`, schema v14)
- **4** Give "not on this device" a way out that does not need blob sync.
  (`65d2f6b`)
- **5** Delete the Tauri build, three years after it stopped being the app.
  (`be311fd`, tagged `legacy-tauri`)
- **6** Version bumped to 0.24.0.
