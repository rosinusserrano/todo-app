// Creating and editing a workspace: its name and colour, its shortcuts, its
// automatic overdue, and deleting it. Shortcuts are only removed here; one is added on the add card,
// from the `#name` it stands for (task_capture.dart).
//
// The form outlived the workspace bar it was drawn from (the dock replaced
// the bar); it is opened from the dock's workspace menu now.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// Create/edit sheet. Returns null on cancel, a [WorkspaceEdit] on save, and
/// [WorkspaceEdit.deleted] when the workspace should be removed.
class WorkspaceEdit {
  const WorkspaceEdit(
    this.name,
    this.color, {
    this.shortcuts = const [],
    this.staleDays,
    this.delete = false,
  });

  final String name;
  final String color;
  final List<String> shortcuts;

  /// Automatic overdue in days; null is off.
  final int? staleDays;
  final bool delete;

  static const deleted = WorkspaceEdit('', '', delete: true);
}

Future<WorkspaceEdit?> showWorkspaceForm(
  BuildContext context, {
  Workspace? existing,
  required int workspaceCount,
}) {
  return showDialog<WorkspaceEdit>(
    context: context,
    builder: (context) => _WorkspaceDialog(
      existing: existing,
      canDelete: existing != null && workspaceCount > 1,
      initialColor: existing != null
          ? T.parseHex(existing.color)
          : T.workspaceColors[workspaceCount % T.workspaceColors.length],
    ),
  );
}

class _WorkspaceDialog extends StatefulWidget {
  const _WorkspaceDialog({
    required this.existing,
    required this.canDelete,
    required this.initialColor,
  });

  final Workspace? existing;
  final bool canDelete;
  final Color initialColor;

  @override
  State<_WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<_WorkspaceDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late Color _color = widget.initialColor;
  late final _shortcuts = [...?widget.existing?.shortcuts];
  late int? _staleDays = widget.existing?.staleDays;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      WorkspaceEdit(
        name,
        T.toHex(_color),
        shortcuts: _shortcuts,
        staleDays: _staleDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        widget.existing == null ? 'New workspace' : 'Edit workspace',
        style: const TextStyle(fontSize: T.fsMenu),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(fontSize: T.fsBody),
            decoration: const InputDecoration(
              hintText: 'Workspace name…',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: T.s4),
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            children: [
              for (final c in T.workspaceColors)
                InkWell(
                  onTap: () => setState(() => _color = c),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == _color ? T.text : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: T.s4),
          const Text(
            'Overdue when left on the list for',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted),
          ),
          const SizedBox(height: T.s2),
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            children: [
              for (final d in [
                null,
                ...kStaleChoices,
                if (_staleDays != null && !kStaleChoices.contains(_staleDays))
                  _staleDays,
              ])
                ChoiceChip(
                  label: Text(
                    describeStaleDays(d),
                    style: const TextStyle(fontSize: T.fsLabel),
                  ),
                  selected: _staleDays == d,
                  onSelected: (_) => setState(() => _staleDays = d),
                ),
            ],
          ),
          if (_shortcuts.isNotEmpty) ...[
            const SizedBox(height: T.s4),
            const Text(
              'Shortcuts in a task title',
              style: TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
            const SizedBox(height: T.s2),
            Wrap(
              spacing: T.s2,
              runSpacing: T.s2,
              children: [
                for (final sc in _shortcuts)
                  InputChip(
                    label: Text(
                      '#$sc',
                      style: const TextStyle(fontSize: T.fsLabel),
                    ),
                    deleteButtonTooltipMessage: 'Remove #$sc',
                    onDeleted: () => setState(() => _shortcuts.remove(sc)),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: () => Navigator.pop(context, WorkspaceEdit.deleted),
            child: const Text('Delete', style: TextStyle(color: T.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The automatic overdue the form offers, in days.
const kStaleChoices = [3, 7, 14, 30, 90];

/// "Off", "3 days", "1 week", "1 month"...
String describeStaleDays(int? days) => switch (days) {
  null => 'Off',
  1 => '1 day',
  7 => '1 week',
  30 => '1 month',
  90 => '3 months',
  final d when d % 7 == 0 => '${d ~/ 7} weeks',
  final d => '$d days',
};
