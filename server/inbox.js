// Things arriving from outside the app: a thought or a todo, sent by a script
// on some other machine with an inbox token (users.js INBOX_SCOPE). The
// public description, with requests and answers, is API.md at the repo root -
// keep the two in step.
//
// The server writes these rows itself, which nothing else here does: every
// other row is pushed by a device. They still go through the one merge
// (db.js writeRow), so they get a seq and every device pulls them the way it
// pulls anything else - and the routes then wake those devices with the same
// hint a push sends (events.js). The rows are built whole, with every column
// a client would write, because a device inserts a pulled row verbatim and a
// NOT NULL left out is a merge that fails on the phone, not here.
//
// What a request may name is looked up the way a person would say it: a
// workspace by its name or one of its shortcuts, a shelf by its title, both
// ignoring case. A miss answers with what there is, so the script's author
// (or their agent) can fix the request from the error alone.

import { randomUUID } from 'node:crypto';

import { writeRow } from './db.js';

/** Longest text kept. Refused rather than cut: unlike a notification, this
 *  is stored, and a truncated title stored for ever is worse than a 400. */
export const TEXT_MAX = 2000;
export const NOTES_MAX = 20000;

export class InboxError extends Error {
  constructor(message, extra = {}) {
    super(message);
    this.extra = extra;
  }
}

/**
 * A stamp the way the app writes one (models.dart `stampOf`): local wall-clock
 * reading plus its offset. Not `toISOString()`: the pile is ordered on
 * `created_at` as text, and a UTC stamp would sort an hour or two away from
 * the thoughts written on a device beside it.
 */
export function stampOf(date) {
  const pad = (n, w = 2) => String(n).padStart(w, '0');
  const offset = -date.getTimezoneOffset();
  const sign = offset < 0 ? '-' : '+';
  const abs = Math.abs(offset);
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    `.${pad(date.getMilliseconds(), 3)}${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`
  );
}

function text(input, name, max, { required = false } = {}) {
  const value = input[name];
  if (value == null || value === '') {
    if (required) throw new InboxError(`"${name}" is required`);
    return '';
  }
  if (typeof value !== 'string') throw new InboxError(`"${name}" must be a string`);
  const trimmed = value.trim();
  if (required && !trimmed) throw new InboxError(`"${name}" is required`);
  if (trimmed.length > max) throw new InboxError(`"${name}" is longer than ${max} characters`);
  return trimmed;
}

/**
 * `remind_at` as the app stores it (`reminderStamp`): a UTC instant with
 * milliseconds. It has to say its timezone - "09:00" means a different
 * moment on the server than on the machine that sent it, and guessing which
 * is how a reminder goes off an hour wrong.
 */
export function readRemindAt(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || !/(?:Z|[+-]\d{2}:?\d{2})$/i.test(value.trim())) {
    throw new InboxError(
      '"remind_at" must be an ISO 8601 time with a timezone, like ' +
        '"2026-11-02T09:00:00+01:00" or "2026-11-02T08:00:00Z"'
    );
  }
  const ms = Date.parse(value.trim());
  if (Number.isNaN(ms)) throw new InboxError(`"remind_at" is not a time: ${value}`);
  return new Date(ms).toISOString();
}

function flag(input, name) {
  const value = input[name];
  if (value == null) return false;
  if (typeof value !== 'boolean') throw new InboxError(`"${name}" must be true or false`);
  return value;
}

function body(input) {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new InboxError('Send a JSON object');
  }
  return input;
}

