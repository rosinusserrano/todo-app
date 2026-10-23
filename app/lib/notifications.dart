// OS notifications for reminders, on mobile and on Windows.
//
// **Windows** (Marco, 2026-10-23: "as other apps do, not just opening the
// app") shows toasts in two ways. A calendar event is scheduled with the OS
// ahead of time, like on a phone, so it arrives even with the app closed.
// A task's, a thought's and a shelf's reminder are toasted by the poll the
// moment it finds them due ([showDue]), instead of the window being pulled
// to the front: the poll already owns "due", including what came due while
// the app was closed, and a scheduled toast as well would be a second
// announcement of the same thing twenty seconds later. Clicking a toast
// lands on what it was about, as a tap does on a phone. Unpackaged (no MSIX)
// Windows cannot take back a toast already shown - only scheduled ones -
// which is fine: the cancel here exists to rewrite the schedule.
//
// [ReminderService] is the alert on the other desktops: it surfaces the
// always-on-top window, which needs no notification permission. That does
// not carry to a phone. iOS and Android
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

import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'platform.dart';
import 'sync/models.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Mobile and Windows; the other desktops surface the window instead - see
  /// the file header.
  static bool get supported => isMobile || isWindows;

  /// Task, thought and review reminders are toasted by the poll
  /// ([showDue]) rather than scheduled ahead - see the file header.
  static bool get toastsFromPoll => isWindows;

  /// Who the toasts say they are from. The GUID names the activation
  /// callback the plugin registers; it must never change, or Windows routes
  /// clicks on old toasts to nothing.
  static const _windowsAppName = 'Todo Widget';
  static const _windowsAumid = 'Marco.TodoWidget';
  static const _windowsGuid = '4c1a4bf2-b30b-43f2-843a-4174b5c38b5b';

  /// The tray's icon, by path out of the bundle beside the exe - a toast's
  /// icon is read from disk.
  static String _windowsIcon() =>
      '${File(Platform.resolvedExecutable).parent.path}'
      r'\data\flutter_assets\assets\tray_icon.png';

  bool _ready = false;

  /// Called when the user taps a task reminder. Wired to the same path the tray
  /// and the global shortcuts use, so a tapped reminder lands on its task.
  void Function(String taskUuid)? onTapped;

  /// Called when the user taps a calendar event's notification.
  void Function(String eventUuid)? onEventTapped;

  /// Called when the user taps a thought's reminder.
  void Function(String thoughtUuid)? onThoughtTapped;

  /// Called when the user taps a shelf's review reminder.
  void Function(String groupUuid)? onReviewTapped;

  /// Payloads say which kind of row they came from.
  ///
  /// Both live in one notification namespace - `cancelAll` does not know the
  /// difference - so an unprefixed uuid would send a tapped event down the task
  /// path, which silently does nothing when no task has that id.
  static const _taskPrefix = 'task:';
  static const _eventPrefix = 'event:';
  static const _thoughtPrefix = 'thought:';
  static const _reviewPrefix = 'review:';

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

  /// Never throws: it runs in `main()`, and notifications failing to start
  /// must not be why the app does not.
  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await _init();
    } catch (e) {
      debugPrint('Notifications are off: $e');
    }
  }

  Future<void> _init() async {
    // zonedSchedule needs a real location, not just an offset: an offset fixed
    // at scheduling time would fire an hour out across a DST boundary.
    tzdata.initializeTimeZones();
    final local = await FlutterTimezone.getLocalTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } on tz.LocationNotFoundException {
      // Windows answers "Etc/Unknown" for a zone it cannot map. The instants
      // scheduled are still right (TZDateTime.from keeps the instant); only
      // nothing here repeats by wall clock, so UTC is a safe stand-in.
      debugPrint('Unknown time zone ${local.identifier}; scheduling in UTC');
    }

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: const DarwinInitializationSettings(),
        windows: isWindows
            ? WindowsInitializationSettings(
                appName: _windowsAppName,
                appUserModelId: _windowsAumid,
                guid: _windowsGuid,
                iconPath: _windowsIcon(),
              )
            : null,
      ),
      onDidReceiveNotificationResponse: (r) => _route(r.payload),
    );

    // Launched by a click on a toast (or a notification) while it was not
    // running: land where that click meant, once the shell is listening.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchPayload = launch!.notificationResponse?.payload;
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(_channel);
      await android.createNotificationChannel(_eventChannel);
      // Android 13+. Declining is not an error: the in-app poll still shows the
      // row as due, so the app degrades to exactly its desktop behaviour.
      await android.requestNotificationsPermission();
    }

    _ready = true;
  }

  /// A click on a notification, by its payload.
  void _route(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith(_eventPrefix)) {
      onEventTapped?.call(payload.substring(_eventPrefix.length));
    } else if (payload.startsWith(_thoughtPrefix)) {
      onThoughtTapped?.call(payload.substring(_thoughtPrefix.length));
    } else if (payload.startsWith(_reviewPrefix)) {
      onReviewTapped?.call(payload.substring(_reviewPrefix.length));
    } else if (payload.startsWith(_taskPrefix)) {
      onTapped?.call(payload.substring(_taskPrefix.length));
    } else {
      // A notification scheduled by a build that predates the prefixes.
      onTapped?.call(payload);
    }
  }

  String? _launchPayload;

  /// Hands over the click that launched the app, if one did - called by the
  /// shell once its handlers are set. Once.
  void deliverLaunch() {
    final payload = _launchPayload;
    _launchPayload = null;
    _route(payload);
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
    List<SideThought> thoughts = const [],
    List<ParkedGroup> reviews = const [],
    List<CalendarEvent> events = const [],
    Map<String, Calendar> calendars = const {},
  }) async {
    if (!supported || !_ready) return;

    await _plugin.cancelAll();

    final now = tz.TZDateTime.now(tz.local);

    // On Windows the poll toasts these as they fall due ([showDue]).
    if (toastsFromPoll) {
      armed = const [];
      thoughts = const [];
      reviews = const [];
    }

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

    // On the task channel: a thought's reminder is the same interruption.
    for (final t in thoughts) {
      final at = t.remindAtTime;
      if (at == null) continue;
      await _scheduleOne(
        id: idFor(t.uuid),
        title: 'Thought',
        body: t.text.isEmpty ? 'Voice note' : t.text,
        at: at,
        now: now,
        payload: '$_thoughtPrefix${t.uuid}',
        channel: _channel,
        describe: 'thought ${t.uuid}',
      );
    }

    // A shelf's review: quieter than a reminder in what it asks, but the same
    // channel - it is something you asked to be told about.
    for (final g in reviews) {
      final at = g.reviewRemindAt;
      if (at == null) continue;
      await _scheduleOne(
        id: idFor('review:${g.uuid}'),
        title: 'Time to review',
        body: '"${g.title}" is due for a look',
        at: at,
        now: now,
        payload: '$_reviewPrefix${g.uuid}',
        channel: _channel,
        describe: 'review of ${g.uuid}',
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
          windows: const WindowsNotificationDetails(),
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

  /// Toasts what the poll just found due, now - Windows, see the file header.
  /// Several tasks at once (the first tick after a night off) are one toast
  /// naming them, not a stack of them.
  Future<void> showDue({
    List<Task> tasks = const [],
    List<SideThought> thoughts = const [],
    List<ParkedGroup> reviews = const [],
  }) async {
    if (!supported || !_ready) return;
    if (tasks.isNotEmpty) {
      await _showNow(
        key: 'tasks:${tasks.first.uuid}',
        title: tasks.length == 1 ? 'Reminder' : '${tasks.length} reminders',
        body: tasks.map((t) => t.text).join(' · '),
        payload: '$_taskPrefix${tasks.first.uuid}',
      );
    }
    if (thoughts.isNotEmpty) {
      String text(SideThought t) => t.text.isEmpty ? 'Voice note' : t.text;
      await _showNow(
        key: 'thoughts:${thoughts.first.uuid}',
        title: thoughts.length == 1 ? 'Thought' : '${thoughts.length} thoughts',
        body: thoughts.map(text).join(' · '),
        payload: '$_thoughtPrefix${thoughts.first.uuid}',
      );
    }
    for (final g in reviews) {
      await _showNow(
        key: 'review:${g.uuid}',
        title: 'Time to review',
        body: '"${g.title}" is due for a look',
        payload: '$_reviewPrefix${g.uuid}',
      );
    }
  }

  Future<void> _showNow({
    required String key,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await _plugin.show(
        id: idFor('now:$key'),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Could not show $key: $e');
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
