// Reading .ics files other applications hand us.
//
// The samples here are shaped like what actually arrives - Google Calendar
// invites, booking confirmations, a Deutsche Bahn ticket - rather than like the
// examples in RFC 5545, because the failure modes worth covering are the ones
// real producers cause: folded lines, escaped commas, and three different ways
// of writing a timestamp.

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/ics.dart';

String _wrap(String body) => 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Test//EN\r\n'
    '$body\r\n'
    'END:VCALENDAR\r\n';

void main() {
  test('a plain invite comes across whole', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'UID:abc-123\r\n'
        'SUMMARY:Dentist\r\n'
        'LOCATION:Hauptstrasse 1\r\n'
        'DTSTART:20260814T093000Z\r\n'
        'DTEND:20260814T101500Z\r\n'
        'END:VEVENT'));

    final e = events.single;
    expect(e.summary, 'Dentist');
    expect(e.location, 'Hauptstrasse 1');
    expect(e.uid, 'abc-123');
    expect(e.duration, const Duration(minutes: 45));
    // A Z stamp is an instant, so it lands wherever local time puts it.
    expect(e.start.toUtc(), DateTime.utc(2026, 8, 14, 9, 30));
    expect(e.allDay, isFalse);
  });

  test('folded lines are rejoined before anything is parsed', () {
    // Producers fold at 75 octets. Without unfolding, the description is
    // truncated *and* the remainder becomes a junk property.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Quarterly review\r\n'
        'DESCRIPTION:This description is long enough that a well-behaved \r\n'
        ' producer will fold it across two lines\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'DTEND:20260814T100000Z\r\n'
        'END:VEVENT'));

    expect(
      events.single.description,
      'This description is long enough that a well-behaved producer will fold '
      'it across two lines',
    );
  });

  test('escaped punctuation and newlines are unescaped', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        r'SUMMARY:Lunch with Ana\, Bea and Cy' '\r\n'
        r'DESCRIPTION:Line one\nLine two\; and more' '\r\n'
        'DTSTART:20260814T120000Z\r\n'
        'END:VEVENT'));

    final e = events.single;
    expect(e.summary, 'Lunch with Ana, Bea and Cy');
    expect(e.description, 'Line one\nLine two; and more');
  });

  test('an all-day event is a date, and its end is exclusive', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Public holiday\r\n'
        'DTSTART;VALUE=DATE:20260814\r\n'
        'DTEND;VALUE=DATE:20260815\r\n'
        'END:VEVENT'));

    final e = events.single;
    expect(e.allDay, isTrue);
    expect(e.start, DateTime(2026, 8, 14));
    expect(e.end, DateTime(2026, 8, 15));
  });

  test('a floating time keeps its reading rather than shifting', () {
    // A train ticket says 09:30 and means 09:30 where you are standing.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:ICE 691\r\n'
        'DTSTART:20260814T093000\r\n'
        'DTEND:20260814T123000\r\n'
        'END:VEVENT'));

    expect(events.single.start, DateTime(2026, 8, 14, 9, 30));
    expect(events.single.start.hour, 9);
  });

  test('a quoted TZID does not split the line in the wrong place', () {
    // `DTSTART;TZID="Europe/Berlin":2026...` has two colons, and taking the
    // first one leaves the value as `"Europe/Berlin":20260814T093000`.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Standup\r\n'
        'DTSTART;TZID="Europe/Berlin":20260814T093000\r\n'
        'DTEND;TZID="Europe/Berlin":20260814T094500\r\n'
        'END:VEVENT'));

    final e = events.single;
    expect(e.start, DateTime(2026, 8, 14, 9, 30));
    expect(e.duration, const Duration(minutes: 15));
  });

  test('DURATION stands in for a missing DTEND', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Focus block\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'DURATION:PT1H30M\r\n'
        'END:VEVENT'));

    expect(events.single.duration, const Duration(hours: 1, minutes: 30));
  });

  test('an event with neither end nor duration still has a length', () {
    // Zero-length is not drawable, so it gets an hour rather than nothing.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Reminder\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'END:VEVENT'));

    expect(events.single.duration, const Duration(hours: 1));
  });

  test('an end before the start is repaired rather than imported', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Backwards\r\n'
        'DTSTART:20260814T100000Z\r\n'
        'DTEND:20260814T090000Z\r\n'
        'END:VEVENT'));

    expect(events.single.end.isAfter(events.single.start), isTrue);
  });

  test('a recurring event is imported once, and flagged', () {
    // The series cannot be stored, so importing the first occurrence and
    // saying so beats guessing at a rule.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Weekly sync\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'DTEND:20260814T093000Z\r\n'
        'RRULE:FREQ=WEEKLY;BYDAY=FR\r\n'
        'END:VEVENT'));

    expect(events.single.recurring, isTrue);
    expect(events.single.summary, 'Weekly sync');
  });

  test('several events come back in order', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:First\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'SUMMARY:Second\r\n'
        'DTSTART:20260815T090000Z\r\n'
        'END:VEVENT'));

    expect(events.map((e) => e.summary), ['First', 'Second']);
  });

  test('one broken event does not cost the others', () {
    // Fed by other applications, so robustness beats strictness.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:No start at all\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\n'
        'SUMMARY:Fine\r\n'
        'DTSTART:20260815T090000Z\r\n'
        'END:VEVENT'));

    expect(events.single.summary, 'Fine');
  });

  test('an alarm block does not become an event', () {
    // VALARM contains its own properties and, crucially, its own TRIGGER -
    // which must not be read as the event's start.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:With a reminder\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'DTEND:20260814T100000Z\r\n'
        'BEGIN:VALARM\r\n'
        'TRIGGER:-PT15M\r\n'
        'ACTION:DISPLAY\r\n'
        'END:VALARM\r\n'
        'END:VEVENT'));

    final e = events.single;
    expect(e.summary, 'With a reminder');
    expect(e.start.toUtc(), DateTime.utc(2026, 8, 14, 9));
    expect(e.duration, const Duration(hours: 1));
  });

  test("a nested alarm's own text never becomes the event's", () {
    // The ordering-dependent version of the bug: this producer emits the alarm
    // *before* the event's own DESCRIPTION, so a parser that flattens nested
    // components imports "Reminder" as the description.
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'SUMMARY:Board meeting\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'BEGIN:VALARM\r\n'
        'ACTION:DISPLAY\r\n'
        'DESCRIPTION:Reminder\r\n'
        'TRIGGER:-PT15M\r\n'
        'END:VALARM\r\n'
        'DESCRIPTION:Agenda attached\r\n'
        'END:VEVENT'));

    expect(events.single.description, 'Agenda attached');
  });

  test('an event with no summary is still importable', () {
    final events = parseIcs(_wrap('BEGIN:VEVENT\r\n'
        'DTSTART:20260814T090000Z\r\n'
        'END:VEVENT'));
    expect(events.single.summary, 'Untitled event');
  });

  test('junk is empty, not an exception', () {
    expect(parseIcs(''), isEmpty);
    expect(parseIcs('not an ics file at all'), isEmpty);
    expect(parseIcs('BEGIN:VEVENT'), isEmpty, reason: 'never closed');
  });

  test('bare LF line endings parse as well as CRLF', () {
    // Plenty of producers, and every hand-edited file, use LF.
    final events = parseIcs(
      'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Unix\n'
      'DTSTART:20260814T090000Z\nEND:VEVENT\nEND:VCALENDAR\n',
    );
    expect(events.single.summary, 'Unix');
  });
}
