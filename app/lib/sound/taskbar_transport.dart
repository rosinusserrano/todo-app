// The Windows taskbar thumbnail toolbar: pause/resume the concentration sound
// without bringing the widget to the front.
//
// This is the row of buttons under the taskbar thumbnail you get on hover - the
// same affordance Spotify and the built-in media apps use. It is Windows-only
// and entirely additive: every other platform gets a no-op, and nothing else in
// the app knows this exists.
//
// Three things about the underlying `ITaskbarList3` shape the code:
//
//   - **The button count is fixed for the window's lifetime.** The first
//     `ThumbBarAddButtons` decides it and no later call can change it. The
//     plugin papers over this by always registering seven and hiding the
//     unused ones, so re-sending a *different* number of buttons is safe - but
//     it means the toolbar is best thought of as "one button whose icon
//     changes", not "a list we rebuild".
//   - **It fails while the window is hidden.** The plugin bails out on
//     `IsWindowVisible`, and this app spends much of its life minimised to the
//     tray. So the desired state is cached and re-applied on restore, rather
//     than assumed to have stuck.
//   - **Icons are read from disk as `.ico`,** by path, out of
//     `data/flutter_assets` beside the exe - hence the bundled assets rather
//     than anything drawn in Flutter.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'sound_service.dart';

class TaskbarTransport {
  TaskbarTransport(this._sound);

  final SoundService _sound;

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// What the toolbar should currently show, whether or not Windows accepted
  /// it. Re-applied on restore, since a call made while hidden is dropped.
  bool? _wantedPaused;
  bool _applied = false;

  void start() {
    if (!supported) return;
    _sound.addListener(_sync);
    _sync();
  }

  void dispose() {
    if (!supported) return;
    _sound.removeListener(_sync);
  }

  /// Call when the window comes back from the tray or from minimised. A
  /// toolbar set while hidden never took, so the cached state has to be
  /// re-sent - otherwise the buttons silently stay as they were when the
  /// window was last visible.
  void refresh() {
    if (!supported) return;
    _applied = false;
    _sync();
  }

  Future<void> _sync() async {
    if (!supported) return;

    final paused = _sound.isPlaying ? _sound.isPaused : null;
    if (paused == _wantedPaused && _applied) return;
    _wantedPaused = paused;

    try {
      if (paused == null) {
        // Nothing loaded: take the toolbar away entirely rather than leave a
        // dead button. A thumbnail with no controls reads as "not a player
        // right now", which is exactly the state.
        await WindowsTaskbar.resetThumbnailToolbar();
      } else {
        await WindowsTaskbar.setThumbnailToolbar([
          ThumbnailToolbarButton(
            ThumbnailToolbarAssetIcon(
              paused ? 'assets/sound_play.ico' : 'assets/sound_pause.ico',
            ),
            paused ? 'Resume sound' : 'Pause sound',
            _sound.togglePause,
          ),
        ]);
      }
      _applied = true;
    } catch (e) {
      // A failure here costs the user nothing they cannot do in the window, so
      // it must never take the app down with it.
      debugPrint('Taskbar transport update failed: $e');
      _applied = false;
    }
  }
}
