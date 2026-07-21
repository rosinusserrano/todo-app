import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { register } from "@tauri-apps/plugin-global-shortcut";

interface Task {
  id: number;
  text: string;
  created_at: string;
  completed_at: string | null;
  workspace_id: number;
  in_progress: boolean;
}

interface SideThought {
  id: number;
  text: string;
  created_at: string;
  resolved_at: string | null;
}

interface Workspace {
  id: number;
  name: string;
  color: string;
  sort_order: number;
}

const appWindow = getCurrentWindow();

const WORKSPACE_COLORS = [
  "#6c8cff", // accent blue
  "#7ee3a1", // mint
  "#ffcf6c", // amber
  "#ff6c6c", // red
  "#ff8cd9", // pink
  "#b28cff", // violet
  "#6cd9ff", // cyan
  "#e0e0e0", // neutral
];

const LAST_WORKSPACE_KEY = "todo-widget:last-workspace-id";
const NUDGE_KEY = "todo-widget:nudge-enabled";

// Duration of the focus-mode hero flight — mirrors --hero-dur in styles.css.
// If you change one, change the other.
const HERO_MS = 380;

// --- element handles (resolved on DOMContentLoaded) ---
let widget: HTMLElement;
let focusView: HTMLElement;
let focusTile: HTMLElement;
let focusText: HTMLElement;
let focusDoneBtn: HTMLButtonElement;
let focusExitBtn: HTMLButtonElement;
let nudgeBtn: HTMLButtonElement;
let addForm: HTMLFormElement;
let addInput: HTMLInputElement;
let taskList: HTMLUListElement;
let emptyState: HTMLElement;
let activeView: HTMLElement;
let historyView: HTMLElement;
let historyList: HTMLUListElement;
let historyEmpty: HTMLElement;
let pinBtn: HTMLButtonElement;
let thoughtList: HTMLUListElement;
let thoughtForm: HTMLFormElement;
let thoughtInput: HTMLInputElement;
let thoughtBtn: HTMLButtonElement;
let footerBar: HTMLElement;
let thoughtCountEl: HTMLElement;
let workspaceList: HTMLUListElement;
let workspaceAddBtn: HTMLButtonElement;
let workspaceForm: HTMLFormElement;
let workspaceNameInput: HTMLInputElement;
let workspaceColorPicker: HTMLElement;
let workspaceDeleteBtn: HTMLButtonElement;
let workspaceCancelBtn: HTMLButtonElement;

let alwaysOnTop = true;

// Pending side-thought count, kept in sync so the footer bar can read it cheaply.
let thoughtCount = 0;

// Set by the Enter keydown handler right before a form's submit event fires, so
// the submit handler knows whether Ctrl was held (chain-entry) or not (close/blur).
let addCtrlEnter = false;
let thoughtCtrlEnter = false;

// The task currently owning the focus view, or null when the list is showing.
// Mirrors the `in_progress` flag in the DB, which is exclusive and global.
let focusTaskId: number | null = null;
let nudgeEnabled = true;
let heroTimer: number | null = null;
let hideTimer: number | null = null;

let workspaces: Workspace[] = [];
let currentWorkspaceId: number | null = null;
// Set while the workspace form is editing an existing workspace (vs. creating one).
let editingWorkspaceId: number | null = null;
let selectedColor = WORKSPACE_COLORS[0];

async function refreshActive(): Promise<void> {
  if (currentWorkspaceId === null) return;
  const tasks = await invoke<Task[]>("list_active", { workspaceId: currentWorkspaceId });
  taskList.replaceChildren(...tasks.map(renderActive));
  emptyState.classList.toggle("hidden", tasks.length > 0);
}

