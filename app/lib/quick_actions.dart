// Home-screen quick actions - the menu you get from long-pressing the app icon
// on iOS and Android.
//
// This is the mobile counterpart of the global shortcuts in shortcuts.dart, and
// it exists for exactly the same reason: capture speed. A thought has to land
// somewhere before it evaporates, and on a phone the fastest route to the add
// field is long-press, tap - two gestures, no app launch screen in between.
//
// Not to be confused with a WidgetKit home-screen *widget*, which is a separate
// app extension with its own Swift target and cannot host a text field at all.
// Both entries here land in the running app with the caret already in the right
// place, which is the part that matters.
//
// Desktop has no such menu, so this is a no-op there.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

typedef QuickAction = Future<void> Function();

class AppQuickActions {
  AppQuickActions({required this.onAddTask, required this.onAddThought});

  final QuickAction onAddTask;
  final QuickAction onAddThought;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static const _addTask = 'add_task';
  static const _addThought = 'add_thought';

  final _quick = const QuickActions();

  /// Registering also installs the handler. The handler fires for a cold start
  /// too - the shortcut that launched the app is delivered once this is set up
  /// - so the caller must be ready to act on it immediately.
  Future<void> install() async {
    if (!supported) return;

    try {
      _quick.initialize((type) async {
        switch (type) {
          case _addTask:
            await onAddTask();
          case _addThought:
            await onAddThought();
        }
      });

      // No `icon`: that field names a native resource (an Android drawable, an
      // iOS asset-catalog image), and a name with nothing behind it fails the
      // whole call. Both platforms fall back to a generic glyph, which is what
      // most apps show anyway.
      await _quick.setShortcutItems(const [
        ShortcutItem(type: _addTask, localizedTitle: 'Add task'),
        ShortcutItem(type: _addThought, localizedTitle: 'Park a thought'),
      ]);
    } catch (e) {
      // Same policy as a hotkey another app already owns: losing the shortcut
      // must not stop the app from starting.
      debugPrint('Could not install quick actions: $e');
    }
  }

  Future<void> clear() async {
    if (!supported) return;
    await _quick.clearShortcutItems();
  }
}
