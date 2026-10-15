// Reading settings out of a task's title as it is typed.
//
// The add card lets a title carry its own settings: a workspace's name puts
// the task on that workspace, a date and/or a time arms a reminder. The words
// that did that are taken out of the title when the task is written, so
// "call the bank tomorrow 9:30 Work" becomes "call the bank" on Work with a
// reminder at 09:30 tomorrow.
//
// Pure and synchronous, with `now` passed in, because it runs on every
// keystroke (the field highlights what it recognised) and because it is
// tested: every rule below is a guess about what someone meant, and the
// guesses that matter most are the ones that must *not* fire.
//
// The rules that are not obvious:
//
// - **A recognised word is only consumed if a title is left.** "Tomorrow" on
//   its own is a task called Tomorrow, not an untitled reminder.
// - **One workspace, one date, one time.** A second workspace name in the
//   same line is just a word in the title.
// - **A bare number is never a time.** "buy 2 eggs" and "chapter 12" stay as
//   they are; a time needs a colon, am/pm or "Uhr". Weekdays are full names
//   only, because "sat", "sun" and "wed" are English words.
// - **Dates are day-first** (15.10., 15/10), the way they are written where
//   this app is used. ISO (2026-10-15) is unambiguous anyway.
// - **A time alone is today, or tomorrow once it has passed.** A reminder
//   armed in the past fires the moment it is written, which reads as a bug,
//   and typing "8:00" at ten in the morning means tomorrow's eight o'clock.
// - **A date alone is 09:00 that day** - the hour the reminder menu's
//   "Tomorrow" preset uses - or the next whole hour if that has passed.
// - The current workspace is not a keyword: naming it changes nothing, so
//   consuming it would only eat a word of the title.

import 'sync/models.dart';

enum KeywordKind { workspace, date, time }

/// A stretch of the typed text that was read as a setting.
class KeywordSpan {
  const KeywordSpan(this.start, this.end, this.kind, {this.workspaceUuid});

  final int start;
  final int end;
  final KeywordKind kind;

  /// Set on a [KeywordKind.workspace] span: which workspace it named.
  final String? workspaceUuid;

  bool overlaps(KeywordSpan o) => start < o.end && o.start < end;

  @override
  String toString() => 'KeywordSpan($start, $end, $kind)';
}

class KeywordParse {
  const KeywordParse({
    required this.title,
    this.workspaceUuid,
    this.remindAt,
    this.spans = const [],
  });

  /// The title with the recognised words taken out.
  final String title;
  final String? workspaceUuid;
  final DateTime? remindAt;

  /// What was recognised, in text order - what the field highlights.
  final List<KeywordSpan> spans;

  bool get hasWorkspace => workspaceUuid != null;
  bool get hasReminder => remindAt != null;
}

/// Read [text] for settings. [hereUuid] is the workspace the card was opened
/// in, which is not a keyword (see the header). Either kind can be switched
/// off - the card does that once a setting of that kind has been chosen by
/// hand, or a recognised word has been dismissed.
KeywordParse parseTaskKeywords(
  String text, {
  required DateTime now,
  List<Workspace> workspaces = const [],
  String? hereUuid,
  bool matchWorkspaces = true,
  bool matchDates = true,
}) {
  final spans = <KeywordSpan>[];
  DateTime? day;
  int? hour, minute;
  DateTime? instant;

  if (matchDates) {
    final found = _findWhen(text, now);
    for (final m in found) {
      // Overlapping readings are alternatives, except the two halves of one
      // word that is both a date and a time ("tonight"), which share a range.
      final clashes = spans.any(
        (o) =>
            o.overlaps(m.span) &&
            !(o.start == m.span.start && o.end == m.span.end),
      );
      if (clashes) continue;
      if (m.instant != null) {
        if (instant != null || day != null || hour != null) continue;
        instant = m.instant;
      } else if (m.day != null) {
        if (day != null || instant != null) continue;
        day = m.day;
      } else {
        if (hour != null || instant != null) continue;
        hour = m.hour;
        minute = m.minute;
      }
      spans.add(m.span);
    }
  }

  String? wsUuid;
  if (matchWorkspaces) {
    final hit = _findWorkspace(text, workspaces, hereUuid, spans);
    if (hit != null) {
      spans.add(hit);
      wsUuid = hit.workspaceUuid;
    }
  }

  if (spans.isEmpty) return KeywordParse(title: text.trim());

  spans.sort((a, b) => a.start.compareTo(b.start));
  final title = _strip(text, spans);
  // Nothing would be left to call the task: the words are the title.
  if (title.isEmpty) return KeywordParse(title: text.trim());

  DateTime? at = instant;
  if (at == null && (day != null || hour != null)) {
    at = _resolve(now, day, hour, minute);
  }

  return KeywordParse(
    title: title,
    workspaceUuid: wsUuid,
    remindAt: at,
    spans: List.unmodifiable(spans),
  );
}