function renderActive(task: Task): HTMLLIElement {
  const li = document.createElement("li");
  li.className = "task";
  li.dataset.id = String(task.id);

  // Only the handle initiates a drag (li.draggable flips on for the duration)
  // so dragging doesn't fight with clicking the checkbox or selecting text.
  const handle = document.createElement("span");
  handle.className = "task-drag";
  handle.title = "Drag to reorder";
  handle.textContent = "⠿";
  handle.addEventListener("mousedown", () => {
    li.draggable = true;
  });
  // A plain click (mousedown without an actual drag) never fires dragend, so
  // reset here too — otherwise the row would stay draggable from any point.
  handle.addEventListener("mouseup", () => {
    li.draggable = false;
  });

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.className = "check";
  checkbox.addEventListener("change", () => completeTask(li, task.id));

  const label = document.createElement("span");
  label.className = "task-text";
  label.textContent = task.text;

  const activate = document.createElement("button");
  activate.className = "task-activate" + (task.in_progress ? " active" : "");
  activate.title = "Work on this — hides everything else";
  activate.textContent = "▶";
  activate.addEventListener("click", () => startFocus(task, li));

  const del = document.createElement("button");
  del.className = "task-del";
  del.title = "Delete (don't log)";
  del.textContent = "✕";
  del.addEventListener("click", () => deleteTask(li, task.id));

  li.classList.toggle("in-progress", task.in_progress);

  li.addEventListener("dragstart", (e) => {
    // Chromium (and WebView2) needs a data payload set on dragstart or it
    // cancels the drag before dragover ever fires.
    e.dataTransfer?.setData("text/plain", String(task.id));
    if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
    li.classList.add("dragging");
  });
  li.addEventListener("dragend", () => {
    li.classList.remove("dragging");
    li.draggable = false;
    void persistTaskOrder();
  });

  li.append(handle, checkbox, label, activate, del);
  return li;
}

// --- focus mode ---
// One task at a time gets the whole window: the list, the workspace tabs, the
// add field and the thoughts footer all dissolve, and the task flies out of its
// row into a tile in the middle. `in_progress` in the DB is the source of truth
// (exclusive and global, enforced backend-side), so focus survives a restart.

// ▶ on a row: claim the in-progress flag, then fly that row into the middle.
async function startFocus(task: Task, li: HTMLLIElement): Promise<void> {
  await invoke("set_task_in_progress", { id: task.id, inProgress: true });
  enterFocus(task, li);
  await refreshActive();
}

// The hero flight. Both the row's box and the tile's resting box are measured
// while each is still in normal flow; only then is the tile pinned to the row's
// geometry and released to its own, with CSS interpolating left/top/width/height
// (and font-size). Animating the box rather than a scale transform is what keeps
// the text from stretching mid-flight.
//
// `sourceLi` is null when there's no row to fly from — e.g. restoring focus at
// launch — in which case the tile simply appears.
function enterFocus(task: Task, sourceLi: HTMLLIElement | null): void {
  cancelFocusTimers();
  clearGeometry();

  focusTaskId = task.id;
  focusText.textContent = task.text;

  const from = sourceLi ? sourceLi.getBoundingClientRect() : null;

  focusView.classList.remove("hidden", "leaving");
  widget.classList.add("focus-mode");

  if (from) {
    const origin = focusView.getBoundingClientRect();
    const to = focusTile.getBoundingClientRect();
    flyTile(from, to, origin, "13px", "");
    heroTimer = window.setTimeout(clearGeometry, HERO_MS);
  }

  // A frame later, so the fade actually transitions instead of snapping on.
  requestAnimationFrame(() => focusView.classList.add("ready"));

  // Only once the tile has landed: .nudging is a transform animation, and the
  // hero flight is driving left/top/width/height until then.
  if (from) window.setTimeout(applyNudge, HERO_MS);
  else applyNudge();
}

