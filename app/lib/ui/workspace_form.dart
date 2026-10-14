// Creating and editing a workspace: its name and colour, and deleting it.
//
// The form outlived the workspace bar it was drawn from (the dock replaced
// the bar); it is opened from the dock's workspace menu now.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// Create/edit sheet. Returns null on cancel, a [WorkspaceEdit] on save, and
/// [WorkspaceEdit.deleted] when the workspace should be removed.
class WorkspaceEdit {
  const WorkspaceEdit(this.name, this.color, {this.delete = false});

  final String name;
  final String color;
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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, WorkspaceEdit(name, T.toHex(_color)));
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
