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

  /// Called when the user taps a task reminder. Wired to the same path the tray
  /// and the global shortcuts use, so a tapped reminder lands on its task.
  void Function(String taskUuid)? onTapped;

  /// Called when the user taps a calendar event's notification.
  void Function(String eventUuid)? onEventTapped;

  /// Payloads say which kind of row they came from.
  ///
  /// Both live in one notification namespace - `cancelAll` does not know the
  /// difference - so an unprefixed uuid would send a tapped event down the task
  /// path, which silently does nothing when no task has that id.
  static const _taskPrefix = 'task:';
  static const _eventPrefix = 'event:';

  static const _channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Tasks you asked to be reminded about.',
    importance: Importance.high,
  );

  /// A separate channel so the calendar can be silenced in the OS settings
  /// without also silencing task reminders - they are different kinds of
  /// interruption and Android lets the user say so per channel.
  static const _eventChannel = AndroidNotificationChannel(
    'calendar',
    'Calendar',
    description: 'Events coming up on your calendars.',
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
        final payload = r.payload;
        if (payload == null || payload.isEmpty) return;
        if (payload.startsWith(_eventPrefix)) {
          onEventTapped?.call(payload.substring(_eventPrefix.length));
        } else if (payload.startsWith(_taskPrefix)) {
          onTapped?.call(payload.substring(_taskPrefix.length));
        } else {
          // A notification scheduled by a build that predates the prefixes.
          onTapped?.call(payload);
        }
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(_channel);
      await android.createNotificationChannel(_eventChannel);
      // Android 13+. Declining is not an error: the in-app poll still shows the
      // row as due, so the app degrades to exactly its desktop behaviour.
      await android.requestNotificationsPermission();
    }

    _ready = true;
  }

  /// Rewrite the whole schedule: task reminders and calendar events together.
  ///
  /// Cancel-then-schedule rather than a diff. The armed set is a handful of
  /// rows, and a diff would have to track what it had already scheduled -
  /// state that gets stale the moment the OS drops a notification or the user
  /// clears one, and that would then silently stop rescheduling it.
  ///
  /// Tasks and events are rewritten in **one** call because the cancel is
  /// global. Two separate reschedule methods would each wipe the other's work,
  /// and the loser would be whichever ran first.
  Future<void> reschedule(
    List<Task> armed, {
    List<CalendarEvent> events = const [],
    Map<String, Calendar> calendars = const {},
  }) async {
    if (!supported || !_ready) return;

    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);

    for (final t in armed) {
      final at = t.remindAtTime;
      if (at == null || !t.isActive) continue;
      await _scheduleOne(
        id: idFor(t.uuid),
        title: 'Reminder',
        body: t.text,
        at: at,
        now: now,
        payload: '$_taskPrefix${t.uuid}',
        channel: _channel,
        describe: 'reminder for ${t.uuid}',
      );
    }

    for (final e in events) {
      // The lead time is the calendar's unless the event overrides it, and
      // either can resolve to "stay quiet".
      final at = e.notifyAt(calendars[e.calendarUuid]);
      if (at == null) continue;
      await _scheduleOne(
        id: idFor(e.uuid),
        title: e.title,
        body: _eventBody(e),
        at: at,
        now: now,
        payload: '$_eventPrefix${e.uuid}',
        channel: _eventChannel,
        describe: 'event ${e.uuid}',
      );
    }
  }

  /// "14:00 – 15:30", plus the description when there is one. The time is the
  /// part that makes a notification actionable at a glance.
  static String _eventBody(CalendarEvent e) {
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final when = '${hhmm(e.start)} – ${hhmm(e.end)}';
    return e.description.isEmpty ? when : '$when · ${e.description}';
  }

  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    required tz.TZDateTime now,
    required String payload,
    required AndroidNotificationChannel channel,
    required String describe,
  }) async {
    final when = tz.TZDateTime.from(at, tz.local);
    // Already past: [ReminderService] owns those. Handing the OS a date in
    // the past either fires immediately on every app start or is dropped,
    // depending on the platform - neither is a reminder.
    if (!when.isAfter(now)) return;

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: when,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
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
      // One bad row must not cost the rest their notifications.
      debugPrint('Could not schedule $describe: $e');
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