// Back to the list: drop the flag, fade the panels back in, and fly the tile
// home to its row. If that row isn't there any more the tile just dissolves
// where it stands, along with the rest of the overlay.
async function exitFocus(): Promise<void> {
  const id = focusTaskId;
  if (id === null) return;
  focusTaskId = null;
  applyNudge();
  cancelFocusTimers();

  await invoke("set_task_in_progress", { id, inProgress: false });

  const from = focusTile.getBoundingClientRect();
  const origin = focusView.getBoundingClientRect();

  widget.classList.remove("focus-mode");
  focusView.classList.remove("ready");
  await refreshActive();

  const target = taskList.querySelector<HTMLLIElement>(`.task[data-id="${id}"]`);
  if (target) flyTile(from, target.getBoundingClientRect(), origin, "", "13px");

  focusView.classList.add("leaving");
  hideTimer = window.setTimeout(() => {
    focusView.classList.add("hidden");
    clearGeometry();
    hideTimer = null;
  }, HERO_MS);
}

// Checked off from the focus view: no fly-back, because the row it would land on
// is on its way out too. The tile drops away and the list fades in behind it.
async function completeFromFocus(): Promise<void> {
  const id = focusTaskId;
  if (id === null) return;
  focusTaskId = null;
  applyNudge();
  cancelFocusTimers();

  focusTile.classList.add("done");
  await invoke("complete_task", { id });

  widget.classList.remove("focus-mode");
  focusView.classList.remove("ready");
  focusView.classList.add("leaving");
  hideTimer = window.setTimeout(() => {
    focusView.classList.add("hidden");
    focusTile.classList.remove("done");
    clearGeometry();
    hideTimer = null;
  }, HERO_MS);

  await refreshActive();
}

// Pin the tile to `from`, commit that frame with transitions off, then release
// it to `to` with transitions back on — the standard FLIP two-step. Coordinates
// are relative to `origin` (the overlay's box), since that's the tile's
// containing block once it goes absolute.
function flyTile(from: DOMRect, to: DOMRect, origin: DOMRect, fromFont: string, toFont: string): void {
  focusTile.classList.add("animating");
  focusTile.style.transition = "none";
  focusText.style.transition = "none";
  applyGeometry(from, origin);
  focusText.style.fontSize = fromFont;
  void focusTile.offsetWidth; // reflow: commits the start frame

  focusTile.style.transition = "";
  focusText.style.transition = "";
  applyGeometry(to, origin);
  focusText.style.fontSize = toFont;
}

function applyGeometry(rect: DOMRect, origin: DOMRect): void {
  focusTile.style.left = `${rect.left - origin.left}px`;
  focusTile.style.top = `${rect.top - origin.top}px`;
  focusTile.style.width = `${rect.width}px`;
  focusTile.style.height = `${rect.height}px`;
}

// Hand the tile back to the overlay's flex centring.
function clearGeometry(): void {
  focusTile.classList.remove("animating");
  for (const prop of ["left", "top", "width", "height", "transition"]) {
    focusTile.style.removeProperty(prop);
  }
  focusText.style.removeProperty("font-size");
  focusText.style.removeProperty("transition");
  heroTimer = null;
}

function cancelFocusTimers(): void {
  if (heroTimer !== null) window.clearTimeout(heroTimer);
  if (hideTimer !== null) window.clearTimeout(hideTimer);
  heroTimer = null;
  hideTimer = null;
}

// If a task was still in progress when the widget last closed, drop straight
// back into focus on it — switching workspace if it lives in another one.
async function restoreFocus(): Promise<void> {
  const task = await invoke<Task | null>("find_in_progress");
  if (!task) return;
  if (task.workspace_id !== currentWorkspaceId) {
    currentWorkspaceId = task.workspace_id;
    localStorage.setItem(LAST_WORKSPACE_KEY, String(task.workspace_id));
    await refreshWorkspaces();
    await refreshActive();
  }
  enterFocus(task, null);
}

// --- the nudge ---
// Anti-distraction bob: while it's on, the focus tile jumps up and down the
// whole time you're focused, so it stays in the corner of your eye. Off, it
// sits still. The choice is remembered across restarts.

