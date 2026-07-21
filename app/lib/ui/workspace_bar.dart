// Workspace tabs and the edit form.
//
// Tasks belong to exactly one workspace; side thoughts stay global across all
// of them. Clicking the active tab opens it for editing, clicking another
// switches to it - the same interaction as the original.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

class WorkspaceBar extends StatelessWidget {
  const WorkspaceBar({
    super.key,
    required this.workspaces,
    required this.currentUuid,
    required this.onSelect,
    required this.onEdit,
    required this.onCreate,
  });

  final List<Workspace> workspaces;
  final String? currentUuid;
  final ValueChanged<Workspace> onSelect;
  final ValueChanged<Workspace> onEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final ws in workspaces)
                  _Tab(
                    workspace: ws,
                    active: ws.uuid == currentUuid,
                    onTap: () => ws.uuid == currentUuid
                        ? onEdit(ws)
                        : onSelect(ws),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: 'New workspace',
            child: InkWell(
              onTap: onCreate,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.add, size: 15, color: T.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.workspace, required this.active, required this.onTap});

  final Workspace workspace;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = T.parseHex(workspace.color);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                workspace.name,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? T.text : T.muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
        style: const TextStyle(fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Workspace name…',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
