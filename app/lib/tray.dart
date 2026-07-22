// System tray icon.
//
// The widget is a always-on-top scrap of screen, so the two things it needs
// from a tray are the ones a window alone cannot give: getting it back once it
// has been hidden, and hiding it without losing it. Minimize puts it in the
// taskbar; hiding puts it here.
//
// Quit deliberately routes back through the same close guard as the ✕ and
// Alt+F4 rather than calling destroy() itself. The guard exists to stop the
// app being abandoned with side thoughts still pending, and a tray menu that
// walked around it would be the one exit that defeats the entire point.
//
// Desktop only - a phone has no tray.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

class AppTray {
  AppTray({
    required this.onShow,
    required this.onHide,
    required this.onAddTask,
    required this.onQuit,
  });

  final Future<void> Function() onShow;
  final Future<void> Function() onHide;
  final Future<void> Function() onAddTask;

  /// Runs the close guard. Nothing here assumes the app actually exits.
  final Future<void> Function() onQuit;

  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _installed = false;

  /// Failure to install a tray icon is not fatal - the shell may simply not
  /// have a notification area. Same reasoning as a hotkey that is already
  /// owned: report it, do not stop the app from starting.
  Future<bool> install() async {
    if (!supported || _installed) return _installed;

    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
      );
      await trayManager.setToolTip('Todo Widget');
      await trayManager.setContextMenu(_menu());
      _installed = true;
      return true;
    } catch (e) {
      debugPrint('Could not install the tray icon: $e');
      return false;
    }
  }

  Menu _menu() => Menu(
        items: [
          MenuItem(key: _kShow, label: 'Show'),
          MenuItem(key: _kHide, label: 'Hide'),
          MenuItem.separator(),
          MenuItem(key: _kAddTask, label: 'Add task'),
          MenuItem.separator(),
          MenuItem(key: _kQuit, label: 'Quit'),
        ],
      );

  static const _kShow = 'show';
  static const _kHide = 'hide';
  static const _kAddTask = 'add-task';
  static const _kQuit = 'quit';

  Future<void> handleMenuItem(MenuItem item) async {
    switch (item.key) {
      case _kShow:
        await onShow();
      case _kHide:
        await onHide();
      case _kAddTask:
        await onAddTask();
      case _kQuit:
        await onQuit();
    }
  }

  Future<void> dispose() async {
    if (!supported || !_installed) return;
    await trayManager.destroy();
    _installed = false;
  }
}
