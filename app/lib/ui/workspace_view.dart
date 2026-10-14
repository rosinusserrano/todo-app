// Which view owns the content area, and the order they come in.

/// The per-workspace views, plus the global thought pile, each of which can
/// own the content area. Null - no view - is the task list.
///
/// [thoughts] is here although the pile belongs to no workspace, because it
/// takes the same content area and the dock has to know it is on screen
/// rather than light up Tasks.
enum WorkspaceView { notes, parked, collections, history, thoughts }

/// The workspace's views in order, Tasks (null) first because it is the one
/// you go back to. The dock's second segment lists them in this order
/// (nearest the bar first) and a horizontal swipe on the list walks it - one
/// list, so the two cannot disagree about what is next to what.
const kViewOrder = <WorkspaceView?>[
  null,
  WorkspaceView.notes,
  WorkspaceView.collections,
  WorkspaceView.parked,
  WorkspaceView.history,
];
