// The bytes behind an attachment.
//
// Files live next to todo.db, in an `attachments/` directory, named by the
// SHA-256 of their contents rather than by the name the user gave them. Three
// things fall out of that, and all three are the reason for it:
//
//   - Attaching the same document twice costs one copy, not two.
//   - A filename can be anything a user types, including things a filesystem
//     will not accept and things that escape the directory. A hex digest
//     cannot.
//   - The digest is already the address a blob-sync endpoint would fetch by, so
//     adding one later needs no migration of what is on disk.
//
// What is deliberately *not* here is any sync of the bytes. The row syncs, the
// file does not, so a second device can hold an attachment whose contents it
// has never seen. [hasLocal] is how the UI tells, and it says so plainly rather
// than pretending the attachment is broken.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class AttachmentStore {
  AttachmentStore._(this._dir);

  final Directory _dir;

  Directory get directory => _dir;

  /// [root] is only for tests; production keeps the blobs beside the database.
  static Future<AttachmentStore> open({String? root}) async {
    final base = root ?? (await getApplicationSupportDirectory()).path;
    final dir = Directory(p.join(base, 'attachments'));
    await dir.create(recursive: true);
    return AttachmentStore._(dir);
  }

  File fileFor(String sha256) => File(p.join(_dir.path, sha256));

  Future<bool> hasLocal(Attachment a) => fileFor(a.sha256).exists();

  /// Copies [source] in and returns the row to save, owned by a task.
  Future<Attachment> add(File source, String taskUuid) =>
      _copyIn(source, taskUuid: taskUuid);

  /// The same, owned by a calendar event. One copy of the bytes serves both:
  /// the file is addressed by its contents, so a document attached to a task
  /// and to an event is stored once.
  Future<Attachment> addForEvent(File source, String eventUuid) =>
      _copyIn(source, eventUuid: eventUuid);

  /// Copies [source] in and returns the row to save.
  ///
  /// Hashing streams rather than reading the file whole: attachments are
  /// documents, and a big one read into memory on a phone is how this becomes
  /// the feature that makes the app die on a 200 MB video.
  Future<Attachment> _copyIn(
    File source, {
    String taskUuid = '',
    String? eventUuid,
  }) async {
    final digest = await sha256.bind(source.openRead()).first;
    final hash = digest.toString();

    // Already have these exact bytes - from another task, or from the same file
    // attached twice. Copying again would only cost the disk.
    final target = fileFor(hash);
    if (!await target.exists()) {
      // Via a temporary name, so an interrupted copy cannot leave a truncated
      // file sitting at the address of the real one - where every later lookup
      // would find it and believe it.
      final tmp = File('${target.path}.part');
      await source.copy(tmp.path);
      await tmp.rename(target.path);
    }

    return Attachment(
      uuid: newId(),
      taskUuid: taskUuid,
      eventUuid: eventUuid,
      filename: p.basename(source.path),
      size: await source.length(),
      sha256: hash,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );
  }

  /// Drops the bytes for [sha256]. The caller is responsible for checking that
  /// nothing else references them - see [LocalStore.isBlobReferenced].
  Future<void> removeBlob(String sha256) async {
    final f = fileFor(sha256);
    if (await f.exists()) await f.delete();
  }

  /// Deletes files no live row points at any more.
  ///
  /// Tombstones make this necessary: a row deleted on another device arrives as
  /// an update, not as a call into this class, so its bytes would otherwise sit
  /// here forever. Cheap enough to run at startup - the directory holds one
  /// entry per distinct document.
  Future<int> sweep(Set<String> referenced) async {
    var removed = 0;
    await for (final entry in _dir.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      // Leave partial copies alone: one may belong to an add still in flight.
      if (name.endsWith('.part')) continue;
      if (referenced.contains(name)) continue;
      await entry.delete();
      removed++;
    }
    return removed;
  }

  /// "412 KB". Sizes are shown because "not on this device" is more useful next
  /// to a number that says how much is missing.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value < 10 ? value.toStringAsFixed(1) : value.round()} '
        '${units[unit]}';
  }
}
