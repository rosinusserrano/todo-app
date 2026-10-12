// Reading iCalendar (.ics) events, so an invite from another app can be added
// to a workspace calendar.
//
// This is a *reader for what other apps send*, not an iCalendar implementation.
// A mail client sharing an invite, a booking confirmation, a train ticket: all
// of them produce a small VEVENT with a start, an end and a summary, and that
// is what this understands. VALARM, VTIMEZONE, attendees and the rest are
// parsed as far as being skipped correctly and no further. An RRULE is read
// only when it maps *exactly* onto one of this app's own repeat rules (see
// [icsRecurRule]); anything else still comes in as its first occurrence with a
// note saying so, because guessing at a rule we cannot store would be wrong
// every week rather than once.
//
// The three parts of RFC 5545 that actually bite, and are handled:
//
//   1. **Line folding.** Long lines are split with CRLF followed by a single
//      space or tab, and the continuation must be re-joined *before* anything
//      is parsed. A folded DESCRIPTION otherwise turns into a truncated
//      description plus a garbage property.
//   2. **Escaping.** Inside a text value, `\n` is a newline and `\, \; \\` are
//      literal punctuation. Skipping this turns every comma in a summary into
//      a visible backslash.
//   3. **Three kinds of timestamp.** `...Z` is UTC, a bare local time is
//      floating (whatever the reader's timezone is), and `TZID=` names a zone,
//      resolved through the IANA database the notification code already
//      carries. See [_parseStamp].
//
// A subscribed calendar (feeds.dart) needs more of a VEVENT than an invite
// does, and it is all read here so there is one parser: the UID, the raw
// RRULE, EXDATE and RDATE, RECURRENCE-ID (one occurrence of a series moved or
// retitled) and STATUS:CANCELLED. The import ignores all of them except as
// before; the feed is what expands them.

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart' show Recur;

/// A time as an .ics file wrote it: the reading, and what it is a reading of.
///
/// Kept apart from the instant because a repeat is counted in the *reading*.
/// A weekly 09:00 meeting written in Europe/Berlin is at 09:00 Berlin time in
/// both halves of the year, which is two different UTC hours; stepping the
/// instant by seven days would move it an hour for half the year.
class IcsTime {
  const IcsTime(this.wall, {this.zone, this.utc = false, this.date = false});

  /// The reading, in a UTC [DateTime] used purely as a container for the
  /// fields - UTC because it has no DST, so adding days to it is exact.
  final DateTime wall;

  /// The TZID it was written in, or null.
  final String? zone;

  /// Written with a trailing `Z`.
  final bool utc;

  /// A DATE rather than a DATE-TIME: a whole day, floating.
  final bool date;

  /// The same kind of time at another reading - an occurrence of a series.
  IcsTime at(DateTime wall) =>
      IcsTime(wall, zone: zone, utc: utc, date: date);

  /// The instant this names, as a local [DateTime].
  ///
  /// A zone the database does not know - Outlook writes Windows names like
  /// "W. Europe Standard Time" - is read as floating, which keeps the reading
  /// as written. That is right whenever the zone is the one the device is in,
  /// which is nearly always, and an event at the time printed on the invite is
  /// the better failure than one moved by a guessed offset.
  DateTime toLocal() {
    final w = wall;
    if (date) return DateTime(w.year, w.month, w.day);
    if (utc) return w.toLocal();
    final location = _location(zone);
    if (location != null) {
      final at = tz.TZDateTime(location, w.year, w.month, w.day, w.hour,
          w.minute, w.second);
      return DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch);
    }
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second);
  }

  static tz.Location? _location(String? name) {
    if (name == null || name.isEmpty) return null;
    // Initialised on first use rather than at startup: most runs never meet a
    // TZID. Not when it already is - initialising again resets tz.local to
    // UTC, which is what the notification schedule reads.
    if (!tz.timeZoneDatabase.isInitialized) tzdata.initializeTimeZones();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }
}

