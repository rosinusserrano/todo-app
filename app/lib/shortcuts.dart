// System-wide shortcuts.
//
//   Ctrl+Alt+T  jump straight into the add-task field
//   Ctrl+Alt+H  jump straight into the side-thought field
//
// The point of both is capture speed: the thought has to land somewhere before
// it evaporates, from whatever you were doing. So each one raises the window
// and puts the caret in the right field in a single keystroke.
//
// Desktop only - iOS and Android have no concept of a system-wide hotkey, and
// registering one is not merely unsupported there but meaningless.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

typedef ShortcutAction = Future<void> Function();

class GlobalShortcuts {
  GlobalShortcuts({required this.onAddTask, required this.onAddThought});

  final ShortcutAction onAddTask;
  final ShortcutAction onAddThought;

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _registered = false;

  /// Registration fails when another application already owns the combination.
  /// That is a normal thing to happen on someone else's machine, so it is
  /// reported rather than thrown - losing a shortcut must not stop the app
  /// from starting.
  Future<List<String>> register() async {
    if (!supported || _registered) return const [];

    final failures = <String>[];

    // Clears anything left over from a previous run or a hot restart, which
    // would otherwise make re-registration fail.
    await hotKeyManager.unregisterAll();

    Future<void> add(
      String label,
      PhysicalKeyboardKey key,
      ShortcutAction action,
    ) async {
      try {
        await hotKeyManager.register(
          HotKey(
            key: key,
            modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
            scope: HotKeyScope.system,
          ),
          keyDownHandler: (_) => action(),
        );
      } catch (e) {
        failures.add(label);
        debugPrint('Could not register $label: $e');
      }
    }

    await add('Ctrl+Alt+T', PhysicalKeyboardKey.keyT, onAddTask);
    await add('Ctrl+Alt+H', PhysicalKeyboardKey.keyH, onAddThought);

    _registered = true;
    return failures;
  }

  Future<void> dispose() async {
    if (!supported || !_registered) return;
    await hotKeyManager.unregisterAll();
    _registered = false;
  }
}
