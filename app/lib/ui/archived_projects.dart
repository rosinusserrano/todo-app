// Settings' archive: the projects put away, to read or bring back.
//
// Archiving a project is not finishing it - it is putting it away whole, open
// tasks and all - so the archive is somewhere to *consult*, not a second
// History. Two rungs inside the settings sheet (like the people page): the
// list of archived projects, newest first, and one project read-only, with
// Restore and Delete.
//
// Read-only on purpose. An archived project is never the current workspace,
// so nothing in the shell is showing it, and editing a project you have put
// away is restoring it first. Its contents are read straight from the store
// (`AppState.archivedContents`) for the same reason: none of the loaded lists
// are its.

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'list_rule.dart';
import 'project_row.dart' show confirmDeleteProject;

class ArchivedProjectsView extends StatefulWidget {
  const ArchivedProjectsView({super.key, required this.state});

  final AppState state;

  @override
  State<ArchivedProjectsView> createState() => ArchivedProjectsViewState();
}

class ArchivedProjectsViewState extends State<ArchivedProjectsView> {
  Workspace? _open;
  ArchivedProject? _contents;

  /// One rung down, for the sheet's back arrow: from a project to the list.
  /// False when already on the list, and the sheet leaves the archive.
  bool back() {
    if (_open == null) return false;
    setState(() => _open = null);
    return true;
  }

  AppState get s => widget.state;

  Future<void> _read(Workspace p) async {
    setState(() {
      _open = p;
      _contents = null;
    });
    final c = await s.archivedContents(p);
    if (mounted && _open?.uuid == p.uuid) setState(() => _contents = c);
  }

  Future<void> _restore(Workspace p) async {
    await s.restoreProject(p);
    if (mounted) setState(() => _open = null);
  }

  Future<void> _delete(Workspace p) async {
    if (!await confirmDeleteProject(context, p)) return;
    await s.deleteWorkspace(p.uuid);
    if (mounted) setState(() => _open = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final open = _open;
        return open == null ? _list() : _project(open);
      },
    );
  }

  Widget _list() {
    final archived = s.archivedProjects;
    if (archived.isEmpty) {
      return const Center(
        child: Text(
          'Nothing archived.',
          style: TextStyle(fontSize: T.fsLabel, color: T.muted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s3),
      children: [
        for (var i = 0; i < archived.length; i++) ...[
          _row(archived[i]),
          if (i < archived.length - 1) const ListRule(inset: 0),
        ],
      ],
    );
  }

  Widget _row(Workspace p) {
    final parent = s.workspaceByUuid(p.parentUuid);
    return InkWell(
      onTap: () => _read(p),
      borderRadius: BorderRadius.circular(T.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s2 + 2),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, size: 18, color: s.colorOf(p)),
            const SizedBox(width: T.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: T.fontDisplay,
                      fontSize: T.fsBody,
                      fontWeight: T.wMedium,
                      color: T.text,
                    ),
                  ),
                  Text(
                    [
                      if (parent != null) parent.name,
                      'archived ${_day(p.archivedAt!)}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: T.muted),
          ],
        ),
      ),
    );
  }

  Widget _project(Workspace p) {
    final c = _contents;
    final color = s.colorOf(p);
    return ListView(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s1, T.s3, T.s3),
      children: [
        Text(
          p.name,
          style: TextStyle(
            fontFamily: T.fontDisplay,
            fontSize: T.fsTitle,
            fontWeight: T.wMedium,
            color: color,
            height: 1.2,
          ),
        ),
        const SizedBox(height: T.s1),
        Text(
          'Archived ${_day(p.archivedAt!)}. Nothing in it reminds or repeats '
          'until it is restored.',
          style: const TextStyle(
            fontSize: T.fsMeta,
            color: T.muted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: T.s3),
        Row(
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: T.inkOn(color),
              ),
              onPressed: () => _restore(p),
              child: const Text('Restore'),
            ),
            const SizedBox(width: T.s2),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: T.danger),
              onPressed: () => _delete(p),
              child: const Text('Delete'),
            ),
          ],
        ),
        const SizedBox(height: T.s3),
        if (c == null)
          const Padding(
            padding: EdgeInsets.all(T.s4),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          if (c.notes > 0 || c.shelves > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s3),
              child: Text(
                [
                  if (c.notes > 0) _count(c.notes, 'note'),
                  if (c.shelves > 0) _count(c.shelves, 'shelf', 'shelves'),
                ].join(' · '),
                style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
              ),
            ),
          _section('Open', c.open, done: false),
          _section('Done', c.done, done: true),
          if (c.open.isEmpty && c.done.isEmpty)
            const Text(
              'No tasks.',
              style: TextStyle(fontSize: T.fsLabel, color: T.muted),
            ),
        ],
      ],
    );
  }

  Widget _section(String title, List<Task> tasks, {required bool done}) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title ${tasks.length}',
            style: const TextStyle(
              fontFamily: T.fontDisplay,
              fontSize: T.fsLabel,
              fontWeight: T.wMedium,
              color: T.muted,
            ),
          ),
          const SizedBox(height: T.s1),
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      done
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 15,
                      color: T.muted,
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  Expanded(
                    child: Text(
                      t.text,
                      style: TextStyle(
                        fontSize: T.fsBody,
                        color: done ? T.muted : T.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _count(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : many ?? '${one}s'}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _day(String stamp) {
    final d = DateTime.tryParse(stamp)?.toLocal();
    return d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';
  }
}
