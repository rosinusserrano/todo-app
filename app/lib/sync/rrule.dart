// Expanding an iCalendar RRULE into the readings it produces.
//
// The import never needed this: it maps a rule onto one of this app's own
// [Recur] rules or brings in one occurrence and says so. A subscription cannot
// do that - "every second Tuesday", "the last Friday of the month", "weekly
// until March" are ordinary in a real calendar, and showing one of them where
// there are twelve is a calendar that lies. So a feed's series are expanded
// here into instances, and the instances are what get written (see feeds.dart).
//
// Counted in **readings**, not instants. The candidates are dates with the
// series' time of day, held in UTC DateTimes purely as containers (UTC has no
// DST, so adding a day is exact); the caller turns each reading into an
// instant in the series' own zone. That is what keeps a 09:00 Berlin meeting
// at 09:00 on both sides of a clock change.
//
// What is covered is what real producers emit: FREQ DAILY/WEEKLY/MONTHLY/
// YEARLY, INTERVAL, COUNT, UNTIL, BYDAY (with ordinals - "2TU", "-1FR"),
// BYMONTHDAY (negative counts from the end), BYMONTH, BYSETPOS and WKST.
// Anything else - BYYEARDAY, BYWEEKNO, an hourly rule - returns null and the
// caller keeps the first occurrence, which is the same honest fallback the
// import has always used.

/// The readings [rrule] produces from [start], in order, up to the first one
/// whose instant is not before [before].
///
/// [instantOf] turns a reading into the instant it names, which is what UNTIL
/// and [before] are compared against. Null means the rule uses something this
/// does not implement; the caller then has the first occurrence only.
///
/// [start] is always the first reading, as RFC 5545 requires of DTSTART - and
/// counts towards COUNT - whether or not it matches the rule.
List<DateTime>? expandRrule(
  String rrule,
  DateTime start, {
  required DateTime Function(DateTime reading) instantOf,
  required DateTime before,
  int limit = 5000,
}) {
  final rule = _Rule.parse(rrule);
  if (rule == null) return null;

  final out = <DateTime>[];
  bool done(DateTime reading) {
    if (rule.count != null && out.length >= rule.count!) return true;
    if (!instantOf(reading).isBefore(before)) return true;
    if (rule.isPastUntil(reading, instantOf)) return true;
    return out.length >= limit;
  }

  if (done(start)) return out;
  out.add(start);

  // Periods with nothing in them (BYMONTHDAY=31 in a short month) are
  // legitimate, so the guard is on periods walked, not on readings found. A
  // daily rule that began fifty years ago is about 18000 of them.
  for (var p = 0; p < 40000; p++) {
    final candidates = rule.period(start, p);
    for (final c in candidates) {
      if (!c.isAfter(start)) continue;
      if (done(c)) return out;
      out.add(c);
    }
    if (candidates.isNotEmpty &&
        !instantOf(candidates.last).isBefore(before)) {
      return out;
    }
  }
  return out;
}

class _Rule {
  _Rule({
    required this.freq,
    required this.interval,
    required this.count,
    required this.until,
    required this.byDay,
    required this.byMonthDay,
    required this.byMonth,
    required this.bySetPos,
    required this.weekStart,
  });

  final String freq;
  final int interval;
  final int? count;
  final _Until? until;

  /// (ordinal, weekday): ordinal 0 means every such weekday in the period.
  final List<(int, int)> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final List<int> bySetPos;
  final int weekStart;

