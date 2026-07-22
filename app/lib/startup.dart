// "Start with Windows".
//
// The registry (HKCU\...\Run) is the single source of truth, not a row in our
// own settings table. Two reasons: the user can turn this off from Windows
// itself - Task Manager's Startup tab - and a cached copy would then be a lie;
// and the setting is per-machine, so syncing it to a phone or a second PC would
// be meaningless at best.
//
// Desktop only, and in practice Windows: setup() must run before any call, so
// every method here no-ops rather than throwing when it has not.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

class StartupSetting {
  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _ready = false;

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      final info = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: info.appName,
        appPath: Platform.resolvedExecutable,
        packageName: info.packageName,
      );
      _ready = true;
    } catch (e) {
      debugPrint('Could not prepare launch-at-startup: $e');
    }
  }

  Future<bool> isEnabled() async {
    if (!_ready) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('Could not read launch-at-startup: $e');
      return false;
    }
  }

  /// Returns the state actually in effect afterwards, which is not necessarily
  /// what was asked for - writing to the Run key can be refused by policy on a
  /// managed machine. The caller shows what is true, not what was requested.
  Future<bool> setEnabled(bool on) async {
    if (!_ready) return false;
    try {
      if (on) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (e) {
      debugPrint('Could not change launch-at-startup: $e');
    }
    return isEnabled();
  }
}