/// One event out of an .ics file.
class IcsEvent {
  const IcsEvent({
    required this.summary,
    required this.start,
    required this.end,
    this.description = '',
    this.location = '',
    this.allDay = false,
    this.recurring = false,
    this.recur,
    this.uid,
    this.startTime,
    this.rrule,
    this.exdates = const [],
    this.rdates = const [],
    this.recurrenceId,
    this.cancelled = false,
  });

  final String summary;

  /// Local time, ready to hand to the calendar.
  final DateTime start;
  final DateTime end;

  final String description;
  final String location;

  /// A DATE-valued start, meaning a whole day rather than a moment.
  final bool allDay;

  /// The source carried an RRULE.
  ///
  /// True whether or not [recur] could express it, because it is what the
  /// import list has to disclose: a rule we cannot store comes in as its first
  /// occurrence, and importing one of a series while saying nothing is exactly
  /// the sort of thing discovered three weeks late.
  final bool recurring;

  /// The rule as one of [Recur.rules], when the RRULE maps onto it exactly, or
  /// null when it does not.
  ///
  /// Deliberately strict - see [icsRecurRule]. An approximation would be
  /// *wrong every week for ever*, which is worse than importing one block and
  /// admitting it.
  final String? recur;

  final String? uid;

  /// [start] as written, for counting a series in its own timezone. Null only
  /// for an event built by hand rather than parsed.
  final IcsTime? startTime;

  /// The RRULE value as written, for a subscription to expand. The import
  /// reads [recur] instead.
  final String? rrule;

  /// Occurrences struck out of the series (EXDATE), as local instants.
  final List<DateTime> exdates;

  /// Occurrences added to it (RDATE), as local instants.
  final List<DateTime> rdates;

  /// Set when this VEVENT replaces one occurrence of the series sharing its
  /// [uid]: the instant that occurrence would otherwise have had.
  final DateTime? recurrenceId;

  /// STATUS:CANCELLED. A cancelled occurrence is how some producers strike one
  /// out instead of an EXDATE.
  final bool cancelled;

  Duration get duration => end.difference(start);
}