// Called whenever either half of the condition changes (the toggle, or entering
// / leaving focus).
function applyNudge(): void {
  focusTile.classList.toggle("nudging", nudgeEnabled && focusTaskId !== null);
}

function toggleNudge(): void {
  nudgeEnabled = !nudgeEnabled;
  localStorage.setItem(NUDGE_KEY, nudgeEnabled ? "1" : "0");
  applyNudgeButton();
  applyNudge();
}

function applyNudgeButton(): void {
  nudgeBtn.classList.toggle("on", nudgeEnabled);
  nudgeBtn.title = nudgeEnabled
    ? "Nudge on — the tile keeps bobbing while you're focused"
    : "Nudge off — the tile stays still";
}

// Reorder-by-drag: dragover moves the dragged <li> in the live DOM to preview
// the drop position; dragend (above) persists the final DOM order to the backend.
function attachTaskListDragging(): void {
  taskList.addEventListener("dragover", (e) => {
    const dragging = taskList.querySelector<HTMLLIElement>(".task.dragging");
    if (!dragging) return;
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = "move";
    const after = taskAfterDragPosition(e.clientY);
    if (after === null) taskList.appendChild(dragging);
    else taskList.insertBefore(dragging, after);
  });
  // Without a drop handler that prevents the default, the browser rejects the
  // drop (and can navigate/open the dragged text as a fallback action).
  taskList.addEventListener("drop", (e) => {
    e.preventDefault();
  });
}

function taskAfterDragPosition(y: number): HTMLLIElement | null {
  const candidates = [...taskList.querySelectorAll<HTMLLIElement>(".task:not(.dragging)")];
  let closest: { offset: number; element: HTMLLIElement | null } = {
    offset: Number.NEGATIVE_INFINITY,
    element: null,
  };
  for (const el of candidates) {
    const box = el.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    if (offset < 0 && offset > closest.offset) {
      closest = { offset, element: el };
    }
  }
  return closest.element;
}

async function persistTaskOrder(): Promise<void> {
  const order = [...taskList.querySelectorAll<HTMLLIElement>(".task")].map((li) => Number(li.dataset.id));
  await invoke("reorder_tasks", { order });
}

// Check off -> play the fade/slide-out animation, then persist and drop the row.
async function completeTask(li: HTMLLIElement, id: number): Promise<void> {
  li.classList.add("completing");
  await invoke("complete_task", { id });
  window.setTimeout(async () => {
    li.remove();
    await refreshActive();
  }, 320);
}

async function deleteTask(li: HTMLLIElement, id: number): Promise<void> {
  li.classList.add("completing");
  await invoke("delete_task", { id });
  window.setTimeout(async () => {
    li.remove();
    await refreshActive();
  }, 320);
}

async function refreshHistory(): Promise<void> {
  if (currentWorkspaceId === null) return;
  const tasks = await invoke<Task[]>("list_history", { workspaceId: currentWorkspaceId, limit: 100 });
  historyList.replaceChildren(...tasks.map(renderHistory));
  historyEmpty.classList.toggle("hidden", tasks.length > 0);
}

function renderHistory(task: Task): HTMLLIElement {
  const li = document.createElement("li");
  li.className = "task done";

  const label = document.createElement("span");
  label.className = "task-text";
  label.textContent = task.text;

  const when = document.createElement("span");
  when.className = "task-when";
  when.textContent = formatWhen(task.completed_at);

  li.append(label, when);
  return li;
}

