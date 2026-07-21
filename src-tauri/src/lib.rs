use rusqlite::Connection;
use serde::Serialize;
use std::sync::Mutex;
use tauri::{Manager, State};

/// A todo item. Active items have `completed_at == None`; finished items keep
/// their completion timestamp so they can be shown in the history overview.
#[derive(Serialize)]
struct Task {
    id: i64,
    text: String,
    created_at: String,
    completed_at: Option<String>,
    workspace_id: i64,
    in_progress: bool,
}

/// A "side thought" — a quick note jotted down to be tidied later. Unlike tasks,
/// these are *never* deleted: once acted on (promoted to a task or thrown away)
/// the row is kept with a `resolved_at` timestamp so every thought is preserved.
/// Side thoughts are global — not scoped to a workspace.
#[derive(Serialize)]
struct SideThought {
    id: i64,
    text: String,
    created_at: String,
    resolved_at: Option<String>,
}

/// A separate todo list ("Arbeitsbereich" / workspace) — e.g. "Uni", "Work".
/// Every task belongs to exactly one workspace.
#[derive(Serialize)]
struct Workspace {
    id: i64,
    name: String,
    color: String,
    sort_order: i64,
}

/// Managed application state: a single SQLite connection behind a mutex.
struct Db(Mutex<Connection>);

fn init_db(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS workspaces (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL,
            color      TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            created_at TEXT NOT NULL
        )",
        [],
    )?;

    let workspace_count: i64 = conn.query_row("SELECT COUNT(*) FROM workspaces", [], |r| r.get(0))?;
    if workspace_count == 0 {
        conn.execute(
            "INSERT INTO workspaces (name, color, sort_order, created_at) VALUES ('Tasks', '#6c8cff', 0, ?1)",
            rusqlite::params![now()],
        )?;
    }
    let default_workspace_id: i64 =
        conn.query_row("SELECT id FROM workspaces ORDER BY sort_order, id LIMIT 1", [], |r| r.get(0))?;

    conn.execute(
        "CREATE TABLE IF NOT EXISTS tasks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            text         TEXT NOT NULL,
            created_at   TEXT NOT NULL,
            completed_at TEXT,
            workspace_id INTEGER NOT NULL DEFAULT 1,
            sort_order   INTEGER NOT NULL DEFAULT 0,
            in_progress  INTEGER NOT NULL DEFAULT 0
        )",
        [],
    )?;
    // Migrate DBs created before workspaces existed.
    let has_workspace_col = conn.prepare("SELECT workspace_id FROM tasks LIMIT 1").is_ok();
    if !has_workspace_col {
        conn.execute("ALTER TABLE tasks ADD COLUMN workspace_id INTEGER NOT NULL DEFAULT 1", [])?;
    }
    conn.execute(
        "UPDATE tasks SET workspace_id = ?1 WHERE workspace_id NOT IN (SELECT id FROM workspaces)",
        rusqlite::params![default_workspace_id],
    )?;
    // Migrate DBs created before manual reordering existed. Backfill sort_order
    // from id so the previous (creation-order) ordering is preserved.
    let has_sort_order_col = conn.prepare("SELECT sort_order FROM tasks LIMIT 1").is_ok();
    if !has_sort_order_col {
        conn.execute("ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0", [])?;
        conn.execute("UPDATE tasks SET sort_order = id", [])?;
    }
    // Migrate DBs created before the "in progress" flag existed.
    let has_in_progress_col = conn.prepare("SELECT in_progress FROM tasks LIMIT 1").is_ok();
    if !has_in_progress_col {
        conn.execute("ALTER TABLE tasks ADD COLUMN in_progress INTEGER NOT NULL DEFAULT 0", [])?;
    }

    conn.execute(
        "CREATE TABLE IF NOT EXISTS side_thoughts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            text        TEXT NOT NULL,
            created_at  TEXT NOT NULL,
            resolved_at TEXT
        )",
        [],
    )?;
    Ok(())
}

/// Current local time as an RFC 3339 string (what every timestamp column stores).
fn now() -> String {
    chrono::Local::now().to_rfc3339()
}

fn read_task(row: &rusqlite::Row) -> rusqlite::Result<Task> {
    Ok(Task {
        id: row.get(0)?,
        text: row.get(1)?,
        created_at: row.get(2)?,
        completed_at: row.get(3)?,
        workspace_id: row.get(4)?,
        in_progress: row.get(5)?,
    })
}

