// Voice notes: where a recording's bytes come from, and the button that
// plays one.
//
// A row names its recording by digest (`SideThought.audio`, `Task.audio`) and
// the bytes travel on their own. The device that recorded it keeps them in
// its `blobs` table until a sync has put them on the server
// (`SyncService._uploadBlobs`); every other device asks the server the first
// time the note is played and keeps a copy, trimmed oldest-used first past
// [VoiceNotes.cacheBytes]. A note whose bytes are nowhere yet - recorded
// offline on a phone that has not synced since - says so rather than failing.
//
// One note plays at a time, app-wide: [VoiceNotes] is the one player and
// [VoiceNotesScope] hands it down, so starting a second stops the first.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'sync/local_store.dart';
import 'sync/models.dart' show VoiceNote;
import 'theme.dart';
import 'voice_clip.dart';
import 'voice_player.dart';

typedef Blob = ({String type, Uint8List data});

class VoiceNotes extends ChangeNotifier {
  VoiceNotes({required this.store, required this.fetch});

  final LocalStore store;

  /// The server's copy - `SyncService.fetchBlob`. Null when it has none.
  final Future<Blob?> Function(String sha256) fetch;

  /// How much fetched audio a device keeps: about seven hours of speech.
  static const cacheBytes = 100 * 1024 * 1024;

  final _player = VoicePlayer();

  /// What is playing, what is being fetched to play, and which notes have no
  /// bytes anywhere this device can reach. Keys are digests; a draft in the
  /// thought pane plays under [draftKey].
  String? playing;
  String? loading;
  final Set<String> missing = {};

  static const draftKey = 'draft';

  /// The bytes, from this device or else from the server.
  Future<Blob?> bytes(String sha256) async {
    final local = await store.blob(sha256);
    if (local != null) return local;
    final remote = await fetch(sha256);
    if (remote == null) return null;
    await store.putBlob(sha256, remote.type, remote.data, uploaded: true);
    unawaited(store.trimBlobs(cacheBytes));
    return remote;
  }

  /// Play [note], or stop it if it is the one playing. Call it from the tap
  /// itself: the browser player is primed before anything is awaited.
  Future<void> toggle(VoiceNote note) => _toggle(note.sha256, () async {
    try {
      return await bytes(note.sha256);
    } catch (_) {
      return null;
    }
  });

  /// The thought pane's recording, before it is saved.
  Future<void> toggleClip(VoiceClip clip) => _toggle(
    draftKey,
    () async => (type: clip.type, data: clip.bytes),
  );

  Future<void> _toggle(String key, Future<Blob?> Function() load) async {
    if (playing == key || loading == key) {
      await stop();
      return;
    }
    VoicePlayer.prime();
    await _player.stop();
    playing = null;
    loading = key;
    missing.remove(key);
    notifyListeners();
    final blob = await load();
    // Stopped, or another note started, while this one was on its way.
    if (loading != key) return;
    loading = null;
    if (blob == null) {
      missing.add(key);
      notifyListeners();
      return;
    }
    playing = key;
    notifyListeners();
    await _player.play(blob.data, blob.type, key, (error) {
      if (playing != key) return;
      playing = null;
      if (error != null) debugPrint('voice note did not play: $error');
      notifyListeners();
    });
  }

  Future<void> stop() async {
    final was = playing != null || loading != null;
    playing = null;
    loading = null;
    await _player.stop();
    if (was) notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

class VoiceNotesScope extends InheritedNotifier<VoiceNotes> {
  const VoiceNotesScope({
    super.key,
    required VoiceNotes notes,
    required super.child,
  }) : super(notifier: notes);

  static VoiceNotes? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceNotesScope>()?.notifier;
}

/// ▶ 0:42 - a pill that plays a voice note. Without a [VoiceNotesScope]
/// above it (a test, mostly) it is the label alone.
class VoiceNoteButton extends StatelessWidget {
  const VoiceNoteButton({
    super.key,
    this.note,
    this.clip,
    required this.accent,
  }) : assert((note == null) != (clip == null));

  final VoiceNote? note;

  /// A recording not saved yet - the thought pane's draft.
  final VoiceClip? clip;

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final notes = VoiceNotesScope.maybeOf(context);
    final key = note?.sha256 ?? VoiceNotes.draftKey;
    final playing = notes?.playing == key;
    final loading = notes?.loading == key;
    final missing = notes?.missing.contains(key) ?? false;
    final length = note?.length ?? VoiceNote('', clip!.ms).length;

    final label = missing
        ? 'Not on the server yet'
        : length.isEmpty
        ? 'Voice note'
        : length;
    final ink = missing ? T.muted : accent;

    return Semantics(
      button: notes != null,
      label: playing ? 'Stop the voice note' : 'Play the voice note',
      child: Material(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.radius),
          onTap: notes == null
              ? null
              : () {
                  if (clip != null) {
                    notes.toggleClip(clip!);
                  } else {
                    notes.toggle(note!);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ink,
                          ),
                        )
                      : Icon(
                          missing
                              ? Icons.cloud_off_rounded
                              : playing
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: ink,
                        ),
                ),
                const SizedBox(width: T.s1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: T.fsLabel,
                    color: ink,
                    fontWeight: T.wMedium,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