// ------------------------------------------------------------------ workspace

KeywordSpan? _findWorkspace(
  String text,
  List<Workspace> workspaces,
  String? hereUuid,
  List<KeywordSpan> taken,
) {
  // Longest name first, so "Meine Apps" wins over a workspace called "Apps"
  // where both would match.
  final candidates = [
    for (final w in workspaces)
      if (w.uuid != hereUuid && w.name.trim().isNotEmpty) w,
  ]..sort((a, b) => b.name.trim().length.compareTo(a.name.trim().length));

  KeywordSpan? best;
  for (final w in candidates) {
    final re = RegExp(
      '(?<![\\p{L}\\p{N}#])#?${RegExp.escape(w.name.trim())}(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    for (final m in re.allMatches(text)) {
      final span = KeywordSpan(
        m.start,
        m.end,
        KeywordKind.workspace,
        workspaceUuid: w.uuid,
      );
      if (taken.any(span.overlaps)) continue;
      if (best != null && span.overlaps(best)) continue;
      // The last one written wins: settings are usually tacked on at the end.
      if (best == null || span.start > best.start) best = span;
    }
  }
  return best;
}

// ----------------------------------------------------------------- date/time

class _When {
  _When(this.span, {this.day, this.hour, this.minute, this.instant});

  final KeywordSpan span;
  final DateTime? day;
  final int? hour;
  final int? minute;
  final DateTime? instant;
}

const _b = r'(?<![\p{L}\p{N}])';
const _e = r'(?![\p{L}\p{N}])';

RegExp _re(String body) =>
    RegExp('$_b$body$_e', caseSensitive: false, unicode: true);

const _weekdays = {
  'monday': 1,
  'montag': 1,
  'tuesday': 2,
  'dienstag': 2,
  'wednesday': 3,
  'mittwoch': 3,
  'thursday': 4,
  'donnerstag': 4,
  'friday': 5,
  'freitag': 5,
  'saturday': 6,
  'samstag': 6,
  'sonnabend': 6,
  'sunday': 7,
  'sonntag': 7,
};

const _months = {
  'jan': 1,
  'january': 1,
  'januar': 1,
  'feb': 2,
  'february': 2,
  'februar': 2,
  'mar': 3,
  'march': 3,
  'mär': 3,
  'märz': 3,
  'maerz': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'mai': 5,
  'jun': 6,
  'june': 6,
  'juni': 6,
  'jul': 7,
  'july': 7,
  'juli': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'okt': 10,
  'oktober': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
  'dez': 12,
  'dezember': 12,
};

