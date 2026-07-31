// Attachments on a task.
//
// The honest part of this screen is the "not on this device" state. Attachment
// rows sync but their bytes do not, so a document attached on the desktop shows
// up on the phone as a real, named, sized entry that simply cannot be opened
// yet. Hiding those would be worse than showing them: you would be told the
// file does not exist when what is true is that it is somewhere else.
//
// So a missing blob is drawn as a dimmed row with a plain label, and it stays
// removable - deciding you no longer need a document is not something you
// should have to be at the right computer to do.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../sync/attachment_store.dart';
import '../sync/models.dart';
import '../theme.dart';

/// Opens the attachment list for one task. Returns once dismissed; the caller
/// reloads from the database rather than being handed a result, since anything
/// added or removed here has already been written.
Future<void> showAttachments(
  BuildContext context, {
  required Task task,
  required Color accent,
  required AttachmentStore blobs,
  required Future<List<Attachment>> Function() load,
  required Future<void> Function(File) onAdd,
  required Future<void> Function(Attachment) onRemove,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _AttachmentDialog(
      task: task,
      accent: accent,
      blobs: blobs,
      load: load,
      onAdd: onAdd,
      onRemove: onRemove,
    ),
  );
}

class _AttachmentDialog extends StatefulWidget {
  const _AttachmentDialog({
    required this.task,
    required this.accent,
    required this.blobs,
    required this.load,
    required this.onAdd,
    required this.onRemove,
  });

  final Task task;
  final Color accent;
  final AttachmentStore blobs;
  final Future<List<Attachment>> Function() load;
  final Future<void> Function(File) onAdd;
  final Future<void> Function(Attachment) onRemove;

  @override
  State<_AttachmentDialog> createState() => _AttachmentDialogState();
}

class _AttachmentDialogState extends State<_AttachmentDialog> {
  List<Attachment>? _items;

  /// Which attachments have their bytes here. Resolved once per load rather
  /// than per build - it is a filesystem stat, and build runs on every frame.
  Map<String, bool> _local = {};

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.load();
    final local = <String, bool>{};
    for (final a in items) {
      local[a.uuid] = await widget.blobs.hasLocal(a);
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _local = local;
    });
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // lockParentWindow: the widget is always-on-top on Windows, so without it
      // the picker can open *behind* the thing that asked for it.
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Attach a document',
        lockParentWindow: true,
      );
      final path = result?.files.singleOrNull?.path;
      if (path != null) await widget.onAdd(File(path));
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not attach that file.');
      debugPrint('Attach failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Attachment a) async {
    final result = await OpenFilex.open(widget.blobs.fileFor(a.sha256).path);
    if (result.type == ResultType.done || !mounted) return;
    // Most often "no application registered for this type", which is worth
    // saying rather than looking like a dead click.
    setState(() => _error = 'Nothing on this device opens ${a.kind} files.');
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        widget.task.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Nothing attached yet.',
                  style: TextStyle(fontSize: 12.5, color: T.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in items)
                      _Row(
                        attachment: a,
                        accent: widget.accent,
                        here: _local[a.uuid] ?? false,
                        onOpen: () => _open(a),
                        onRemove: () async {
                          await widget.onRemove(a);
                          await _reload();
                        },
                      ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 11.5, color: T.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.attach_file_rounded, size: 15),
          label: const Text('Attach'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.attachment,
    required this.accent,
    required this.here,
    required this.onOpen,
    required this.onRemove,
  });

  final Attachment attachment;
  final Color accent;

  /// Whether the bytes are on this device. False is a normal state, not an
  /// error - see the file header.
  final bool here;

  final VoidCallback onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;

    return Opacity(
      opacity: here ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              here ? Icons.description_outlined : Icons.cloud_off_rounded,
              size: 15,
              color: here ? accent : T.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: T.text),
                  ),
                  Text(
                    here
                        ? AttachmentStore.formatSize(a.size)
                        : '${AttachmentStore.formatSize(a.size)} · '
                            'not on this device',
                    style: const TextStyle(fontSize: 10.5, color: T.muted),
                  ),
                ],
              ),
            ),
            if (here)
              Tooltip(
                message: 'Open',
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.open_in_new_rounded,
                        size: 14, color: T.muted),
                  ),
                ),
              ),
            // Removable either way: deciding you no longer need a document
            // should not require being at the machine that holds it.
            Tooltip(
              message: 'Remove',
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 14, color: T.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