  static const _weekdays = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };

  static const _supported = {
    'FREQ',
    'INTERVAL',
    'COUNT',
    'UNTIL',
    'BYDAY',
    'BYMONTHDAY',
    'BYMONTH',
    'BYSETPOS',
    'WKST',
  };

  static _Rule? parse(String raw) {
    final parts = <String, String>{};
    for (final piece in raw.toUpperCase().split(';')) {
      final i = piece.indexOf('=');
      if (i <= 0) continue;
      parts[piece.substring(0, i).trim()] = piece.substring(i + 1).trim();
    }
    if (parts.keys.any((k) => !_supported.contains(k))) return null;

    final freq = parts['FREQ'];
    if (!const {'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
      return null;
    }

    List<int>? ints(String key) {
      final v = parts[key];
      if (v == null) return const [];
      final out = <int>[];
      for (final s in v.split(',')) {
        final n = int.tryParse(s.trim());
        if (n == null || n == 0) return null;
        out.add(n);
      }
      return out;
    }

    final byDay = <(int, int)>[];
    for (final s in (parts['BYDAY'] ?? '').split(',')) {
      final t = s.trim();
      if (t.isEmpty) continue;
      final m = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(t);
      if (m == null) return null;
      byDay.add((int.tryParse(m[1] ?? '') ?? 0, _weekdays[m[2]]!));
    }

    final byMonthDay = ints('BYMONTHDAY');
    final byMonth = ints('BYMONTH');
    final bySetPos = ints('BYSETPOS');
    if (byMonthDay == null || byMonth == null || bySetPos == null) return null;
    if (byMonth.any((m) => m < 1 || m > 12)) return null;

    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    final count = parts['COUNT'] == null ? null : int.tryParse(parts['COUNT']!);
    final until = parts['UNTIL'] == null ? null : _Until.parse(parts['UNTIL']!);
    if (parts['UNTIL'] != null && until == null) return null;

    return _Rule(
      freq: freq!,
      interval: interval < 1 ? 1 : interval,
      count: count,
      until: until,
      byDay: byDay,
      byMonthDay: byMonthDay,
      byMonth: byMonth,
      bySetPos: bySetPos,
      weekStart: _weekdays[parts['WKST']] ?? DateTime.monday,
    );
  }

  bool isPastUntil(DateTime reading, DateTime Function(DateTime) instantOf) {
    final u = until;
    if (u == null) return false;
    // A UTC UNTIL is an instant; a bare one is a reading in the series' own
    // terms, and a DATE one includes the whole of that day.
    if (u.utc) return instantOf(reading).isAfter(u.at);
    if (u.date) {
      final day = DateTime.utc(reading.year, reading.month, reading.day);
      return day.isAfter(u.at);
    }
    return reading.isAfter(u.at);
  }

  /// The candidates in period [p] (counted in INTERVALs from [start]'s own
  /// period), sorted, with BYSETPOS applied.
  List<DateTime> period(DateTime start, int p) {
    final days = switch (freq) {
      'DAILY' => _daily(start, p),
      'WEEKLY' => _weekly(start, p),
      'MONTHLY' => _monthly(start, p),
      _ => _yearly(start, p),
    };
    final sorted = (days.toSet().toList()..sort());
    final picked = bySetPos.isEmpty ? sorted : _setPos(sorted);
    return [
      for (final d in picked)
        DateTime.utc(d.year, d.month, d.day, start.hour, start.minute,
            start.second),
    ];
  }

  List<DateTime> _setPos(List<DateTime> sorted) {
    final out = <DateTime>[];
    for (final n in bySetPos) {
      final i = n > 0 ? n - 1 : sorted.length + n;
      if (i >= 0 && i < sorted.length) out.add(sorted[i]);
    }
    return out..sort();
  }

  bool _monthOk(DateTime d) => byMonth.isEmpty || byMonth.contains(d.month);

  List<DateTime> _daily(DateTime start, int p) {
    final d = DateTime.utc(start.year, start.month, start.day + p * interval);
    if (!_monthOk(d)) return const [];
    if (byMonthDay.isNotEmpty &&
        !byMonthDay.any((n) => _monthDay(d.year, d.month, n) == d.day)) {
      return const [];
    }
    if (byDay.isNotEmpty && !byDay.any((b) => b.$2 == d.weekday)) {
      return const [];
    }
    return [d];
  }

  List<DateTime> _weekly(DateTime start, int p) {
    final back = (start.weekday - weekStart) % 7;
    final first = DateTime.utc(
        start.year, start.month, start.day - back + 7 * interval * p);
    final wanted = byDay.isEmpty ? {start.weekday} : byDay.map((b) => b.$2);
    return [
      for (var i = 0; i < 7; i++)
        if (DateTime.utc(first.year, first.month, first.day + i)
            case final d when wanted.contains(d.weekday) && _monthOk(d))
          d,
    ];
  }

  List<DateTime> _monthly(DateTime start, int p) {
    final index = start.month - 1 + p * interval;
    final y = start.year + index ~/ 12;
    final m = index % 12 + 1;
    if (byMonth.isNotEmpty && !byMonth.contains(m)) return const [];
    return _inMonth(y, m, start.day);
  }

  List<DateTime> _yearly(DateTime start, int p) {
    final y = start.year + p * interval;
    if (byMonth.isEmpty && byMonthDay.isEmpty && byDay.isNotEmpty) {
      return _weekdaysOfYear(y);
    }
    final months = byMonth.isNotEmpty
        ? byMonth
        : byMonthDay.isNotEmpty
            ? [for (var m = 1; m <= 12; m++) m]
            : [start.month];
    return [for (final m in months) ..._inMonth(y, m, start.day)];
  }

  /// The days of one month the BY-parts select, or [fallbackDay] when there
  /// are none. A day the month does not have is skipped rather than clamped:
  /// that is what RFC 5545 says, and what Google does with "monthly on the
  /// 31st".
  List<DateTime> _inMonth(int y, int m, int fallbackDay) {
    final length = _daysIn(y, m);
    Set<int>? byDate;
    if (byMonthDay.isNotEmpty) {
      byDate = {
        for (final n in byMonthDay)
          if (_monthDay(y, m, n) case final d when d >= 1 && d <= length) d,
      };
    }
    Set<int>? byWeekday;
    if (byDay.isNotEmpty) {
      byWeekday = {};
      for (final (ord, wd) in byDay) {
        final matching = [
          for (var d = 1; d <= length; d++)
            if (DateTime.utc(y, m, d).weekday == wd) d,
        ];
        if (ord == 0) {
          byWeekday.addAll(matching);
        } else {
          final i = ord > 0 ? ord - 1 : matching.length + ord;
          if (i >= 0 && i < matching.length) byWeekday.add(matching[i]);
        }
      }
    }
    final Set<int> days;
    if (byDate != null && byWeekday != null) {
      days = byDate.intersection(byWeekday);
    } else {
      days = byDate ??
          byWeekday ??
          {if (fallbackDay <= length) fallbackDay};
    }
    return [for (final d in days) DateTime.utc(y, m, d)];
  }

  /// BYDAY across a whole year with no BYMONTH: "20MO" is the twentieth
  /// Monday of the year.
  List<DateTime> _weekdaysOfYear(int y) {
    final out = <DateTime>[];
    for (final (ord, wd) in byDay) {
      final matching = <DateTime>[];
      for (var d = DateTime.utc(y, 1, 1);
          d.year == y;
          d = DateTime.utc(d.year, d.month, d.day + 1)) {
        if (d.weekday == wd) matching.add(d);
      }
      if (ord == 0) {
        out.addAll(matching);
      } else {
        final i = ord > 0 ? ord - 1 : matching.length + ord;
        if (i >= 0 && i < matching.length) out.add(matching[i]);
      }
    }
    return out;
  }

  static int _daysIn(int y, int m) => DateTime.utc(y, m + 1, 0).day;

  /// A BYMONTHDAY value as a day of [m]: negative counts back from the end.
  static int _monthDay(int y, int m, int n) =>
      n > 0 ? n : _daysIn(y, m) + n + 1;
}

class _Until {
  const _Until(this.at, {this.utc = false, this.date = false});

  /// An instant when [utc], otherwise a reading.
  final DateTime at;
  final bool utc;
  final bool date;

  static _Until? parse(String raw) {
    final d = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(raw);
    if (d != null) {
      return _Until(
        DateTime.utc(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!)),
        date: true,
      );
    }
    final t = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$')
        .firstMatch(raw);
    if (t == null) return null;
    return _Until(
      DateTime.utc(int.parse(t[1]!), int.parse(t[2]!), int.parse(t[3]!),
          int.parse(t[4]!), int.parse(t[5]!), int.parse(t[6]!)),
      utc: t[7] == 'Z',
    );
  }
}
