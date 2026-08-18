// Quick add: blocks placed but not yet written.
//
// The mode exists so a week can be laid out in one pass - tap, tap, tap, look
// at the shape, adjust, done - which means the taps deliberately do *not* hit
// the database. That is the whole risk in one sentence: anything held outside
// the store can be lost by leaving in a way nobody thought about.
//
// So what is pinned here is the commit rule, from every direction the mode can
// end: the bolt going off, the view changing, the calendar closing. There is
// one rule and it is "everything placed gets written", because the alternative
// - some exits commit and some discard - is the kind of thing a user only
// discovers by losing an afternoon's planning.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    await state.refreshCalendars();
    return state;
  }

  /// Quick add on, targeting the current workspace's calendar.
  Future<AppState> blocking() async {
    final s = await freshState();
    final target = s.visibleCalendars.first;
    await s.setTimeBlockCalendar(target.uuid);
    expect(s.timeBlocking, isTrue);
    return s;
  }

  // Today, because `events` is the *visible* window - the week around the
  // calendar's anchor. A fixed date drifts out of that window and the
  // assertions below then pass or fail depending on when the suite is run.
  final today = DateTime.now();
  final at9 = DateTime(today.year, today.month, today.day, 9);
  final at11 = DateTime(today.year, today.month, today.day, 11);

  test('a placed block is not written yet', () async {
    final s = await blocking();
    s.placePendingBlock(at9);

    expect(s.pendingBlocks, hasLength(1));
    // An hour is the unit people block time out in.
    expect(
      s.pendingBlocks.single.end.difference(s.pendingBlocks.single.start),
      AppState.pendingBlockLength,
    );

    await s.refreshEvents();
    expect(s.events, isEmpty, reason: 'nothing reaches the database yet');
  });

  test('turning the mode off writes everything placed', () async {
    final s = await blocking();
    s.placePendingBlock(at9);
    s.placePendingBlock(at11);

    await s.commitPendingBlocks();
    await s.refreshEvents();

    expect(s.pendingBlocks, isEmpty);
    expect(s.events, hasLength(2));
    // Titled after the calendar being filled in - that is what the blocks are
    // for, and it is what the dragged version of this mode already does.
    final target = s.visibleCalendars.first;
    expect(s.events.map((e) => e.title).toSet(), {s.calendarName(target)});
  });

  test('switching the target off from the strip writes what was placed',
      () async {
    // The strip's "Off" is a *second* way out of the mode, beside the bolt, and
    // it used to set the target directly instead of going through the commit.
    // The blocks then outlived the mode with nowhere to belong, and the
    // calendar closing found no target and discarded them - an afternoon's
    // planning lost by reaching for the wrong control. The rule now lives in
    // setTimeBlockCalendar, so no caller can take a different path.
    final s = await blocking();
    s.placePendingBlock(at9);
    s.placePendingBlock(at11);

    await s.setTimeBlockCalendar(null);
    await s.refreshEvents();

    expect(s.timeBlocking, isFalse);
    expect(s.pendingBlocks, isEmpty);
    expect(s.events, hasLength(2), reason: 'placed blocks must survive the exit');
  });

  test('moving the target writes the blocks to the calendar they were laid on',
      () async {
    // Switching mid-mode is the other half of the same hole: committing after
    // the target moved would file an afternoon planned on one calendar under
    // another one's name.
    final s = await freshState();
    // Both calendars have to stay visible, or the target resolves to null and
    // the commit correctly drops the blocks instead - a different test.
    await s.saveWorkspace(name: 'Workout', color: '#7ee3a1');
    await s.setCalendarScope(CalendarScope.all);
    await s.refreshCalendars();

    final first = s.visibleCalendars.first;
    final second = s.visibleCalendars.firstWhere((c) => c.uuid != first.uuid);
    await s.setTimeBlockCalendar(first.uuid);

    s.placePendingBlock(at9);
    await s.setTimeBlockCalendar(second.uuid);
    await s.refreshEvents();

    expect(s.events, hasLength(1));
    expect(s.events.single.calendarUuid, first.uuid);
    expect(s.events.single.title, s.calendarName(first));
  });

  test('changing the view writes what was placed', () async {
    final s = await blocking();
    s.placePendingBlock(at9);

    // Tapping D/W/Y, not swiping. The commit used to live in the calendar
    // view's swipe handler, so a *swipe* to another mode wrote the blocks and
    // a *tap* on the same control did not - and the swipe now moves through
    // time instead, which would have left no committing path at all. It lives
    // on AppState.setCalendarMode now, where no caller can miss it.
    await s.setCalendarMode(CalendarViewMode.year);

    expect(s.pendingBlocks, isEmpty);
    await s.setCalendarMode(CalendarViewMode.week);
    expect(s.events, hasLength(1));
  });

  test('moving through time keeps them pending', () async {
    final s = await blocking();
    s.placePendingBlock(at9);

    // Looking at next week is not leaving the sitting: the mode is still on
    // and the target has not changed, so there is nothing to resolve. Coming
    // back has to find them exactly where they were laid.
    await s.stepCalendar(1);
    await s.stepCalendar(-1);

    expect(s.pendingBlocks, hasLength(1));
    expect(s.pendingBlocks.single.start, at9);
    await s.refreshEvents();
    expect(s.events, isEmpty);
  });

  test('turning the mode on commits nothing', () async {
    // Nothing can be pending with the mode off, so the commit on the way in is
    // a no-op rather than a surprise write.
    final s = await freshState();
    await s.setTimeBlockCalendar(s.visibleCalendars.first.uuid);
    await s.refreshEvents();
    expect(s.events, isEmpty);
  });

  test('committing twice does not write them twice', () async {
    // Every exit path calls this, and more than one can fire on the way out -
    // switching mode and then closing the calendar, say.
    final s = await blocking();
    s.placePendingBlock(at9);

    await s.commitPendingBlocks();
    await s.commitPendingBlocks();
    await s.refreshEvents();

    expect(s.events, hasLength(1));
  });

  test('committing nothing is a no-op', () async {
    final s = await blocking();
    await s.commitPendingBlocks();
    await s.refreshEvents();
    expect(s.events, isEmpty);
  });

  test('a block can be moved and stretched before it is written', () async {
    final s = await blocking();
    s.placePendingBlock(at9);

    // Dragged an hour later and stretched to two.
    s.adjustPendingBlock(0, at11, at11.add(const Duration(hours: 2)));
    await s.commitPendingBlocks();
    await s.refreshEvents();

    final written = s.events.single;
    expect(written.start, at11);
    expect(written.end, at11.add(const Duration(hours: 2)));
  });

  test('a block dragged inside out is refused rather than inverted', () async {
    final s = await blocking();
    s.placePendingBlock(at11);
    s.adjustPendingBlock(0, at11, at9);

    // Left as it was: an event whose end precedes its start would sort and
    // render as nonsense everywhere downstream.
    expect(s.pendingBlocks.single.end.isAfter(s.pendingBlocks.single.start),
        isTrue);
  });

  test('a block can be taken back before it is written', () async {
    final s = await blocking();
    s.placePendingBlock(at9);
    s.placePendingBlock(at11);
    s.removePendingBlock(0);

    await s.commitPendingBlocks();
    await s.refreshEvents();

    expect(s.events.single.start, at11);
  });

  test('losing the target drops the blocks rather than looping', () async {
    // The calendar can go away underneath the mode - unticked, scope narrowed,
    // workspace deleted. There is then nowhere honest to write them.
    //
    // Simulated by hiding the calendar, which is what actually makes
    // [AppState.timeBlockCalendar] resolve to null: the setting still names it
    // and it is no longer among the visible ones. Turning the mode *off*
    // through the setter is a different thing entirely and commits - see the
    // strip tests above.
    final s = await blocking();
    s.placePendingBlock(at9);
    await s.toggleCalendarHidden(s.visibleCalendars.first.uuid);
    expect(s.timeBlocking, isFalse, reason: 'the target is gone');

    await s.commitPendingBlocks();
    await s.refreshEvents();

    expect(s.pendingBlocks, isEmpty, reason: 'cleared, not retried forever');
    expect(s.events, isEmpty);
  });
}
