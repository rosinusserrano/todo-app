// Creating and editing a standalone calendar - "Workout", "Gigs", anything
// that is a strand of life rather than a workspace of tasks.
//
// Workspace calendars are deliberately not editable here. Their name and colour
// come from the workspace, so a second place to set them would be a second
// source of truth that quietly disagrees with the first.
//
// The notification rule lives on the calendar because that is the level it
// actually varies at: a workout wants ten minutes' warning, work wants an hour,
// and nobody wants to answer that question again for every entry. An event can
// still override it, including down to silence.

import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';

class CalendarEdit {
  const CalendarEdit({
    required this.name,
    required this.color,
    required this.notifyMinutes,
    this.delete = false,
  });

  const CalendarEdit.delete()
      : name = '',
        color = '',
        notifyMinutes = null,
        delete = true;

  final String name;
  final String color;

  /// Null means this calendar never notifies on its own.
  final int? notifyMinutes;

  final bool delete;
}

Future<CalendarEdit?> showCalendarForm(
  BuildContext context, {
  Calendar? existing,
}) {
  return showDialog<CalendarEdit>(
    context: context,
    builder: (context) => _CalendarDialog(existing: existing),
  );
}

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({required this.existing});

  final Calendar? existing;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _color = widget.existing?.color ?? T.toHex(T.workspaceColors[1]);
  late int? _notify = widget.existing?.notifyMinutes;

  static const _notifyOptions = <int?, String>{
    null: 'Never',
    0: 'At start',
    10: '10 min before',
    30: '30 min before',
    60: '1 hour before',
    1440: '1 day before',
  };

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
      CalendarEdit(name: name, color: _color, notifyMinutes: _notify),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        editing ? 'Edit calendar' : 'New calendar',
        style: const TextStyle(fontSize: 15),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 24,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Workout, Gigs…',
                counterText: '',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            const Text('Colour',
                style: TextStyle(fontSize: 11.5, color: T.muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in T.workspaceColors)
                  () {
                    final hex = T.toHex(c);
                    final selected = hex.toLowerCase() == _color.toLowerCase();
                    return InkWell(
                      onTap: () => setState(() => _color = hex),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? T.text : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }(),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Notify by default',
                style: TextStyle(fontSize: 11.5, color: T.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _notifyOptions.entries)
                  ChoiceChip(
                    label:
                        Text(e.value, style: const TextStyle(fontSize: 11.5)),
                    selected: _notify == e.key,
                    onSelected: (_) => setState(() => _notify = e.key),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const CalendarEdit.delete()),
            child: const Text('Delete',
                style: TextStyle(color: T.danger, fontSize: 12.5)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}
