# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small, always-on-top desktop **todo widget** for Windows (a checklist-capable
replacement for Sticky Notes). You add tasks, check them off — checked items
animate away and are logged to a local SQLite database so a history/overview of
completed work is preserved across restarts.

Built with **Tauri v2** (Rust backend) + a **vanilla TypeScript** frontend bundled by Vite.

## Commands

Run all commands from the repo root. The Rust toolchain must be on `PATH`
(`%USERPROFILE%\.cargo\bin`); it is not added to the shell automatically here.

| Task | Command |
| --- | --- |
| Run the app in dev (hot-reload frontend + Rust) | `npm run tauri dev` |
| Build a production bundle/installer | `npm run tauri build` |
| Build/type-check the frontend only | `npm run build` (`tsc && vite build`) |
| Compile/check the Rust side only | `cd src-tauri && cargo build` (or `cargo check`) |
| Lint Rust | `cd src-tauri && cargo clippy` |

There is no test suite yet. The frontend has no test runner configured, and
`src-tauri` has no `#[cfg(test)]` modules — add `cargo test` targets in
`src-tauri` and a frontend runner before claiming tests exist.

`npm run tauri build` first runs `npm run build` (see `beforeBuildCommand` in
`tauri.conf.json`), so the frontend always ships fresh.

## Architecture

The app is two processes bridged by Tauri's IPC:

- **Frontend** (`src/`, `index.html`) — pure DOM, no framework. `src/main.ts`
  owns all UI logic and calls the Rust backend via `invoke()` from
  `@tauri-apps/api/core`. Window controls (pin/minimize/close) go through
  `getCurrentWindow()` from `@tauri-apps/api/window`.
- **Backend** (`src-tauri/src/lib.rs`) — owns the database and exposes
  `#[tauri::command]` functions. `main.rs` is a thin shim that calls
  `todo_widget_lib::run()`.

### Data model — the single source of truth is SQLite

There is **one `tasks` table**, not separate active/done tables. The
`completed_at` column is the state flag:

- `completed_at IS NULL` → **active** task (shown in the main list)
- `completed_at IS NOT NULL` → **completed** task (shown in History; the
  timestamp is when it was checked off)

Timestamps are RFC 3339 strings (`chrono::Local::now().to_rfc3339()`). The DB
lives at the OS app-data dir (`app.path().app_data_dir()` → `todo.db`), created
and migrated in the Tauri `.setup()` hook. The connection is a single
`Mutex<Connection>` stored as managed state (`struct Db`), so every command
locks it.

Backend commands (keep frontend `invoke` names in sync with these):
`add_task`, `list_active`, `complete_task`, `delete_task`, `list_history`.
`complete_task` sets `completed_at` (keeps the row for history); `delete_task`
removes the row entirely (dismiss without logging).

The `in_progress` column is the focus-mode flag, and it is **exclusive and
global**: `set_task_in_progress(id, true)` clears it on every other row, so at
most one task is ever flagged. `find_in_progress` returns that task (if any) and
is what lets the frontend restore focus mode on launch.

### Completion flow

Checking a box does **not** immediately drop the row. `main.ts` adds the
`.completing` CSS class to play the slide-out animation, awaits the backend
call, then removes the element and re-fetches after the animation timeout
(~320ms — kept in sync with the `slide-out` keyframe duration in
`src/styles.css`). If you change one duration, change the other.

### Focus mode

Activating a task (▶) hides everything but the title bar and flies the task into
a tile in the middle of the window. The pieces:

- `.widget.focus-mode` fades out every child except `.titlebar` and `.focus-view`
  (opacity only — the panels **keep their layout**, which is what lets the tile
  fly back to its exact row on exit).
- The hero flight is a FLIP in `enterFocus`/`exitFocus`/`flyTile` (`main.ts`): both
  boxes are measured while each element is still in normal flow, then the tile is
  pinned to the start box with transitions off, reflowed, and released to the end
  box. It animates `left/top/width/height` rather than a scale transform — a
  non-uniform scale would stretch the text.
- `HERO_MS` in `main.ts` mirrors `--hero-dur` in `src/styles.css`. **Change both
  together** (same deal as the slide-out above).
- The title bar sits at `z-index: 3`, above the overlay's `2`, so the window stays
  draggable/closable while focused. Anything that must stay reachable in focus
  mode needs to live there.
- Paths that touch hidden UI (the add/thought fields, history, the close guard's
  footer flash) call `exitFocus()` first — otherwise they'd act on, or flash,
  something behind the overlay.

### Window / look

The window is configured in `src-tauri/tauri.conf.json` under `app.windows`:
small (340×480), `decorations: false` (frameless), `transparent: true`,
`alwaysOnTop: true`, `shadow: true`. Because there is no OS title bar:

- The custom title bar (`.titlebar` in `index.html`) is the drag handle via the
  `data-tauri-drag-region` attribute. Any new draggable area needs that
  attribute **and** interactive children must not have it (they'd swallow clicks).
- Rounded corners come from CSS on `.widget`; the OS window is transparent so the
  corners show through. The acrylic/blur look is `backdrop-filter` in CSS.

### Permissions

Tauri v2 gates every API behind capabilities. Window controls used by the
frontend are allow-listed in `src-tauri/capabilities/default.json`
(`core:window:allow-start-dragging`, `allow-minimize`, `allow-close`,
`allow-set-always-on-top`). **If you call a new Tauri API from the frontend and
it fails at runtime with a permission error, add the matching permission here.**

## Gotchas

- **Renaming the crate**: the lib name `todo_widget_lib` is referenced by
  `main.rs`. The `_lib` suffix is required on Windows (bin/lib name collision) —
  don't drop it.
- First `cargo build` is slow (compiles Tauri + bundles SQLite from source via
  `rusqlite`'s `bundled` feature). The `bundled` feature means no system SQLite
  is needed, but a C compiler (MSVC) is required.
- Prereqs on a fresh machine: Rust (rustup), Node 18+, MSVC C++ build tools, and
  WebView2 (preinstalled on Windows 11).