#[tauri::command]
fn list_active(db: State<Db>, workspace_id: i64) -> Result<Vec<Task>, String> {
    let conn = db.0.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT id, text, created_at, completed_at, workspace_id, in_progress FROM tasks
             WHERE completed_at IS NULL AND workspace_id = ?1 ORDER BY sort_order, id",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([workspace_id], read_task)
        .map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn add_task(db: State<Db>, workspace_id: i64, text: String) -> Result<Task, String> {
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err("Task text is empty".into());
    }
    let conn = db.0.lock().unwrap();
    let created_at = now();
    let sort_order: i64 = conn
        .query_row(
            "SELECT COALESCE(MAX(sort_order), 0) + 1 FROM tasks
             WHERE workspace_id = ?1 AND completed_at IS NULL",
            rusqlite::params![workspace_id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO tasks (text, created_at, workspace_id, sort_order) VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![text, created_at, workspace_id, sort_order],
    )
    .map_err(|e| e.to_string())?;
    Ok(Task {
        id: conn.last_insert_rowid(),
        text,
        created_at,
        completed_at: None,
        workspace_id,
        in_progress: false,
    })
}

/// Flag (or unflag) the task currently being worked on. Exclusive and global:
/// setting one clears every other task in every workspace, because `in_progress`
/// is what drives the frontend's single-task focus view.
#[tauri::command]
fn set_task_in_progress(db: State<Db>, id: i64, in_progress: bool) -> Result<(), String> {
    let conn = db.0.lock().unwrap();
    if in_progress {
        conn.execute("UPDATE tasks SET in_progress = 0 WHERE id != ?1", rusqlite::params![id])
            .map_err(|e| e.to_string())?;
    }
    conn.execute(
        "UPDATE tasks SET in_progress = ?1 WHERE id = ?2",
        rusqlite::params![in_progress, id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// The task currently in progress, if any — regardless of workspace. Lets the
/// frontend restore the focus view (and switch to the right workspace) on launch.
/// Completed tasks never count, so checking one off elsewhere can't resurrect focus.
#[tauri::command]
fn find_in_progress(db: State<Db>) -> Result<Option<Task>, String> {
    let conn = db.0.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT id, text, created_at, completed_at, workspace_id, in_progress FROM tasks
             WHERE in_progress = 1 AND completed_at IS NULL ORDER BY id LIMIT 1",
        )
        .map_err(|e| e.to_string())?;
    let mut rows = stmt.query_map([], read_task).map_err(|e| e.to_string())?;
    match rows.next() {
        Some(task) => Ok(Some(task.map_err(|e| e.to_string())?)),
        None => Ok(None),
    }
}

/// Persist a new manual order for active tasks: `order` is the list of task ids
/// top-to-bottom as dragged in the UI.
#[tauri::command]
fn reorder_tasks(db: State<Db>, order: Vec<i64>) -> Result<(), String> {
    let mut conn = db.0.lock().unwrap();
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    for (position, id) in order.iter().enumerate() {
        tx.execute(
            "UPDATE tasks SET sort_order = ?1 WHERE id = ?2",
            rusqlite::params![position as i64, id],
        )
        .map_err(|e| e.to_string())?;
    }
    tx.commit().map_err(|e| e.to_string())?;
    Ok(())
}

/// Mark a task done. It stays in the DB (for history) but leaves the active list.
#[tauri::command]
fn complete_task(db: State<Db>, id: i64) -> Result<(), String> {
    let conn = db.0.lock().unwrap();
    conn.execute(
        "UPDATE tasks SET completed_at = ?1, in_progress = 0 WHERE id = ?2 AND completed_at IS NULL",
        rusqlite::params![now(), id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Permanently remove a task (used for dismissing an active item without logging it).
#[tauri::command]
fn delete_task(db: State<Db>, id: i64) -> Result<(), String> {
    let conn = db.0.lock().unwrap();
    conn.execute("DELETE FROM tasks WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn list_history(db: State<Db>, workspace_id: i64, limit: i64) -> Result<Vec<Task>, String> {
    let conn = db.0.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT id, text, created_at, completed_at, workspace_id, in_progress FROM tasks
             WHERE completed_at IS NOT NULL AND workspace_id = ?1 ORDER BY completed_at DESC LIMIT ?2",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(rusqlite::params![workspace_id, limit], read_task)
        .map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())
}

fn read_workspace(row: &rusqlite::Row) -> rusqlite::Result<Workspace> {
    Ok(Workspace {
        id: row.get(0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        sort_order: row.get(3)?,
    })
}

#[tauri::command]
fn list_workspaces(db: State<Db>) -> Result<Vec<Workspace>, String> {
    let conn = db.0.lock().unwrap();
    let mut stmt = conn
        .prepare("SELECT id, name, color, sort_order FROM workspaces ORDER BY sort_order, id")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], read_workspace)
        .map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn add_workspace(db: State<Db>, name: String, color: String) -> Result<Workspace, String> {
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err("Workspace name is empty".into());
    }
    let conn = db.0.lock().unwrap();
    let sort_order: i64 = conn
        .query_row("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM workspaces", [], |r| r.get(0))
        .map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO workspaces (name, color, sort_order, created_at) VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![name, color, sort_order, now()],
    )
    .map_err(|e| e.to_string())?;
    Ok(Workspace {
        id: conn.last_insert_rowid(),
        name,
        color,
        sort_order,
    })
}

#[tauri::command]
fn update_workspace(db: State<Db>, id: i64, name: String, color: String) -> Result<(), String> {
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err("Workspace name is empty".into());
    }
    let conn = db.0.lock().unwrap();
    conn.execute(
        "UPDATE workspaces SET name = ?1, color = ?2 WHERE id = ?3",
        rusqlite::params![name, color, id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Delete a workspace. Its tasks (active and history) are reassigned to the
/// remaining workspace with the lowest sort order — nothing is ever deleted.
/// Refuses to delete the last remaining workspace.
#[tauri::command]
fn delete_workspace(db: State<Db>, id: i64) -> Result<(), String> {
    let conn = db.0.lock().unwrap();
    let total: i64 = conn
        .query_row("SELECT COUNT(*) FROM workspaces", [], |r| r.get(0))
        .map_err(|e| e.to_string())?;
    if total <= 1 {
        return Err("Can't delete the only remaining workspace".into());
    }
    let fallback_id: i64 = conn
        .query_row(
            "SELECT id FROM workspaces WHERE id != ?1 ORDER BY sort_order, id LIMIT 1",
            rusqlite::params![id],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE tasks SET workspace_id = ?1 WHERE workspace_id = ?2",
        rusqlite::params![fallback_id, id],
    )
    .map_err(|e| e.to_string())?;
    conn.execute("DELETE FROM workspaces WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| e.to_string())?;
    Ok(())
}

fn read_side_thought(row: &rusqlite::Row) -> rusqlite::Result<SideThought> {
    Ok(SideThought {
        id: row.get(0)?,
        text: row.get(1)?,
        created_at: row.get(2)?,
        resolved_at: row.get(3)?,
    })
}

/// Record a new side thought. Every thought is written to the DB the moment it
/// is captured — it stays there forever, whether it later becomes a task or is
/// thrown away.
#[tauri::command]
fn add_side_thought(db: State<Db>, text: String) -> Result<SideThought, String> {
    let text = text.trim().to_string();
    if text.is_empty() {
        return Err("Side thought is empty".into());
    }
    let conn = db.0.lock().unwrap();
    let created_at = now();
    conn.execute(
        "INSERT INTO side_thoughts (text, created_at) VALUES (?1, ?2)",
        rusqlite::params![text, created_at],
    )
    .map_err(|e| e.to_string())?;
    Ok(SideThought {
        id: conn.last_insert_rowid(),
        text,
        created_at,
        resolved_at: None,
    })
}

/// Pending (un-tidied) side thoughts — the ones still nagging the user.
#[tauri::command]
fn list_side_thoughts(db: State<Db>) -> Result<Vec<SideThought>, String> {
    let conn = db.0.lock().unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT id, text, created_at, resolved_at FROM side_thoughts
             WHERE resolved_at IS NULL ORDER BY id",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], read_side_thought)
        .map_err(|e| e.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())
}

/// Tidy a side thought away. The row is kept (with a `resolved_at` stamp) whether
/// it was promoted to a task or simply discarded — nothing is ever deleted.
#[tauri::command]
fn resolve_side_thought(db: State<Db>, id: i64) -> Result<(), String> {
    let conn = db.0.lock().unwrap();
    conn.execute(
        "UPDATE side_thoughts SET resolved_at = ?1 WHERE id = ?2 AND resolved_at IS NULL",
        rusqlite::params![now(), id],
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let dir = app.path().app_data_dir().expect("resolve app data dir");
            std::fs::create_dir_all(&dir).ok();
            let conn = Connection::open(dir.join("todo.db")).expect("open database");
            init_db(&conn).expect("initialize database");
            app.manage(Db(Mutex::new(conn)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            add_task,
            list_active,
            reorder_tasks,
            set_task_in_progress,
            find_in_progress,
            complete_task,
            delete_task,
            list_history,
            add_side_thought,
            list_side_thoughts,
            resolve_side_thought,
            list_workspaces,
            add_workspace,
            update_workspace,
            delete_workspace
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
