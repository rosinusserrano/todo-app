// Subscribed calendars: turning a fetched .ics into calendar_events rows.
//
// The subscription (a [CalendarFeed] row) says where to fetch and which
// calendar the events land in. A refresh fetches the file, expands it into
// **instances** over a window, and hands the rows to
// [LocalStore.applyFeedRows], which writes only what changed and tombstones
// what the feed no longer has. Four decisions carry the rest:
//
//   - **Instances, not rules.** A feed's series are expanded here (rrule.dart)
//     and every occurrence is its own row, rather than being stored as one row
//     with a [Recur] rule the way a block made here is. Real calendars are full
//     of rules this app cannot store, and of single occurrences that were moved
//     or cancelled (RECURRENCE-ID, EXDATE) - one row per occurrence is what lets
//     all of that be shown exactly as the source has it.
//   - **Derived ids.** An instance's uuid is a v5 over the feed, the event's
//     UID and - for an occurrence of a series - the instant it was *scheduled*
//     for. Every device holding the subscription refreshes it, and this is what
//     makes them write the same rows instead of a copy each. Being keyed on the
//     scheduled instant rather than the actual one is what makes a meeting that
//     moved an *edit* to its row rather than a delete plus an add, so anything
//     planned into it stays planned into it.
//   - **A window**, from [feedPast] behind today to [feedAhead] in front, both
//     day-aligned so two devices on the same day agree on it exactly. Without
//     one a daily rule has no end.
//   - **Read-only.** The feed is the authority for these rows; see
//     [CalendarEvent.feedUuid].

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'ics.dart';
import 'models.dart';
import 'rrule.dart';

/// How far back a refresh writes. Older occurrences already written are kept;
/// they are just no longer refreshed.
const feedPast = Duration(days: 90);

/// How far ahead. A year is what the year view can show.
const feedAhead = Duration(days: 366);

/// How often a feed is fetched while the app is running. Google regenerates
/// its secret address on the order of hours, so asking more often buys
/// nothing.
const feedInterval = Duration(minutes: 30);

/// After a failure, sooner - a laptop that has just woken up has no network
/// for its first few seconds, and half an hour is a long time to show a stale
/// calendar for that.
const feedRetry = Duration(minutes: 5);

/// A fixed namespace, so the same instance gets the same id on every device.
const feedNamespace = '3a2f6d4e-8c71-5b09-9e4a-1d7c0b5f2e83';

const _uuid = Uuid();