/// The calendar's own name (`X-WR-CALNAME`), which Google, Apple and Outlook
/// all write, or null. What a new subscription is called until renamed.
String? icsCalendarName(String text) {
  for (final line in _unfold(text)) {
    final upper = line.toUpperCase();
    if (upper == 'BEGIN:VEVENT') break;
    if (upper.startsWith('X-WR-CALNAME')) {
      final prop = _Prop.parse(line);
      final name = prop == null ? '' : _unescape(prop.value).trim();
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

/// Everything importable in one file, in the order it appeared.
///
/// Returns an empty list rather than throwing for anything unparseable: this is
/// fed by other applications, and one malformed VEVENT in a file of five should
/// cost that one event, not the import.
List<IcsEvent> parseIcs(String text) {
  final out = <IcsEvent>[];

  Map<String, List<_Prop>>? current;

  // How deep we are inside a component nested in the VEVENT - a VALARM, in
  // practice. Its properties must not land in the event's map: an alarm has its
  // own DESCRIPTION ("Reminder") and its own TRIGGER, and a producer that emits
  // the alarm before the event's own DESCRIPTION would otherwise have the
  // alarm's text win.
  var nested = 0;

  for (final line in _unfold(text)) {
    final upper = line.toUpperCase();

    if (current == null) {
      if (upper == 'BEGIN:VEVENT') {
        current = {};
        nested = 0;
      }
      continue;
    }

    if (upper.startsWith('BEGIN:')) {
      nested++;
      continue;
    }
    if (upper.startsWith('END:')) {
      if (nested > 0) {
        nested--;
        continue;
      }
      // END of anything at depth zero closes the event. Treating only
      // END:VEVENT as the terminator would let a malformed file swallow the
      // rest of the calendar into one event.
      final event = _build(current);
      if (event != null) out.add(event);
      current = null;
      continue;
    }
    if (nested > 0) continue;

    final prop = _Prop.parse(line);
    // Every occurrence is kept, because EXDATE and RDATE may legitimately
    // appear several times. Everything else reads the first: a malformed file
    // with two SUMMARYs should not have the later one silently replace a good
    // earlier one.
    if (prop != null) (current[prop.name] ??= []).add(prop);
  }

  return out;
}

/// Undo RFC 5545 line folding, and normalise line endings.
///
/// A continuation is a CRLF (or LF) followed by exactly one space or tab; that
/// one whitespace character is part of the folding, not of the value.
List<String> _unfold(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final out = <String>[];

  for (final line in lines) {
    if (line.isEmpty) continue;
    if ((line.startsWith(' ') || line.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += line.substring(1);
    } else {
      out.add(line);
    }
  }
  return out;
}

/// One `NAME;PARAM=x:value` line.
class _Prop {
  const _Prop(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;

  static _Prop? parse(String line) {
    final colon = _valueColon(line);
    if (colon < 0) return null;

    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);

    final parts = head.split(';');
    final name = parts.first.toUpperCase().trim();
    if (name.isEmpty) return null;

    final params = <String, String>{};
    for (final p in parts.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) {
        params[p.substring(0, eq).toUpperCase().trim()] = p
            .substring(eq + 1)
            .replaceAll('"', '')
            .trim();
      }
    }
    return _Prop(name, params, value);
  }

  /// The colon that separates the value, skipping any inside a quoted
  /// parameter - `DTSTART;TZID="Europe/Berlin":2026...` has two.
  static int _valueColon(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') quoted = !quoted;
      if (c == ':' && !quoted) return i;
    }
    return -1;
  }
}

/// Undo text escaping: `\n` is a newline, `\, \; \\` are literals.
String _unescape(String v) {
  final buffer = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    if (v[i] != r'\' || i + 1 >= v.length) {
      buffer.write(v[i]);
      continue;
    }
    final next = v[++i];
    buffer.write(switch (next) {
      'n' || 'N' => '\n',
      r'\' => r'\',
      ',' => ',',
      ';' => ';',
      _ => next,
    });
  }
  return buffer.toString();
}

/// Parse one of iCalendar's three timestamp shapes.
///
/// `20260814T093000Z` is UTC. `20260814T093000` without a zone is *floating* -
/// it means that reading wherever it is opened, which is what a train ticket
/// wants. `TZID=Europe/Berlin:20260814T093000` is that reading in that zone;
/// see [IcsTime.toLocal] for a zone that cannot be resolved.
IcsTime? _parseStamp(_Prop prop) =>
    _parseValue(prop.value.trim(), prop.params);

IcsTime? _parseValue(String raw, Map<String, String> params) {
  final isDate =
      params['VALUE']?.toUpperCase() == 'DATE' ||
      RegExp(r'^\d{8}$').hasMatch(raw);

  if (isDate) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(raw);
    if (m == null) return null;
    return IcsTime(
      DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
      date: true,
    );
  }

  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
  ).firstMatch(raw);
  if (m == null) return null;

  final wall = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  if (m[7] == 'Z') return IcsTime(wall, utc: true);
  return IcsTime(wall, zone: params['TZID']);
}

/// Every instant in a list-valued property (EXDATE, RDATE), across however
/// many lines it was written on.
List<DateTime> _instants(List<_Prop>? props) => [
      for (final p in props ?? const <_Prop>[])
        for (final v in p.value.split(','))
          ?_parseValue(v.trim(), p.params)?.toLocal(),
    ];

