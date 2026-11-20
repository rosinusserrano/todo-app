// The timer: "1h for checking mails", counted down while you do something
// else, and the app coming back to tell you when it is up (Marco,
// 2026-11-20). Design in ROADMAP.md *The timer*.
//
// This file is the pure half - the model, what a typed line means, and how a
// duration is printed - so `test/countdown_test.dart` needs no widgets.
//
// Things about the shape:
//
//   - **One timer, device-local.** It is about this sitting at this machine,
//     like the window modes, so it lives in `settings` as JSON and never
//     syncs. One, because "the timer" is what was asked for and a second one
//     would need somewhere to be told apart.
//   - **It stores an instant, not a count.** A running timer is `endsAt`; a
//     paused one is `left`. Exactly one of the two is set. An instant is what
//     survives the app being closed and reopened, and what the OS is handed
//     on a phone - a count would need something to keep counting it.
//   - **Being up is a state, not an event.** A timer whose `endsAt` has
//     passed stays until it is dismissed, so a launch after it ran out still
//     says so instead of the timer having quietly vanished.

/// One timer.
class Countdown {
  const Countdown({
    required this.label,
    required this.total,
    this.endsAt,
    this.left,
  }) : assert((endsAt == null) != (left == null));

  /// Starts [duration] from [now].
  factory Countdown.start(Duration duration, String label, DateTime now) =>
      Countdown(label: label, total: duration, endsAt: now.add(duration));

  /// What it is for - may be empty.
  final String label;

  /// How long it was set for, plus anything added. What the progress bar is
  /// a fraction of.
  final Duration total;

  /// When it runs out, while running.
  final DateTime? endsAt;

  /// What was left when it was paused.
  final Duration? left;

  bool get paused => left != null;

  Duration remaining(DateTime now) {
    if (left != null) return left!;
    final d = endsAt!.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  bool isUp(DateTime now) => !paused && !now.isBefore(endsAt!);

  /// 0 at the start, 1 when it is up.
  double progress(DateTime now) {
    if (total <= Duration.zero) return 1;
    final done = 1 - remaining(now).inMilliseconds / total.inMilliseconds;
    return done.clamp(0.0, 1.0);
  }

  Countdown pause(DateTime now) => paused || isUp(now)
      ? this
      : Countdown(label: label, total: total, left: remaining(now));

  Countdown resume(DateTime now) => !paused
      ? this
      : Countdown(label: label, total: total, endsAt: now.add(left!));

  /// [by] more. On a timer that is up it counts from now - "five more
  /// minutes" means from when you said it, not from when it rang.
  Countdown extend(Duration by, DateTime now) {
    if (paused) {
      return Countdown(label: label, total: total + by, left: left! + by);
    }
    if (isUp(now)) {
      return Countdown(label: label, total: by, endsAt: now.add(by));
    }
    return Countdown(label: label, total: total + by, endsAt: endsAt!.add(by));
  }

  Map<String, Object?> toJson() => {
    'label': label,
    'total': total.inMilliseconds,
    if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
    if (left != null) 'left': left!.inMilliseconds,
  };

  /// Null for anything that is not a timer this build wrote - a setting from
  /// a newer build, or garbage, is no timer rather than a crash at launch.
  static Countdown? fromJson(Object? json) {
    if (json is! Map) return null;
    final total = json['total'];
    final label = json['label'];
    final ends = DateTime.tryParse('${json['endsAt'] ?? ''}');
    final left = json['left'];
    if (total is! int || label is! String) return null;
    if ((ends == null) == (left is! int)) return null;
    return Countdown(
      label: label,
      total: Duration(milliseconds: total),
      endsAt: ends?.toLocal(),
      left: left is int ? Duration(milliseconds: left) : null,
    );
  }
}

/// The longest timer: a day. Past that it is a reminder.
const kMaxCountdown = Duration(hours: 24);

// English and German, longest first so "min" is not read as "m" + "in".
const _hours = r'hours|hour|hrs|hr|stunden|stunde|std|h';
const _minutes = r'minutes|minute|minuten|mins|min|m';
const _seconds = r'seconds|second|sekunden|sekunde|secs|sec|sek|s';

final _part = RegExp(
  '(?<![\\p{L}\\d.,])(\\d+(?:[.,]\\d+)?)\\s*($_hours|$_minutes|$_seconds)'
  '(?!\\p{L})',
  caseSensitive: false,
  unicode: true,
);

bool _isHours(String unit) =>
    RegExp('^($_hours)\$', caseSensitive: false).hasMatch(unit);

bool _isMinutes(String unit) =>
    RegExp('^($_minutes)\$', caseSensitive: false).hasMatch(unit);

final _clock = RegExp(r'(?<![\d:])(\d{1,2}):([0-5]\d)(?![\d:])');
final _leadingNumber = RegExp(r'^(\d{1,3})(?![\d.,:\p{L}])', unicode: true);

/// What a typed line asks for: a duration and what it is for. "1h for
/// checking mails", "checking mails 1h30", "25", "1:30 call", "90 min",
/// "1 Stunde 20 Minuten Mails". Null when there is no duration in it, or it
/// is nothing or longer than [kMaxCountdown].
///
/// Read like the add card's keywords, tuned to not guess: a duration needs a
/// unit, except a number that opens the line ("25 call" is 25 minutes) or an
/// `h:mm`. Several parts next to each other add up ("1h 30m", "1h30"), and
/// the "for" that joins a duration to its label goes with it.
({Duration duration, String label})? parseCountdown(String input) {
  final text = input.trim();
  Duration? duration;
  var start = 0, end = 0;

  final first = _part.firstMatch(text);
  if (first != null) {
    duration = Duration.zero;
    start = first.start;
    end = first.start;
    // The run of parts from the first one on, with only spaces between.
    while (true) {
      final m = _part.matchAsPrefix(text, _skipSpaces(text, end));
      if (m == null) break;
      duration = duration! + _partDuration(m.group(1)!, m.group(2)!);
      end = m.end;
      // "1h30": a bare number straight after hours is minutes.
      if (_isHours(m.group(2)!)) {
        final bare = RegExp(
          r'(\d{1,2})(?![\d\p{L}])',
          unicode: true,
        ).matchAsPrefix(text, end);
        if (bare != null) {
          duration = duration + Duration(minutes: int.parse(bare.group(1)!));
          end = bare.end;
        }
      }
    }
  } else if (_clock.firstMatch(text) case final m?) {
    duration = Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
    );
    start = m.start;
    end = m.end;
  } else if (_leadingNumber.firstMatch(text) case final m?) {
    duration = Duration(minutes: int.parse(m.group(1)!));
    start = m.start;
    end = m.end;
  }