String _alt(Iterable<String> words) =>
    (words.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');

final _monthAlt = _alt(_months.keys);
final _weekdayAlt = _alt(_weekdays.keys);

// A preposition in front of a date or time belongs to it: "on Friday",
// "at 9:30", "am 15.10.", "um 14 Uhr". Taken out with it, or the title would
// end in a dangling "at".
const _datePrep = r'(?:(?:on|am|next|this|nächsten|nächster|kommenden)\s+)?';
const _timePrep = r'(?:(?:at|um|@)\s*)?';

final _relative = _re(
  r'in\s+(\d{1,3})\s*(minutes?|mins?|m|minuten|hours?|hrs?|h|stunden?|std|'
  r'days?|d|tagen?|weeks?|w|wochen?)',
);
final _today = _re(r'today|heute');
final _tonight = _re(r'tonight|heute\s+abend');
final _dayAfter = _re(r'übermorgen|day\s+after\s+tomorrow');
final _tomorrow = _re(r'tomorrow|tmrw|morgen');
final _weekday = _re('$_datePrep($_weekdayAlt)');
final _iso = _re(r'(\d{4})-(\d{1,2})-(\d{1,2})');
// 15.10. / 15.10.2026 / 15.10.26 - the trailing dot is required without a
// year, or every decimal would be a date.
final _dotted = RegExp(
  '$_b$_datePrep(\\d{1,2})\\.(\\d{1,2})\\.(\\d{2}|\\d{4})?(?![\\p{L}\\p{N}.])',
  caseSensitive: false,
  unicode: true,
);
final _slashed = _re('$_datePrep(\\d{1,2})/(\\d{1,2})(?:/(\\d{2}|\\d{4}))?');
final _dayMonth = _re(
  '$_datePrep(\\d{1,2})\\.?\\s+($_monthAlt)\\.?(?:\\s+(\\d{4}))?',
);
final _monthDay = _re(
  '$_datePrep($_monthAlt)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?',
);
final _clock = _re('$_timePrep(\\d{1,2}):(\\d{2})(?:\\s*(am|pm|uhr|h))?');
final _meridiem = _re('$_timePrep(\\d{1,2})\\s*(am|pm)');
final _uhr = _re('$_timePrep(\\d{1,2})\\s*uhr');
final _noon = _re(r'(?:at\s+)?noon|mittags');

/// Every date and time in [text], in text order. The caller keeps the first of
/// each kind and drops overlaps, so the order of the patterns below is the
/// priority between two readings of the same characters ("15.10.2026" before
/// "15.10.").
List<_When> _findWhen(String text, DateTime now) {
  final out = <_When>[];
  final today = DateTime(now.year, now.month, now.day);

  void add(
    RegExpMatch m,
    KeywordKind kind, {
    DateTime? day,
    int? hour,
    int? minute,
    DateTime? instant,
  }) {
    final span = KeywordSpan(m.start, m.end, kind);
    if (out.any((w) => w.span.overlaps(span))) return;
    out.add(
      _When(span, day: day, hour: hour, minute: minute, instant: instant),
    );
  }

  for (final m in _relative.allMatches(text)) {
    final n = int.parse(m[1]!);
    final unit = m[2]!.toLowerCase();
    if (n == 0) continue;
    if (unit.startsWith('m') && !unit.startsWith('mo')) {
      add(m, KeywordKind.time, instant: now.add(Duration(minutes: n)));
    } else if (unit.startsWith('h') || unit.startsWith('s')) {
      add(m, KeywordKind.time, instant: now.add(Duration(hours: n)));
    } else if (unit.startsWith('d') || unit.startsWith('t')) {
      add(m, KeywordKind.date, day: _addDays(today, n));
    } else {
      add(m, KeywordKind.date, day: _addDays(today, 7 * n));
    }
  }

  for (final m in _tonight.allMatches(text)) {
    add(m, KeywordKind.date, day: today);
    // "tonight" is a date and a time at once; the time half is a second
    // entry over the same characters, which the caller accepts because it
    // is a different kind.
    out.add(
      _When(KeywordSpan(m.start, m.end, KeywordKind.time), hour: 18, minute: 0),
    );
  }
  for (final m in _dayAfter.allMatches(text)) {
    add(m, KeywordKind.date, day: _addDays(today, 2));
  }
  for (final m in _today.allMatches(text)) {
    add(m, KeywordKind.date, day: today);
  }
  for (final m in _tomorrow.allMatches(text)) {
    add(m, KeywordKind.date, day: _addDays(today, 1));
  }

  for (final m in _weekday.allMatches(text)) {
    final wd = _weekdays[m[1]!.toLowerCase()]!;
    var ahead = (wd - now.weekday) % 7;
    final explicitNext = m[0]!.toLowerCase().startsWith(RegExp('next|nächst'));
    if (explicitNext && ahead == 0) ahead = 7;
    add(m, KeywordKind.date, day: _addDays(today, ahead));
  }

  for (final m in _iso.allMatches(text)) {
    final d = _date(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d != null) add(m, KeywordKind.date, day: d);
  }
  for (final re in [_dotted, _slashed]) {
    for (final m in re.allMatches(text)) {
      // "1/2 cup" and "3/4" are fractions: a slashed date needs a two-digit
      // part somewhere, which a fraction on a shopping list never has.
      if (re == _slashed &&
          m[3] == null &&
          m[1]!.length < 2 &&
          m[2]!.length < 2) {
        continue;
      }
      final d = _dayFirst(today, int.parse(m[1]!), int.parse(m[2]!), m[3]);
      if (d != null) add(m, KeywordKind.date, day: d);
    }
  }
  for (final m in _dayMonth.allMatches(text)) {
    final d = _dayFirst(
      today,
      int.parse(m[1]!),
      _months[m[2]!.toLowerCase()]!,
      m[3],
    );
    if (d != null) add(m, KeywordKind.date, day: d);
  }
  for (final m in _monthDay.allMatches(text)) {
    final d = _dayFirst(
      today,
      int.parse(m[2]!),
      _months[m[1]!.toLowerCase()]!,
      m[3],
    );
    if (d != null) add(m, KeywordKind.date, day: d);
  }

  for (final m in _clock.allMatches(text)) {
    final t = _time(int.parse(m[1]!), int.parse(m[2]!), m[3]);
    if (t != null) add(m, KeywordKind.time, hour: t.$1, minute: t.$2);
  }
  for (final m in _meridiem.allMatches(text)) {
    final t = _time(int.parse(m[1]!), 0, m[2]);
    if (t != null) add(m, KeywordKind.time, hour: t.$1, minute: t.$2);
  }
  for (final m in _uhr.allMatches(text)) {
    final t = _time(int.parse(m[1]!), 0, 'uhr');
    if (t != null) add(m, KeywordKind.time, hour: t.$1, minute: t.$2);
  }
  for (final m in _noon.allMatches(text)) {
    add(m, KeywordKind.time, hour: 12, minute: 0);
  }

  out.sort((a, b) => a.span.start.compareTo(b.span.start));
  return out;
}

DateTime _addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

DateTime? _date(int y, int mo, int d) {
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final out = DateTime(y, mo, d);
  // DateTime normalises 31 February into March; that is a typo, not a date.
  if (out.month != mo || out.day != d) return null;
  return out;
}

/// A day and month, with the year given or the next time that date comes
/// round (today included).
DateTime? _dayFirst(DateTime today, int d, int mo, String? year) {
  if (year != null) {
    var y = int.parse(year);
    if (year.length == 2) y += 2000;
    return _date(y, mo, d);
  }
  final out = _date(today.year, mo, d);
  if (out == null) return null;
  if (out.isBefore(today)) return _date(today.year + 1, mo, d);
  return out;
}

(int, int)? _time(int h, int m, String? suffix) {
  if (m > 59) return null;
  final s = suffix?.toLowerCase();
  if (s == 'am' || s == 'pm') {
    if (h < 1 || h > 12) return null;
    final h24 = (h % 12) + (s == 'pm' ? 12 : 0);
    return (h24, m);
  }
  if (h > 23) return null;
  return (h, m);
}

/// The reminder a date and/or a time on their own amount to (see the header).
DateTime _resolve(DateTime now, DateTime? day, int? hour, int? minute) {
  if (day != null && hour != null) {
    return DateTime(day.year, day.month, day.day, hour, minute ?? 0);
  }
  if (hour != null) {
    final at = DateTime(now.year, now.month, now.day, hour, minute ?? 0);
    if (at.isAfter(now)) return at;
    return DateTime(now.year, now.month, now.day + 1, hour, minute ?? 0);
  }
  final at = DateTime(day!.year, day.month, day.day, 9);
  if (at.isAfter(now)) return at;
  return DateTime(now.year, now.month, now.day, now.hour + 1);
}

/// [text] with [spans] (sorted, non-overlapping) cut out, and the seams
/// tidied: no doubled spaces, and no colon or comma left hanging at either
/// end ("Work: ring Anna" leaves "ring Anna", not ": ring Anna").
String _strip(String text, List<KeywordSpan> spans) {
  final b = StringBuffer();
  var at = 0;
  for (final s in spans) {
    if (s.start < at) continue;
    b.write(text.substring(at, s.start));
    b.write(' ');
    at = s.end;
  }
  b.write(text.substring(at));
  return b
      .toString()
      .replaceAllMapped(RegExp(r'\s+([,;:.!?])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s,;:–-]+|[\s,;:–-]+$'), '')
      .trim();
}