function formatWhen(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function toggleHistory(): void {
  // History lives behind the focus overlay, so the first click just leaves focus.
  if (focusTaskId !== null) {
    void exitFocus();
    return;
  }
  const showHistory = historyView.classList.contains("hidden");
  historyView.classList.toggle("hidden", !showHistory);
  activeView.classList.toggle("hidden", showHistory);
  if (showHistory) refreshHistory();
}

async function togglePin(): Promise<void> {
  alwaysOnTop = !alwaysOnTop;
  await appWindow.setAlwaysOnTop(alwaysOnTop);
  pinBtn.classList.toggle("active", alwaysOnTop);
}

// --- workspaces ("Arbeitsbereiche") ---
// Separate todo lists, each with its own name and color. Tasks belong to
// exactly one workspace; side thoughts stay global across all of them.

async function refreshWorkspaces(): Promise<void> {
  workspaces = await invoke<Workspace[]>("list_workspaces");

  if (currentWorkspaceId === null || !workspaces.some((w) => w.id === currentWorkspaceId)) {
    const stored = Number(localStorage.getItem(LAST_WORKSPACE_KEY));
    const fallback = workspaces.find((w) => w.id === stored) ?? workspaces[0];
    currentWorkspaceId = fallback ? fallback.id : null;
  }

  workspaceList.replaceChildren(...workspaces.map(renderWorkspaceTab));
  applyWorkspaceTint();
}

// Tint the window chrome with the active workspace's color (see --ws-color in styles.css),
// and drive the side-thought urgency bar with its complement so the alarm always reads
// clearly against that tint (see --thought-r/g/b).
function applyWorkspaceTint(): void {
  const active = workspaces.find((w) => w.id === currentWorkspaceId);
  const color = active ? active.color : WORKSPACE_COLORS[0];
  document.documentElement.style.setProperty("--ws-color", color);

  const [r, g, b] = complementaryRgb(color);
  document.documentElement.style.setProperty("--thought-r", String(r));
  document.documentElement.style.setProperty("--thought-g", String(g));
  document.documentElement.style.setProperty("--thought-b", String(b));
}

// Hue-rotate 180° from the given hex color, but force high saturation and a
// mid lightness so the result is always a vivid, attention-grabbing color —
// even if the workspace color itself is pale or desaturated.
function complementaryRgb(hex: string): [number, number, number] {
  const r = parseInt(hex.slice(1, 3), 16) / 255;
  const g = parseInt(hex.slice(3, 5), 16) / 255;
  const b = parseInt(hex.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d !== 0) {
    switch (max) {
      case r:
        h = ((g - b) / d) % 6;
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      default:
        h = (r - g) / d + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  const complementHue = (h + 180) % 360;
  return hslToRgb(complementHue, 0.85, 0.58);
}

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let [r, g, b] = [0, 0, 0];
  if (h < 60) [r, g, b] = [c, x, 0];
  else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x];
  else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

function renderWorkspaceTab(ws: Workspace): HTMLLIElement {
  const li = document.createElement("li");
  li.className = "workspace-tab" + (ws.id === currentWorkspaceId ? " active" : "");
  li.dataset.id = String(ws.id);

  const dot = document.createElement("span");
  dot.className = "workspace-dot";
  dot.style.background = ws.color;

  const label = document.createElement("span");
  label.textContent = ws.name;

  li.append(dot, label);
  li.addEventListener("click", () => onWorkspaceTabClick(ws));
  return li;
}

// Clicking the already-active tab opens it for editing; clicking another tab
// switches to it (blocked while side thoughts are pending, same as closing).
async function onWorkspaceTabClick(ws: Workspace): Promise<void> {
  if (ws.id === currentWorkspaceId) {
    openWorkspaceForm(ws);
    return;
  }
  if (!(await canProceedPastThoughts())) {
    flashBlocked();
    return;
  }
  currentWorkspaceId = ws.id;
  localStorage.setItem(LAST_WORKSPACE_KEY, String(ws.id));
  closeWorkspaceForm();
  await Promise.all([refreshWorkspaces(), refreshActive()]);
  if (!historyView.classList.contains("hidden")) await refreshHistory();
}

function renderColorPicker(): void {
  workspaceColorPicker.replaceChildren(
    ...WORKSPACE_COLORS.map((color) => {
      const swatch = document.createElement("button");
      swatch.type = "button";
      swatch.className = "workspace-color-swatch" + (color === selectedColor ? " selected" : "");
      swatch.style.background = color;
      swatch.addEventListener("click", () => {
        selectedColor = color;
        renderColorPicker();
      });
      return swatch;
    }),
  );
}

function openWorkspaceForm(ws: Workspace | null): void {
  editingWorkspaceId = ws ? ws.id : null;
  workspaceNameInput.value = ws ? ws.name : "";
  selectedColor = ws ? ws.color : WORKSPACE_COLORS[workspaces.length % WORKSPACE_COLORS.length];
  workspaceDeleteBtn.classList.toggle("hidden", !ws || workspaces.length <= 1);
  renderColorPicker();
  workspaceForm.classList.remove("hidden");
  workspaceNameInput.focus();
}

function closeWorkspaceForm(): void {
  workspaceForm.classList.add("hidden");
  editingWorkspaceId = null;
}

async function submitWorkspaceForm(): Promise<void> {
  const name = workspaceNameInput.value.trim();
  if (!name) return;
  if (editingWorkspaceId !== null) {
    await invoke("update_workspace", { id: editingWorkspaceId, name, color: selectedColor });
  } else {
    const ws = await invoke<Workspace>("add_workspace", { name, color: selectedColor });
    currentWorkspaceId = ws.id;
    localStorage.setItem(LAST_WORKSPACE_KEY, String(ws.id));
  }
  closeWorkspaceForm();
  await refreshWorkspaces();
  await refreshActive();
}

async function deleteCurrentWorkspace(): Promise<void> {
  if (editingWorkspaceId === null) return;
  await invoke("delete_workspace", { id: editingWorkspaceId });
  currentWorkspaceId = null;
  closeWorkspaceForm();
  await refreshWorkspaces();
  await refreshActive();
}

// --- side thoughts ---

async function refreshThoughts(): Promise<void> {
  const thoughts = await invoke<SideThought[]>("list_side_thoughts");
  thoughtCount = thoughts.length;
  thoughtList.replaceChildren(...thoughts.map(renderThought));
  thoughtList.classList.toggle("hidden", thoughts.length === 0);
  updateThoughtBar();
}

function renderThought(t: SideThought): HTMLLIElement {
  const li = document.createElement("li");
  li.className = "thought";
  li.dataset.id = String(t.id);

  const label = document.createElement("span");
  label.className = "thought-text";
  label.textContent = t.text;

  const promote = document.createElement("button");
  promote.className = "thought-act";
  promote.title = "Turn into a task";
  promote.textContent = "↑";
  promote.addEventListener("click", () => promoteThought(t));

  const discard = document.createElement("button");
  discard.className = "thought-act discard";
  discard.title = "Throw it away";
  discard.textContent = "✕";
  discard.addEventListener("click", () => resolveThought(t.id));

  li.append(label, promote, discard);
  return li;
}

// Tidy a thought into a proper task: create the task, then mark the thought
// resolved (its row stays in the DB either way).
async function promoteThought(t: SideThought): Promise<void> {
  if (currentWorkspaceId === null) return;
  await invoke("add_task", { workspaceId: currentWorkspaceId, text: t.text });
  await invoke("resolve_side_thought", { id: t.id });
  await refreshActive();
  await refreshThoughts();
}

async function resolveThought(id: number): Promise<void> {
  await invoke("resolve_side_thought", { id });
  await refreshThoughts();
}

// Redden + pulse the bottom bar as pending thoughts pile up: a gentle nudge
// around 10, an unmissable flash by 20.
function updateThoughtBar(): void {
  const n = thoughtCount;
  const intensity = Math.min(n / 20, 1);
  footerBar.style.setProperty("--intensity", intensity.toFixed(3));
  thoughtCountEl.textContent = n > 0 ? `💭 ${n}` : "";

  if (n >= 10) {
    // Pulse speeds up from ~1.8s at 10 thoughts down to 0.5s at 20+.
    const dur = Math.max(0.5, 1.8 - (n - 10) * 0.13);
    footerBar.style.setProperty("--pulse-dur", `${dur}s`);
    footerBar.classList.add("pulse");
  } else {
    footerBar.classList.remove("pulse");
  }
}

// --- guard: refuse to close, or switch workspace, until side thoughts are
// cleared --- Deliberate: it forces you to move every stray thought into your
// real planner (or check it off) before it can leave view. Tasks themselves no
// longer block closing — they persist in the DB regardless of workspace.

// Ask the backend fresh every time — never a cached count — so an in-flight
// resolve can't wrongly block *or* allow a close/switch.
async function canProceedPastThoughts(): Promise<boolean> {
  const thoughts = await invoke<SideThought[]>("list_side_thoughts");
  return thoughts.length === 0;
}

// Shake + redden the footer and say why, when a close/switch is refused.
function flashBlocked(): void {
  footerBar.classList.remove("blocked");
  void footerBar.offsetWidth; // reflow so the animation restarts on rapid clicks
  footerBar.classList.add("blocked");
  thoughtCountEl.textContent = "Clear side thoughts first";
  window.setTimeout(() => {
    footerBar.classList.remove("blocked");
    updateThoughtBar();
  }, 1600);
}

window.addEventListener("DOMContentLoaded", () => {
  widget = document.querySelector(".widget")!;
  focusView = document.querySelector("#focus-view")!;
  focusTile = document.querySelector("#focus-tile")!;
  focusText = document.querySelector("#focus-text")!;
  focusDoneBtn = document.querySelector("#focus-done-btn")!;
  focusExitBtn = document.querySelector("#focus-exit-btn")!;
  nudgeBtn = document.querySelector("#nudge-btn")!;
  addForm = document.querySelector("#add-form")!;
  addInput = document.querySelector("#add-input")!;
  taskList = document.querySelector("#task-list")!;
  emptyState = document.querySelector("#empty-state")!;
  activeView = document.querySelector("#active-view")!;
  historyView = document.querySelector("#history-view")!;
  historyList = document.querySelector("#history-list")!;
  historyEmpty = document.querySelector("#history-empty")!;
  pinBtn = document.querySelector("#pin-btn")!;
  thoughtList = document.querySelector("#thought-list")!;
  thoughtForm = document.querySelector("#thought-form")!;
  thoughtInput = document.querySelector("#thought-input")!;
  thoughtBtn = document.querySelector("#thought-btn")!;
  footerBar = document.querySelector("#footer-bar")!;
  thoughtCountEl = document.querySelector("#thought-count")!;
  workspaceList = document.querySelector("#workspace-list")!;
  workspaceAddBtn = document.querySelector("#workspace-add-btn")!;
  workspaceForm = document.querySelector("#workspace-form")!;
  workspaceNameInput = document.querySelector("#workspace-name-input")!;
  workspaceColorPicker = document.querySelector("#workspace-color-picker")!;
  workspaceDeleteBtn = document.querySelector("#workspace-delete-btn")!;
  workspaceCancelBtn = document.querySelector("#workspace-cancel-btn")!;

  // Ctrl+Enter keeps the field focused for chaining entries; plain Enter blurs
  // it away once the task is added.
  addInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") addCtrlEnter = e.ctrlKey;
  });

  addForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = addInput.value.trim();
    const chain = addCtrlEnter;
    addCtrlEnter = false;
    if (!text || currentWorkspaceId === null) return;
    addInput.value = "";
    await invoke("add_task", { workspaceId: currentWorkspaceId, text });
    await refreshActive();
    if (chain) addInput.focus();
    else addInput.blur();
  });

  workspaceAddBtn.addEventListener("click", () => openWorkspaceForm(null));
  workspaceCancelBtn.addEventListener("click", closeWorkspaceForm);
  workspaceDeleteBtn.addEventListener("click", deleteCurrentWorkspace);
  workspaceForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    await submitWorkspaceForm();
  });

  // Side-thought capture: the button expands the field to the right; Enter saves
  // and collapses it again.
  thoughtBtn.addEventListener("click", () => {
    thoughtForm.classList.toggle("collapsed");
    if (!thoughtForm.classList.contains("collapsed")) thoughtInput.focus();
  });

  // Ctrl+Enter keeps the thought field open and focused for chaining entries;
  // plain Enter collapses it back to the icon once the thought is captured.
  thoughtInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") thoughtCtrlEnter = e.ctrlKey;
  });

  thoughtForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = thoughtInput.value.trim();
    const chain = thoughtCtrlEnter;
    thoughtCtrlEnter = false;
    thoughtInput.value = "";
    if (!text) {
      thoughtForm.classList.add("collapsed");
      return;
    }
    await invoke("add_side_thought", { text });
    await refreshThoughts();
    if (chain) {
      thoughtForm.classList.remove("collapsed");
      thoughtInput.focus();
    } else {
      thoughtForm.classList.add("collapsed");
    }
  });

  thoughtInput.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      thoughtInput.value = "";
      thoughtForm.classList.add("collapsed");
    }
  });

  thoughtInput.addEventListener("blur", () => {
    if (!thoughtInput.value.trim()) thoughtForm.classList.add("collapsed");
  });

  focusDoneBtn.addEventListener("click", completeFromFocus);
  focusExitBtn.addEventListener("click", exitFocus);
  nudgeBtn.addEventListener("click", toggleNudge);
  nudgeEnabled = localStorage.getItem(NUDGE_KEY) !== "0";
  applyNudgeButton();

  // Esc is the quick way out of focus mode.
  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && focusTaskId !== null) void exitFocus();
  });

  pinBtn.addEventListener("click", togglePin);
  document.querySelector("#history-btn")!.addEventListener("click", toggleHistory);
  document.querySelector("#min-btn")!.addEventListener("click", () => appWindow.minimize());
  document.querySelector("#close-btn")!.addEventListener("click", () => appWindow.close());

  // Single gatekeeper for every close path (our ✕, Alt+F4, OS close): stay open
  // until pending side thoughts are cleared, then destroy() to actually close.
  // Tasks no longer block closing — they persist in the DB across restarts.
  appWindow.onCloseRequested(async (event) => {
    event.preventDefault();
    if (await canProceedPastThoughts()) {
      await appWindow.destroy();
    } else {
      // Leave focus first — the footer, and its refusal flash, are behind the
      // focus overlay.
      await exitFocus();
      flashBlocked();
    }
  });

  attachTaskListDragging();
  refreshWorkspaces().then(refreshActive).then(restoreFocus);
  refreshThoughts();
  registerGlobalShortcuts();
});

// Ctrl+Alt+T / Ctrl+Alt+H, from anywhere: bring the widget forward and jump
// straight into the add-task / add-thought field.
async function registerGlobalShortcuts(): Promise<void> {
  try {
    await register("Ctrl+Alt+T", (event) => {
      if (event.state === "Pressed") focusAddTask();
    });
  } catch (err) {
    console.error("Couldn't register Ctrl+Alt+T:", err);
  }
  try {
    await register("Ctrl+Alt+H", (event) => {
      if (event.state === "Pressed") focusAddThought();
    });
  } catch (err) {
    console.error("Couldn't register Ctrl+Alt+H:", err);
  }
}

// Both fields sit behind the focus overlay, so jumping to either leaves focus.
async function focusAddTask(): Promise<void> {
  await appWindow.unminimize();
  await appWindow.setFocus();
  await exitFocus();
  addInput.focus();
}

async function focusAddThought(): Promise<void> {
  await appWindow.unminimize();
  await appWindow.setFocus();
  await exitFocus();
  thoughtForm.classList.remove("collapsed");
  thoughtInput.focus();
}