IcsEvent? _build(Map<String, List<_Prop>> all) {
  final props = {for (final e in all.entries) e.key: e.value.first};
  final startProp = props['DTSTART'];
  if (startProp == null) return null;

  final startTime = _parseStamp(startProp);
  if (startTime == null) return null;
  final start = (at: startTime.toLocal(), allDay: startTime.date);

  // DTEND is optional. DURATION is the other way of saying it, and a bare
  // DTSTART means a default length rather than a zero-length event, which no
  // calendar can draw.
  DateTime? end;
  final endProp = props['DTEND'];
  if (endProp != null) end = _parseStamp(endProp)?.toLocal();
  end ??= _addDuration(start.at, props['DURATION']?.value);
  end ??= start.allDay
      ? start.at.add(const Duration(days: 1))
      : start.at.add(const Duration(hours: 1));

  // An all-day DTEND is exclusive - a one-day event ends on the *next* day -
  // and an end that is not after the start cannot be drawn at all.
  if (!end.isAfter(start.at)) {
    end = start.at.add(
      start.allDay ? const Duration(days: 1) : const Duration(hours: 1),
    );
  }

  final summary = _unescape(props['SUMMARY']?.value ?? '').trim();

  return IcsEvent(
    summary: summary.isEmpty ? 'Untitled event' : summary,
    start: start.at,
    end: end,
    description: _unescape(props['DESCRIPTION']?.value ?? '').trim(),
    location: _unescape(props['LOCATION']?.value ?? '').trim(),
    allDay: start.allDay,
    recurring: props.containsKey('RRULE'),
    recur: icsRecurRule(props['RRULE']?.value, start.at),
    uid: props['UID']?.value.trim(),
    startTime: startTime,
    rrule: props['RRULE']?.value.trim(),
    exdates: _instants(all['EXDATE']),
    rdates: _instants(all['RDATE']),
    recurrenceId: props['RECURRENCE-ID'] == null
        ? null
        : _parseStamp(props['RECURRENCE-ID']!)?.toLocal(),
    cancelled: props['STATUS']?.value.trim().toUpperCase() == 'CANCELLED',
  );
}

/// The [Recur] rule an RRULE means, or null when it means something this app
/// cannot say.
///
/// Strict on purpose. The rules here are periods with no end and no interval,
/// so anything carrying COUNT, UNTIL, INTERVAL or a BY-part that is not simply
/// restating DTSTART is **rejected** rather than rounded to the nearest thing
/// we have. A six-week course imported as "every week for ever" would be wrong
/// on the seventh week and every week after it, silently, on a calendar the
/// user now trusts; one imported block plus the note saying why is a smaller
/// and much more visible loss.
///
/// The one BY-part that is honoured is `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR`,
/// because that is [Recur.weekdays] exactly and is what every "every working
/// day" event in the wild emits.
String? icsRecurRule(String? rrule, DateTime start) {
  if (rrule == null) return null;

  final parts = <String, String>{};
  for (final piece in rrule.toUpperCase().split(';')) {
    final i = piece.indexOf('=');
    if (i <= 0) continue;
    parts[piece.substring(0, i).trim()] = piece.substring(i + 1).trim();
  }

  if (parts.containsKey('COUNT') || parts.containsKey('UNTIL')) return null;

  final interval = parts['INTERVAL'];
  if (interval != null && interval != '1') return null;

  final byDay = parts['BYDAY'];
  // Any other BY-part is a shape this app has no column for.
  final otherBy = parts.keys.any((k) => k.startsWith('BY') && k != 'BYDAY');
  if (otherBy) return null;

  const dayNames = {
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };

  switch (parts['FREQ']) {
    case 'DAILY':
      return byDay == null ? Recur.daily : null;

    case 'WEEKLY':
      if (byDay == null) return Recur.weekly;
      final days = byDay.split(',').map((d) => d.trim()).toSet();
      if (days.length == 5 &&
          days.containsAll(const {'MO', 'TU', 'WE', 'TH', 'FR'})) {
        return Recur.weekdays;
      }
      // A single BYDAY that just restates the day DTSTART already falls on
      // adds nothing, so it is still a plain weekly rule.
      if (days.length == 1 && days.first == dayNames[start.weekday]) {
        return Recur.weekly;
      }
      return null;

    case 'MONTHLY':
      return byDay == null ? Recur.monthly : null;

    case 'YEARLY':
      return byDay == null ? Recur.yearly : null;
  }
  return null;
}

/// Parse the subset of ISO 8601 durations iCalendar uses: `PT1H30M`, `P2D`.
DateTime? _addDuration(DateTime from, String? raw) {
  if (raw == null) return null;
  final m = RegExp(
    r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(raw.trim().toUpperCase());
  if (m == null) return null;

  int g(int i) => int.tryParse(m[i] ?? '') ?? 0;
  final d = Duration(
    days: g(1) * 7 + g(2),
    hours: g(3),
    minutes: g(4),
    seconds: g(5),
  );
  return d == Duration.zero ? null : from.add(d);
}
