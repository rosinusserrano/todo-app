# Todo Widget

A small, always-on-top todo list widget for Windows — a checklist-capable
alternative to Sticky Notes. Add tasks, check them off (they animate away), and
every completed item is logged to a local SQLite database so you keep a history
of what you got done.

Built with [Tauri v2](https://tauri.app) (Rust) and a vanilla TypeScript frontend.

## Features

- Frameless, always-on-top floating window (pin toggle to release it)
- Add tasks, check them off, or dismiss without logging
- Completed tasks persist to SQLite and show up in a History view
- Drag by the title bar; minimize/close from the title bar buttons

## Develop

Prerequisites: [Rust](https://www.rust-lang.org/tools/install), Node 18+, MSVC
C++ build tools, and WebView2 (preinstalled on Windows 11).

```sh
npm install
npm run tauri dev      # run with hot reload
npm run tauri build    # produce an installer / standalone exe
```

## Where things live

- `src/` — frontend (`main.ts`, `styles.css`) and `index.html`
- `src-tauri/src/lib.rs` — Rust backend: SQLite + `#[tauri::command]` API
- `src-tauri/tauri.conf.json` — window size, always-on-top, transparency
- `src-tauri/capabilities/default.json` — Tauri permission allow-list

See [CLAUDE.md](./CLAUDE.md) for architecture notes.

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
