import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/task_keywords.dart';

Workspace ws(String uuid, String name) => Workspace(
  uuid: uuid,
  name: name,
  color: '#6F86CC',
  sortOrder: 0,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  // A Thursday, mid-morning.
  final now = DateTime(2026, 10, 15, 10, 30);
  final spaces = [
    ws('here', 'Tasks'),
    ws('work', 'Work'),
    ws('apps', 'Meine Apps'),
    ws('a', 'Apps'),
  ];

  KeywordParse p(String text) =>
      parseTaskKeywords(text, now: now, workspaces: spaces, hereUuid: 'here');

  group('workspaces', () {
    test('a name moves the task and leaves the title', () {
      final r = p('fix the sync bug Work');
      expect(r.title, 'fix the sync bug');
      expect(r.workspaceUuid, 'work');
    });

    test('case-insensitive, whole words, # allowed', () {
      expect(p('ring Anna work').workspaceUuid, 'work');
      expect(p('ring Anna #work').title, 'ring Anna');
      expect(p('homework due').workspaceUuid, isNull);
      expect(p('workshop notes').workspaceUuid, isNull);
    });

    test('the longest name wins', () {
      final r = p('ship it Meine Apps');
      expect(r.workspaceUuid, 'apps');
      expect(r.title, 'ship it');
    });

    test('a leading name with a colon leaves no colon', () {
      expect(p('Work: ring Anna').title, 'ring Anna');
    });

    test('the current workspace is not a keyword', () {
      final r = p('Tasks to sort');
      expect(r.workspaceUuid, isNull);
      expect(r.title, 'Tasks to sort');
    });

    test('a name on its own is the title', () {
      final r = p('Work');
      expect(r.workspaceUuid, isNull);
      expect(r.title, 'Work');
    });

    test('switched off, nothing is read', () {
      final r = parseTaskKeywords(
        'report Work',
        now: now,
        workspaces: spaces,
        matchWorkspaces: false,
      );
      expect(r.workspaceUuid, isNull);
      expect(r.title, 'report Work');
    });
  });

  group('times', () {
    test('a time alone is today', () {
      final r = p('call the bank 14:30');
      expect(r.title, 'call the bank');
      expect(r.remindAt, DateTime(2026, 10, 15, 14, 30));
    });

    test('a time that has passed today is tomorrow', () {
      expect(p('stretch 8:00').remindAt, DateTime(2026, 10, 16, 8, 0));
    });

    test('am/pm, Uhr and a leading at/um', () {
      expect(p('call at 3pm').remindAt, DateTime(2026, 10, 15, 15));
      expect(p('call at 3pm').title, 'call');
      expect(p('anrufen um 16 Uhr').remindAt, DateTime(2026, 10, 15, 16));
      expect(p('anrufen um 16 Uhr').title, 'anrufen');
      expect(p('lunch 12am').remindAt, DateTime(2026, 10, 16, 0));
    });

    test('bare numbers are not times', () {
      for (final t in ['buy 2 eggs', 'read chapter 12', 'at 5 we leave']) {
        final r = p(t);
        expect(r.remindAt, isNull, reason: t);
        expect(r.title, t);
      }
    });

    test('nonsense times are left alone', () {
      expect(p('score 25:00').remindAt, isNull);
      expect(p('ratio 3:75').remindAt, isNull);
    });

    test('relative minutes and hours', () {
      expect(p('tea in 10 min').remindAt, DateTime(2026, 10, 15, 10, 40));
      expect(p('tea in 2h').remindAt, DateTime(2026, 10, 15, 12, 30));
      expect(p('tea in 2h').title, 'tea');
    });
  });

  group('dates', () {
    test('date and time together', () {
      final r = p('dentist tomorrow 9:15');
      expect(r.title, 'dentist');
      expect(r.remindAt, DateTime(2026, 10, 16, 9, 15));
    });

    test('a date alone is 09:00', () {
      expect(p('dentist tomorrow').remindAt, DateTime(2026, 10, 16, 9));
    });

    test('today alone after nine is the next whole hour', () {
      expect(p('water plants today').remindAt, DateTime(2026, 10, 15, 11));
    });

    test('weekdays, English and German', () {
      expect(p('bins on Monday').remindAt, DateTime(2026, 10, 19, 9));
      expect(p('bins on Monday').title, 'bins');
      expect(p('Müll am Freitag 18:00').remindAt, DateTime(2026, 10, 16, 18));
      expect(p('Müll am Freitag 18:00').title, 'Müll');
      // Thursday is today; "next Thursday" is a week away.
      expect(p('meet Thursday 17:00').remindAt, DateTime(2026, 10, 15, 17));
      expect(p('meet next Thursday').remindAt, DateTime(2026, 10, 22, 9));
    });

    test('short weekday words are not weekdays', () {
      expect(p('sun cream').remindAt, isNull);
      expect(p('sat down with Ben').remindAt, isNull);
    });

    test('day-first numeric dates', () {
      expect(p('rent 1.11. 10:00').remindAt, DateTime(2026, 11, 1, 10));
      expect(p('rent 1.11. 10:00').title, 'rent');
      expect(p('passport 03.02.2027').remindAt, DateTime(2027, 2, 3, 9));
      expect(p('party 24/12').remindAt, DateTime(2026, 12, 24, 9));
      expect(
        p('flight 2026-12-01 06:40').remindAt,
        DateTime(2026, 12, 1, 6, 40),
      );
    });

    test('a date already past this year is next year', () {
      expect(p('taxes 1.3.').remindAt, DateTime(2027, 3, 1, 9));
    });

    test('decimals and fractions are not dates', () {
      expect(p('version 2.5 release').remindAt, isNull);
      expect(p('add 1/2 cup sugar').remindAt, isNull);
      expect(p('31.02. typo').remindAt, isNull);
    });

    test('month names', () {
      expect(p('gift 3 Dec').remindAt, DateTime(2026, 12, 3, 9));
      expect(p('gift Dec 3rd').remindAt, DateTime(2026, 12, 3, 9));
      expect(p('Geschenk 3. Dezember').title, 'Geschenk');
    });

    test('tonight is a date and a time', () {
      final r = p('call mum tonight');
      expect(r.title, 'call mum');
      expect(r.remindAt, DateTime(2026, 10, 15, 18));
    });

    test('in N days', () {
      expect(p('follow up in 3 days').remindAt, DateTime(2026, 10, 18, 9));
    });

    test('only the first date and the first time are read', () {
      final r = p('move 14:00 meeting to 15:00');
      expect(r.remindAt, DateTime(2026, 10, 15, 14));
      expect(r.title, 'move meeting to 15:00');
    });
  });

  test('everything at once', () {
    final r = p('Meine Apps: release notes Friday 9:30');
    expect(r.title, 'release notes');
    expect(r.workspaceUuid, 'apps');
    expect(r.remindAt, DateTime(2026, 10, 16, 9, 30));
    expect(r.spans.length, 3);
  });

  test('a title made only of keywords is kept whole', () {
    final r = p('tomorrow 9:00');
    expect(r.title, 'tomorrow 9:00');
    expect(r.remindAt, isNull);
    expect(r.spans, isEmpty);
  });
}