const fold = (s) => s.trim().replace(/^#/, '').toLowerCase();

/** The workspaces a todo may go to: live and not archived, top-level first. */
function workspacesOf(db, userId) {
  return db
    .prepare(
      `SELECT uuid, name, shortcuts, parent_uuid FROM workspaces
        WHERE user_id = ? AND deleted_at IS NULL AND archived_at IS NULL
        ORDER BY parent_uuid IS NOT NULL, sort_order, name`
    )
    .all(userId);
}

function shortcutsOf(ws) {
  try {
    const list = JSON.parse(ws.shortcuts ?? '[]');
    return Array.isArray(list) ? list.filter((s) => typeof s === 'string') : [];
  } catch {
    return [];
  }
}

/**
 * The workspace a request names, or the first top-level one when it names
 * none - the dock's first, which is the list a person would call "my list".
 */
export function findWorkspace(db, userId, name) {
  const all = workspacesOf(db, userId);
  if (!name) {
    const first = all.find((w) => w.parent_uuid == null) ?? all[0];
    if (!first) throw new InboxError('This account has no workspace yet - create one in the app');
    return first;
  }
  const want = fold(name);
  const found =
    all.find((w) => fold(w.name) === want) ??
    all.find((w) => shortcutsOf(w).some((s) => fold(s) === want));
  if (!found) {
    throw new InboxError(`No workspace called "${name}"`, {
      workspaces: all.map((w) => w.name),
    });
  }
  return found;
}

function findShelf(db, userId, ws, title) {
  const shelves = db
    .prepare(
      `SELECT uuid, title FROM parked_groups
        WHERE user_id = ? AND workspace_uuid = ? AND deleted_at IS NULL
        ORDER BY sort_order, title`
    )
    .all(userId, ws.uuid);
  const want = fold(title);
  const found = shelves.find((g) => fold(g.title) === want);
  if (!found) {
    throw new InboxError(`No shelf called "${title}" in ${ws.name}`, {
      shelves: shelves.map((g) => g.title),
    });
  }
  return found;
}

/** The app's `nextSortOrder`: after every task and project on that list. */
function nextSortOrder(db, userId, workspaceUuid) {
  const row = db
    .prepare(
      `SELECT MAX(m) AS m FROM (
         SELECT MAX(sort_order) AS m FROM tasks WHERE user_id = ? AND workspace_uuid = ?
         UNION ALL
         SELECT MAX(sort_order) AS m FROM workspaces WHERE user_id = ? AND parent_uuid = ?)`
    )
    .get(userId, workspaceUuid, userId, workspaceUuid);
  return (row?.m ?? -1) + 1;
}

/**
 * POST /api/thought. Returns what was written and the cursor to hint with;
 * throws InboxError for a request that cannot be written.
 */
export function addThought(db, userId, input, now = new Date()) {
  input = body(input);
  const words = text(input, 'text', TEXT_MAX, { required: true });
  const remindAt = readRemindAt(input.remind_at);
  const notify = flag(input, 'notify');
  const stamp = stampOf(now);
  const uuid = randomUUID();

  const cursor = writeRow(db, userId, 'side_thoughts', {
    uuid,
    text: words,
    created_at: stamp,
    resolved_at: null,
    audio: null,
    audio_ms: null,
    remind_at: remindAt,
    updated_at: stamp,
    deleted_at: null,
  });
  return {
    cursor,
    result: { id: uuid, text: words, remind_at: remindAt },
    notification: notify ? { title: 'Thought', body: words, url: '/' } : null,
  };
}

/** POST /api/todo. As [addThought]. */
export function addTodo(db, userId, input, now = new Date()) {
  input = body(input);
  // `title` too: it is what a script is likeliest to call it.
  const words =
    input.text != null
      ? text(input, 'text', TEXT_MAX, { required: true })
      : text(input, 'title', TEXT_MAX, { required: true });
  const notes = text(input, 'notes', NOTES_MAX);
  const remindAt = readRemindAt(input.remind_at);
  const high = flag(input, 'high_priority');
  const notify = flag(input, 'notify');
  if (input.workspace != null && typeof input.workspace !== 'string') {
    throw new InboxError('"workspace" must be a string');
  }
  if (input.shelf != null && typeof input.shelf !== 'string') {
    throw new InboxError('"shelf" must be a string');
  }

  const ws = findWorkspace(db, userId, input.workspace?.trim() || null);
  const shelf = input.shelf?.trim() ? findShelf(db, userId, ws, input.shelf) : null;
  const stamp = stampOf(now);
  const uuid = randomUUID();

  const cursor = writeRow(db, userId, 'tasks', {
    uuid,
    workspace_uuid: ws.uuid,
    text: words,
    created_at: stamp,
    completed_at: null,
    sort_order: nextSortOrder(db, userId, ws.uuid),
    in_progress: 0,
    remind_at: remindAt,
    group_uuid: shelf?.uuid ?? null,
    event_uuid: null,
    notes,
    priority: high ? 1 : 0,
    recur: null,
    recur_from: null,
    recur_lead: null,
    recur_text: null,
    recur_notes: null,
    audio: null,
    audio_ms: null,
    updated_at: stamp,
    deleted_at: null,
  });
  return {
    cursor,
    result: {
      id: uuid,
      text: words,
      workspace: ws.name,
      ...(shelf ? { shelf: shelf.title } : {}),
      remind_at: remindAt,
    },
    notification: notify
      ? { title: shelf ? `${ws.name} · ${shelf.title}` : ws.name, body: words, url: '/' }
      : null,
  };
}
