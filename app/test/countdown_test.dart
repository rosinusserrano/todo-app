// The timer's pure half: what a typed line means, and the model's states.

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/countdown.dart';

void main() {
  group('parseCountdown', () {
    void reads(String input, Duration d, String label) {
      final r = parseCountdown(input);
      expect(r, isNotNull, reason: input);
      expect(r!.duration, d, reason: input);
      expect(r.label, label, reason: input);
    }

    test('a duration and what it is for, either way round', () {
      reads(
        '1h for checking mails',
        const Duration(hours: 1),
        'checking mails',
      );
      reads(
        'checking mails for 1h',
        const Duration(hours: 1),
        'checking mails',
      );
      reads(
        'checking mails 45m',
        const Duration(minutes: 45),
        'checking mails',
      );
      reads('90 min', const Duration(minutes: 90), '');
      reads('tea 3 minutes', const Duration(minutes: 3), 'tea');
      reads('30s plank', const Duration(seconds: 30), 'plank');
    });

    test('parts add up', () {
      reads('1h30 call', const Duration(minutes: 90), 'call');
      reads('1h 30m call', const Duration(minutes: 90), 'call');
      reads('1 hour 15 minutes', const Duration(minutes: 75), '');
      reads('1.5h deep work', const Duration(minutes: 90), 'deep work');
      reads('1,5 Stunden Mails', const Duration(minutes: 90), 'Mails');
      reads('Mails für 20 Minuten', const Duration(minutes: 20), 'Mails');
    });

    test('without a unit only a leading number or h:mm counts', () {
      reads('25', const Duration(minutes: 25), '');
      reads('25 focus', const Duration(minutes: 25), 'focus');
      reads('1:30 call', const Duration(minutes: 90), 'call');
      expect(parseCountdown('answer 3 mails'), isNull);
      expect(parseCountdown('read mails'), isNull);
      expect(parseCountdown(''), isNull);
    });

    test('a unit inside a word is not one', () {
      reads('5 mails 10m', const Duration(minutes: 10), '5 mails');
      reads('check 2 mails 10m', const Duration(minutes: 10), 'check 2 mails');
      expect(parseCountdown('mp3s'), isNull);
    });

    test('nothing, and more than a day, are not timers', () {
      expect(parseCountdown('0m'), isNull);
      expect(parseCountdown('25h'), isNull);
    });
  });

  group('Countdown', () {
    final t0 = DateTime(2026, 11, 20, 14);

    test('runs, pauses, resumes and is up', () {
      var c = Countdown.start(const Duration(minutes: 10), 'tea', t0);
      final t3 = t0.add(const Duration(minutes: 3));
      expect(c.remaining(t3), const Duration(minutes: 7));
      expect(c.progress(t3), closeTo(0.3, 1e-9));

      c = c.pause(t3);
      expect(c.paused, isTrue);
      // Time passing while paused changes nothing.
      expect(
        c.remaining(t0.add(const Duration(hours: 5))),
        const Duration(minutes: 7),
      );

      final t20 = t0.add(const Duration(minutes: 20));
      c = c.resume(t20);
      expect(c.endsAt, t20.add(const Duration(minutes: 7)));
      expect(c.isUp(t20.add(const Duration(minutes: 7))), isTrue);
      expect(c.remaining(t20.add(const Duration(hours: 1))), Duration.zero);
    });

    test('more time counts from now once it is up', () {
      final c = Countdown.start(const Duration(minutes: 10), '', t0);
      final late = t0.add(const Duration(minutes: 30));
      final more = c.extend(const Duration(minutes: 5), late);
      expect(more.endsAt, late.add(const Duration(minutes: 5)));
      final running = c.extend(const Duration(minutes: 5), t0);
      expect(running.endsAt, t0.add(const Duration(minutes: 15)));
      expect(running.total, const Duration(minutes: 15));
    });

    test('round-trips through JSON, and refuses what it did not write', () {
      final c = Countdown.start(const Duration(minutes: 10), 'tea', t0);
      final back = Countdown.fromJson(c.toJson())!;
      expect(back.endsAt, c.endsAt);
      expect(back.label, 'tea');
      final p = Countdown.fromJson(c.pause(t0).toJson())!;
      expect(p.left, const Duration(minutes: 10));
      expect(Countdown.fromJson({'label': 'x'}), isNull);
      expect(Countdown.fromJson('nonsense'), isNull);
    });
  });

  test('formats', () {
    expect(formatClock(const Duration(minutes: 59, seconds: 12)), '59:12');
    expect(
      formatClock(const Duration(hours: 1, minutes: 5, seconds: 9)),
      '1:05:09',
    );
    expect(formatShort(const Duration(seconds: 45)), '45s');
    expect(formatShort(const Duration(minutes: 41, seconds: 1)), '42m');
    expect(formatShort(const Duration(minutes: 65)), '1h05');
    expect(describeDuration(const Duration(minutes: 90)), '1 h 30 min');
  });
}