/// The window a refresh at [now] covers.
({DateTime from, DateTime to}) feedWindow([DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return (
    from: DateTime(today.year, today.month, today.day - feedPast.inDays),
    to: DateTime(today.year, today.month, today.day + feedAhead.inDays),
  );
}

/// One occurrence out of a feed.
class FeedInstance {
  const FeedInstance(this.key, this.event, this.start, this.end);

  /// What identifies it across refreshes: the UID, plus the instant it was
  /// scheduled for when it is one of a series.
  final String key;
  final IcsEvent event;
  final DateTime start;
  final DateTime end;
}

/// Every occurrence in [events] that overlaps `[from, to)`.
///
/// A series is expanded from its RRULE and RDATEs, less its EXDATEs; an
/// occurrence that has its own VEVENT (same UID, with a RECURRENCE-ID) is
/// replaced by it - or dropped, when that VEVENT is cancelled. A rule that
/// rrule.dart cannot expand keeps its first occurrence, as the import does.
List<FeedInstance> expandFeed(
  List<IcsEvent> events,
  DateTime from,
  DateTime to,
) {
  final masters = <String, IcsEvent>{};
  final overrides = <String, Map<int, IcsEvent>>{};
  var anonymous = 0;

  for (final e in events) {
    // A VEVENT with no UID is malformed, but common enough in hand-made files
    // to be worth a stable key: the title and start are what a person would
    // call "the same event".
    final uid = e.uid ?? 'nouid:${e.summary}@${e.start.toUtc().toIso8601String()}';
    final rid = e.recurrenceId;
    if (rid != null) {
      (overrides[uid] ??= {})[rid.millisecondsSinceEpoch] = e;
    } else if (masters.containsKey(uid)) {
      masters['$uid#${anonymous++}'] = e;
    } else {
      masters[uid] = e;
    }
  }

  final out = <FeedInstance>[];
  void add(String key, IcsEvent e, DateTime start, DateTime end) {
    if (start.isBefore(to) && end.isAfter(from)) {
      out.add(FeedInstance(key, e, start, end));
    }
  }

  for (final MapEntry(key: uid, value: e) in masters.entries) {
    if (e.cancelled) continue;
    final moved = overrides[uid] ?? const {};

    final rule = e.rrule;
    if (rule == null && e.rdates.isEmpty) {
      add(uid, e, e.start, e.end);
      continue;
    }

    final time = e.startTime ??
        IcsTime(DateTime.utc(e.start.year, e.start.month, e.start.day,
            e.start.hour, e.start.minute, e.start.second));
    final List<DateTime> starts;
    final walls = rule == null
        ? null
        : expandRrule(
            rule,
            time.wall,
            instantOf: (w) => time.at(w).toLocal(),
            before: to,
          );
    starts = [
      if (walls == null) e.start else ...walls.map((w) => time.at(w).toLocal()),
      ...e.rdates,
    ];

    final struck = {for (final x in e.exdates) x.millisecondsSinceEpoch};
    final seen = <int>{};
    for (final start in starts) {
      final ms = start.millisecondsSinceEpoch;
      if (!seen.add(ms) || struck.contains(ms) || moved.containsKey(ms)) {
        continue;
      }
      add('$uid@${start.toUtc().toIso8601String()}', e, start,
          _endFor(e, start));
    }

    for (final MapEntry(key: ms, value: o) in moved.entries) {
      if (o.cancelled || struck.contains(ms)) continue;
      final scheduled = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      add('$uid@${scheduled.toIso8601String()}', o, o.start, o.end);
    }
  }

  // An override whose series is not in the file at all (a feed that only
  // carries the exceptions in range) is still an event.
  for (final MapEntry(key: uid, value: moved) in overrides.entries) {
    if (masters.containsKey(uid)) continue;
    for (final MapEntry(key: ms, value: o) in moved.entries) {
      if (o.cancelled) continue;
      final scheduled = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      add('$uid@${scheduled.toIso8601String()}', o, o.start, o.end);
    }
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The end of one occurrence: the series' length, counted in days for an
/// all-day event so a two-day booking stays two days across a clock change.
DateTime _endFor(IcsEvent e, DateTime start) {
  if (!e.allDay) return start.add(e.duration);
  final days = DateTime.utc(e.end.year, e.end.month, e.end.day)
      .difference(DateTime.utc(e.start.year, e.start.month, e.start.day))
      .inDays;
  return DateTime(start.year, start.month, start.day + (days < 1 ? 1 : days));
}

/// The row one instance becomes on [feed]'s calendar.
///
/// The stamps are placeholders: [LocalStore.applyFeedRows] decides them, since
/// whether this is a new row, a changed one or nothing to write is only known
/// against what is already there.
CalendarEvent feedRow(CalendarFeed feed, FeedInstance i) {
  final e = i.event;
  final description = [
    if (e.location.isNotEmpty) e.location,
    if (e.description.isNotEmpty) e.description,
  ].join('\n\n');
  return CalendarEvent(
    uuid: _uuid.v5(feedNamespace, '${feed.uuid}|${i.key}'),
    calendarUuid: feed.calendarUuid,
    title: e.summary,
    description: description,
    startAt: reminderStamp(i.start),
    endAt: reminderStamp(i.end),
    // Silent rather than inheriting when alerts are off, so a feed landing in
    // a calendar that notifies does not start notifying for every meeting in
    // somebody's work calendar.
    notifyMinutes: feed.alerts ? null : CalendarEvent.notifySilent,
    allDay: e.allDay,
    feedUuid: feed.uuid,
    createdAt: '',
    updatedAt: '',
  );
}

/// Everything a refresh writes for [feed], from the file's text.
List<CalendarEvent> feedRows(
  CalendarFeed feed,
  String ics, {
  required DateTime from,
  required DateTime to,
}) =>
    [
      for (final i in expandFeed(parseIcs(ics), from, to)) feedRow(feed, i),
    ];

/// Why a fetch did not produce a calendar, in words for the settings line.
class FeedError implements Exception {
  const FeedError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches a feed's text. Injected, because how depends on the platform: a
/// native build asks the address directly, while a browser cannot (calendar
/// services do not send CORS headers) and asks the sync server to fetch it.
typedef FeedFetcher = Future<String> Function(Uri url);

/// What a fetch must look like to be a calendar at all.
///
/// The commonest wrong address is a calendar's *public* page or its sharing
/// link, which is HTML; parsing that would "succeed" with no events and empty
/// the calendar. Refusing it keeps what is already there.
String checkFeedText(String body) {
  if (!body.contains('BEGIN:VCALENDAR')) {
    throw const FeedError(
        'That address did not return a calendar. Use the iCal (.ics) '
        'address, not the page link.');
  }
  return body;
}

/// The native fetcher: a plain GET.
Future<String> fetchFeedDirect(Uri url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c.get(url).timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) {
      throw const FeedError('Not found - the address may have been reset.');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const FeedError('Not allowed - the calendar is not shared at that '
          'address.');
    }
    if (res.statusCode != 200) {
      throw FeedError('The calendar server answered ${res.statusCode}.');
    }
    return checkFeedText(_decode(res));
  } on FeedError {
    rethrow;
  } catch (e) {
    throw FeedError('Could not reach it: ${_short(e)}');
  } finally {
    if (client == null) c.close();
  }
}

/// iCalendar is UTF-8 by definition, whatever the header claims (or fails to:
/// `http` falls back to Latin-1 when there is no charset, which turns every
/// umlaut in a title into two characters).
String _decode(http.Response res) =>
    const Utf8Decoder(allowMalformed: true).convert(res.bodyBytes);

String _short(Object e) {
  final s = e.toString();
  return s.length > 100 ? '${s.substring(0, 100)}...' : s;
}
