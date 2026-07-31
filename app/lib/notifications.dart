// OS notifications for reminders, on mobile only.
//
// [ReminderService] is the alert on desktop: it surfaces the always-on-top
// window, which is the strongest thing this widget can do and needs no
// notification permission. That does not carry to a phone. iOS and Android
// suspend an app's timers the moment it goes to the background and never let it
// raise itself to the foreground, so on mobile a reminder that is not handed to
// the OS ahead of time simply does not arrive until the app is next opened.
//
// So this schedules with the OS, and the poll keeps running alongside it: the
// poll is what makes the row itself read as due once the app *is* open, and it
// still catches anything that came due while the app was closed.
//
// Reconcile, don't hook the writes. Every scheduled notification is derived
// from one query over the armed reminders, and the whole set is rewritten on
// any change. A per-write hook would miss the case that matters most - a
// reminder set on the desktop and merged in by sync, which no local write path
// ever sees.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'sync/models.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Desktop deliberately gets nothing - see the file header.
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  bool _ready = false;

  /// Called when the user taps a reminder. Wired to the same path the tray and
  /// the global shortcuts use, so a tapped reminder lands on its task.
  void Function(String taskUuid)? onTapped;

  static const _channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Tasks you asked to be reminded about.',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (!supported || _ready) return;

    // zonedSchedule needs a real location, not just an offset: an offset fixed
    // at scheduling time would fire an hour out across a DST boundary.
    tzdata.initializeTimeZones();
    final local = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(local.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onTapped?.call(id);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_channel);
      // Android 13+. Declining is not an error: the in-app poll still shows the
      // row as due, so the app degrades to exactly its desktop behaviour.
      await android.requestNotificationsPermission();
    }

    _ready = true;
  }

  /// Rewrite the schedule from the given tasks.
  ///
  /// Cancel-then-schedule rather than a diff. The armed set is a handful of
  /// rows, and a diff would have to track what it had already scheduled -
  /// state that gets stale the moment the OS drops a notification or the user
  /// clears one, and that would then silently stop rescheduling it.
  Future<void> reschedule(List<Task> armed) async {
    if (!supported || !_ready) return;

    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    for (final t in armed) {
      final at = t.remindAtTime;
      if (at == null || !t.isActive) continue;

      final when = tz.TZDateTime.from(at, tz.local);
      // Already past: [ReminderService] owns those. Handing the OS a date in
      // the past either fires immediately on every app start or is dropped,
      // depending on the platform - neither is a reminder.
      if (!when.isAfter(now)) continue;

      try {
        await _plugin.zonedSchedule(
          id: idFor(t.uuid),
          title: 'Reminder',
          body: t.text,
          scheduledDate: when,
          payload: t.uuid,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          // A reminder is a moment the user picked, so it should not be
          // deferred into a doze window. Falls back to inexact automatically
          // when the OS refuses the exact-alarm permission.
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        // One bad row must not cost the rest their reminders.
        debugPrint('Could not schedule reminder for ${t.uuid}: $e');
      }
    }
  }

  /// Notification ids are 32-bit ints, task ids are uuids. A stable hash keeps
  /// the mapping deterministic, so rescheduling a task replaces its own
  /// notification instead of stacking up duplicates.
  @visibleForTesting
  static int idFor(String uuid) {
    var h = 0;
    for (final c in uuid.codeUnits) {
      h = (h * 31 + c) & 0x3fffffff;
    }
    return h;
  }

  Future<void> cancelAll() async {
    if (!supported || !_ready) return;
    await _plugin.cancelAll();
  }
}
