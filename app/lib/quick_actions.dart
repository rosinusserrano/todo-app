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
// **The list is not fixed.** Both platforms take whatever `setShortcutItems`
// was last handed and remember it across launches, so the menu can name the
// task you are actually on - which is what the third entry does. Three things
// follow from that and none of them are obvious:
//
//   - It is rebuilt on a *change*, not on a timer and not per notify: the call
//     crosses a platform channel and the menu is only read while the app is in
//     the background, so re-registering an identical list is pure cost.
//   - It survives the app being killed. A stale entry naming a task that has
//     since been finished is therefore possible, and the handler has to cope
//     with the task being gone rather than assume the menu was truthful.
//   - iOS shows **four** items at most, static and dynamic together. With the
//     calendar that budget is spent exactly - three fixed entries and the one
//     that comes and goes - so a fifth needs one of these to go.
//
// Desktop has no such menu, so this is a no-op there.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

typedef QuickAction = Future<void> Function();

class AppQuickActions {
  AppQuickActions({
    required this.onAddTask,
    required this.onAddThought,
    required this.onNoteOnActive,
    required this.onOpenCalendar,
  });

  final QuickAction onAddTask;
  final QuickAction onAddThought;

  /// The task in focus was picked from the menu: add a line to its notes.
  final QuickAction onNoteOnActive;

  /// Straight to the calendar. Not a capture path like the other two, but the
  /// question a phone is most often unlocked to ask - "what is next today" -
  /// and three taps through the app to answer it is two too many.
  final QuickAction onOpenCalendar;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  static const _addTask = 'add_task';
  static const _addThought = 'add_thought';
  static const _noteOnActive = 'note_on_active';
  static const _calendar = 'open_calendar';

  /// How much of a task's title the entry can carry. Both platforms ellipsise
  /// on their own, but they do it at whatever the icon grid allows, and a title
  /// cut at "Draft the quarterly rep…" is more use than one cut at "Draft".
  static const _titleMax = 32;

  final _quick = const QuickActions();

  bool _installed = false;

  /// The title currently named in the menu, or null for "no third entry".
  /// Compared against rather than the task itself: a title is what the menu
  /// shows, so it is what decides whether the menu is out of date.
  String? _activeTitle;

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
          case _noteOnActive:
            await onNoteOnActive();
          case _calendar:
            await onOpenCalendar();
        }
      });
      _installed = true;
      await _publish();
    } catch (e) {
      // Same policy as a hotkey another app already owns: losing the shortcut
      // must not stop the app from starting.
      debugPrint('Could not install quick actions: $e');
    }
  }

  /// Name the task in focus in the menu, or pass null to take the entry away.
  ///
  /// Safe to call on every state change: it does nothing unless the title it
  /// would print has actually moved.
  Future<void> setActiveTask(String? title) async {
    final next = _shorten(title);
    if (next == _activeTitle) return;
    _activeTitle = next;
    if (!_installed) return;
    try {
      await _publish();
    } catch (e) {
      debugPrint('Could not update quick actions: $e');
    }
  }

  static String? _shorten(String? title) {
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length <= _titleMax) return trimmed;
    return '${trimmed.substring(0, _titleMax - 1).trimRight()}…';
  }

  Future<void> _publish() {
    final active = _activeTitle;
    return _quick.setShortcutItems([
      // No `icon`: that field names a native resource (an Android drawable, an
      // iOS asset-catalog image), and a name with nothing behind it fails the
      // whole call. Both platforms fall back to a generic glyph, which is what
      // most apps show anyway.
      const ShortcutItem(type: _addTask, localizedTitle: 'Add task'),
      const ShortcutItem(type: _addThought, localizedTitle: 'Park a thought'),
      const ShortcutItem(type: _calendar, localizedTitle: 'Calendar'),
      // Last, because it is the one that comes and goes: an entry that moves
      // the other three up and down the menu as tasks are started and finished is
      // one you cannot learn the position of.
      //
      // The title carries the task and the subtitle says what will happen to
      // it. iOS draws both; Android drops the subtitle, which is why the task
      // is in the title rather than the other way round - "Add a note" on its
      // own would be a menu entry with no object.
      if (active != null)
        ShortcutItem(
          type: _noteOnActive,
          localizedTitle: 'Note on $active',
          localizedSubtitle: 'Add a line to its notes',
        ),
    ]);
  }

  Future<void> clear() async {
    if (!supported) return;
    await _quick.clearShortcutItems();
  }
}