  if (duration == null || duration <= Duration.zero) return null;
  if (duration > kMaxCountdown) return null;

  var before = text.substring(0, start).trimRight();
  var after = text.substring(end).trimLeft();
  // "1h for mails" / "mails for 1h" - the joining word belongs to the time.
  final joinAfter = RegExp(r'^(for|für)\s+', caseSensitive: false);
  final joinBefore = RegExp(r'\s*\b(for|für)$', caseSensitive: false);
  if (joinAfter.hasMatch(after)) {
    after = after.replaceFirst(joinAfter, '');
  } else if (joinBefore.hasMatch(before)) {
    before = before.replaceFirst(joinBefore, '');
  }
  final label = [
    before,
    after,
  ].where((s) => s.isNotEmpty).join(' ').replaceAll(RegExp(r'\s+'), ' ');
  return (duration: duration, label: label.trim());
}

int _skipSpaces(String text, int at) {
  while (at < text.length && text[at] == ' ') {
    at++;
  }
  return at;
}

Duration _partDuration(String number, String unit) {
  final n = double.parse(number.replaceAll(',', '.'));
  final ms = _isHours(unit)
      ? n * Duration.millisecondsPerHour
      : _isMinutes(unit)
      ? n * Duration.millisecondsPerMinute
      : n * Duration.millisecondsPerSecond;
  return Duration(milliseconds: ms.round());
}

/// The big readout: "59:12", "1:05:09".
String formatClock(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// The dock's: "1h05", "42m", "45s". Rounded up, so it never says 0m while
/// something is left.
String formatShort(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  if (s < 60) return '${s}s';
  final m = (s / 60).ceil();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}';
}

/// What a parsed line will set, in words: "1 h 30 min".
String describeDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return [if (h > 0) '$h h', if (m > 0) '$m min', if (s > 0) '$s s'].join(' ');
}
