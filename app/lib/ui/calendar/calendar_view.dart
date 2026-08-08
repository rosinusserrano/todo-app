// The calendar, and everything wrapped around the three grids: the header with
// the mode switch and the navigation, and the calendar filter.
//
// This is the only view that takes over the *whole* window rather than the
// content area - it has its own header. It used to also grow the window to
// 920x640 on the way in and put the old size back on the way out, because a
// week grid inside a 340px widget gives each day 43 pixels, which is not enough
// to read a title in, let alone drag out a span. That fixed the grid by moving
// the window: an always-on-top widget parked in a corner jumped to the middle
// of the screen at a size the user never chose.
//
// The window is left alone now and the *views* adapt instead: the week falls
// back to [AgendaView] when the grid does not fit, and the year stacks into as
// many columns as there is room for, down to one. Both decisions come from
// [Layout], not from a platform check - the same 400px window behaves the same
// way whether it is a phone or a shrunken desktop widget.
//
// Scope and filter are two different questions and are answered separately:
// "this workspace or all of them" is the scope, and the tick list underneath is
// for hiding an individual calendar you do not want to look at today. Hiding is
// remembered; the scope is remembered too, but the two do not interact - see
// AppState.visibleCalendars.
//
// **Time-block mode** puts a strip of calendar chips under the header and turns
// a drag into a saved block titled after the picked calendar, with no editor in
// between. It is a *third* thing the chips could have meant - they are not the
// scope and they are not the filter - which is why they are their own strip
// rather than another section of the filter menu: the strip only exists while
// the mode is on, and while it is on it is the answer to "what am I filling in".

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../layout.dart';
import '../../sync/models.dart';
import '../../theme.dart';
import 'agenda_view.dart';
import 'time_grid.dart';
import 'year_view.dart';

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.state,
    required this.onClose,
    required this.onOpenEvent,
    required this.onEventMenu,
    required this.onCreate,
    required this.onNewCalendar,
    required this.onEditCalendar,
    required this.onImportIcs,
    this.onPlanTask,
  });

  final AppState state;
  final VoidCallback onClose;

  /// A plain click: the details card. Editing is named on it rather than being
  /// what a click does, because most clicks on a block are asking a question.
  final void Function(CalendarEvent) onOpenEvent;

  /// Right-click or long-press: the actions menu, at that point.
  final void Function(CalendarEvent, Offset globalPosition) onEventMenu;

  final void Function(DateTime start, DateTime end) onCreate;
  final VoidCallback onNewCalendar;
  final void Function(Calendar) onEditCalendar;

  /// Bring events in from an .ics file another application produced.
  final VoidCallback onImportIcs;

  /// A task was dragged out of the list beside the calendar and dropped on a
  /// block. Only wired up when the two really are side by side - see
  /// [Layout.splitsCalendar] - because there is nothing to drag from otherwise.
  final void Function(CalendarEvent, Task)? onPlanTask;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get _title {
    final a = state.calendarAnchor;
    switch (state.calendarMode) {
      case CalendarViewMode.day:
        return '${a.day} ${_months[a.month - 1]} ${a.year}';
      case CalendarViewMode.week:
        final start = AppState.startOfWeek(a);
        final end = start.add(const Duration(days: 6));
        // A week that straddles two months should say so rather than picking
        // one of them and being wrong for half its columns.
        if (start.month == end.month) {
          return '${_months[start.month - 1]} ${start.year}';
        }
        return '${_months[start.month - 1].substring(0, 3)} – '
            '${_months[end.month - 1].substring(0, 3)} ${end.year}';
      case CalendarViewMode.year:
        return '${a.year}';
    }
  }

  List<DateTime> get _days {
    final a = DateTime(
      state.calendarAnchor.year,
      state.calendarAnchor.month,
      state.calendarAnchor.day,
    );
    if (state.calendarMode == CalendarViewMode.day) return [a];
    final start = AppState.startOfWeek(a);
    return [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
  }

  /// Drill into one day. The year view's tap and the agenda's day header both
  /// mean the same thing - "show me this one properly" - so they land here.
  Future<void> _openDay(DateTime day) async {
    await state.setCalendarAnchor(day);
    await state.setCalendarMode(CalendarViewMode.day);
  }

  /// Turn time-block mode on, off, or onto a different calendar.
  ///
  /// Turning it on has to choose a target, and the same guess the editor makes
  /// for a fresh drag is the right one: the workspace you are in.
  Future<void> _toggleBlocking() async {
    if (state.timeBlocking) {
      await state.setTimeBlockCalendar(null);
      return;
    }
    final visible = state.visibleCalendars;
    if (visible.isEmpty) return;
    final preferred = visible.firstWhere(
      (c) => c.workspaceUuid == state.currentWorkspaceUuid,
      orElse: () => visible.first,
    );
    await state.setTimeBlockCalendar(preferred.uuid);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final block = state.timeBlockCalendar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: _title,
          mode: state.calendarMode,
          compact: !layout.weekGridFits,
          scope: state.calendarScope,
          calendars: state.calendars,
          hidden: state.hiddenCalendars,
          nameFor: state.calendarName,
          colorFor: state.calendarColor,
          blocking: block != null,
          onClose: onClose,
          onMode: state.setCalendarMode,
          onScope: state.setCalendarScope,
          onStep: state.stepCalendar,
          onToday: () => state.setCalendarAnchor(DateTime.now()),
          onToggleHidden: state.toggleCalendarHidden,
          onToggleBlocking: _toggleBlocking,
          onNewCalendar: onNewCalendar,
          onEditCalendar: onEditCalendar,
          onImportIcs: onImportIcs,
        ),
        if (block != null)
          _BlockStrip(
            calendars: state.visibleCalendars,
            selected: block.uuid,
            nameFor: state.calendarName,
            colorFor: state.calendarColor,
            onPick: state.setTimeBlockCalendar,
            onOff: () => state.setTimeBlockCalendar(null),
          ),
        Expanded(child: _grid(layout)),
      ],
    );
  }

  /// The body for the current mode, at the current size.
  ///
  /// Only the *week* changes shape with the width. A day is one column and fits
  /// anywhere, and the year is a wrap that reflows on its own - so this is one
  /// fallback, not a parallel set of narrow views.
  Widget _grid(Layout layout) {
    // The year is for finding the week that has something in it; the day view
    // is where you then work. Both of the drill-downs below say that.
    if (state.calendarMode == CalendarViewMode.year) {
      return YearView(
        year: state.calendarAnchor.year,
        events: state.events,
        colorFor: state.colorForEvent,
        onPickDay: _openDay,
      );
    }

    if (state.calendarMode == CalendarViewMode.week && !layout.weekGridFits) {
      return AgendaView(
        days: _days,
        events: state.events,
        colorFor: state.colorForEvent,
        hasAttachment: (e) => state.eventsWithAttachments.contains(e.uuid),
        taskCountFor: (e) => state.eventTaskCounts[e.uuid] ?? 0,
        onOpenEvent: onOpenEvent,
        onEventMenu: onEventMenu,
        onCreate: onCreate,
        onPickDay: _openDay,
        onPlanTask: onPlanTask,
      );
    }

    final block = state.timeBlockCalendar;
    return TimeGridView(
      days: _days,
      events: state.events,
      colorFor: state.colorForEvent,
      hasAttachment: (e) => state.eventsWithAttachments.contains(e.uuid),
      taskCountFor: (e) => state.eventTaskCounts[e.uuid] ?? 0,
      onOpenEvent: onOpenEvent,
      onEventMenu: onEventMenu,
      onCreate: onCreate,
      onPlanTask: onPlanTask,
      // What the drag is about to become. In block mode the editor never opens,
      // so the draft is the only chance to see what is being saved.
      blockTitle: block == null ? null : state.calendarName(block),
      blockColor: block == null ? null : state.calendarColor(block),
    );
  }
}

/// The calendar chips under the header while time-block mode is on.
///
/// A horizontal strip rather than a dropdown: the whole point of the mode is
/// that retargeting is as cheap as dragging, and a menu would put two presses
/// between "meetings" and "deep work". It lists [AppState.visibleCalendars], so
/// what you can block onto is exactly what you can see - blocking time onto a
/// calendar that is filtered out would produce an event that vanishes.
class _BlockStrip extends StatelessWidget {
  const _BlockStrip({
    required this.calendars,
    required this.selected,
    required this.nameFor,
    required this.colorFor,
    required this.onPick,
    required this.onOff,
  });

  final List<Calendar> calendars;
  final String selected;
  final String Function(Calendar) nameFor;
  final Color Function(Calendar) colorFor;
  final void Function(String) onPick;
  final VoidCallback onOff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 5),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in calendars)
                    _BlockChip(
                      label: nameFor(c),
                      color: colorFor(c),
                      selected: c.uuid == selected,
                      onTap: () => onPick(c.uuid),
                    ),
                ],
              ),
            ),
          ),
          // The way out is on the strip as well as on the header toggle: the
          // strip is what says the mode is on, so it is where you look to end it.
          Tooltip(
            message: 'Leave time-block mode',
            child: InkWell(
              onTap: onOff,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 13, color: T.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  const _BlockChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? Color.lerp(T.bgSolid, color, 0.4) : T.surface,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? T.text : T.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.mode,
    required this.compact,
    required this.scope,
    required this.calendars,
    required this.hidden,
    required this.nameFor,
    required this.colorFor,
    required this.blocking,
    required this.onClose,
    required this.onMode,
    required this.onScope,
    required this.onStep,
    required this.onToday,
    required this.onToggleHidden,
    required this.onToggleBlocking,
    required this.onNewCalendar,
    required this.onEditCalendar,
    required this.onImportIcs,
  });

  final String title;
  final CalendarViewMode mode;

  /// No room for the word "Today" beside everything else, so it becomes its
  /// icon. Dropping the control instead would strand someone who had navigated
  /// three months out with nothing but the ‹ › to get home.
  final bool compact;

  final CalendarScope scope;
  final List<Calendar> calendars;
  final Set<String> hidden;
  final String Function(Calendar) nameFor;
  final Color Function(Calendar) colorFor;

  /// Time-block mode is on. The strip below the header says which calendar;
  /// this only lights the toggle.
  final bool blocking;

  final VoidCallback onClose;
  final void Function(CalendarViewMode) onMode;
  final void Function(CalendarScope) onScope;
  final void Function(int) onStep;
  final VoidCallback onToday;
  final void Function(String) onToggleHidden;
  final VoidCallback onToggleBlocking;
  final VoidCallback onNewCalendar;
  final void Function(Calendar) onEditCalendar;
  final VoidCallback onImportIcs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      child: Row(
        children: [
          Tooltip(
            message: 'Back to tasks (Esc)',
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.arrow_back_rounded, size: 14, color: T.muted),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _IconBtn(
            icon: Icons.chevron_left,
            tooltip: 'Previous',
            onTap: () => onStep(-1),
          ),
          _IconBtn(
            icon: Icons.chevron_right,
            tooltip: 'Next',
            onTap: () => onStep(1),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: T.text,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (compact)
            _IconBtn(
              icon: Icons.today_outlined,
              tooltip: 'Today',
              onTap: onToday,
            )
          else
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Today', style: TextStyle(fontSize: 11.5)),
            ),
          const Spacer(),
          _IconBtn(
            icon: Icons.bolt,
            tooltip: blocking
                ? 'Time-block mode on – drag to fill the week'
                : 'Time-block mode: drag blocks straight onto a calendar',
            active: blocking,
            onTap: onToggleBlocking,
          ),
          const SizedBox(width: 2),
          _ModeSwitch(mode: mode, onMode: onMode),
          const SizedBox(width: 4),
          _FilterMenu(
            scope: scope,
            calendars: calendars,
            hidden: hidden,
            nameFor: nameFor,
            colorFor: colorFor,
            onScope: onScope,
            onToggleHidden: onToggleHidden,
            onNewCalendar: onNewCalendar,
            onEditCalendar: onEditCalendar,
            onImportIcs: onImportIcs,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// A toggle that is currently on, drawn in the accent. The navigation buttons
  /// leave this alone - they do something rather than being in a state.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: active ? T.accent : T.muted),
        ),
      ),
    );
  }
}

/// D / W / Y. Three letters rather than a dropdown: switching view is the most
/// frequent thing done up here, and a menu would put two taps behind it.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onMode});

  final CalendarViewMode mode;
  final void Function(CalendarViewMode) onMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in CalendarViewMode.values)
            () {
              final selected = m == mode;
              return InkWell(
                onTap: () => onMode(m),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? T.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    m.name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? T.bgSolid : T.muted,
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.scope,
    required this.calendars,
    required this.hidden,
    required this.nameFor,
    required this.colorFor,
    required this.onScope,
    required this.onToggleHidden,
    required this.onNewCalendar,
    required this.onEditCalendar,
    required this.onImportIcs,
  });

  final CalendarScope scope;
  final List<Calendar> calendars;
  final Set<String> hidden;
  final String Function(Calendar) nameFor;
  final Color Function(Calendar) colorFor;
  final void Function(CalendarScope) onScope;
  final void Function(String) onToggleHidden;
  final VoidCallback onNewCalendar;
  final void Function(Calendar) onEditCalendar;
  final VoidCallback onImportIcs;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Calendars',
      color: T.bgSolid,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value is CalendarScope) {
          onScope(value);
        } else if (value == 'new') {
          onNewCalendar();
        } else if (value == 'import') {
          onImportIcs();
        } else if (value is String) {
          onToggleHidden(value);
        }
      },
      itemBuilder: (context) => [
        for (final s in CalendarScope.values)
          PopupMenuItem<Object>(
            value: s,
            height: 34,
            child: Row(
              children: [
                Icon(
                  scope == s
                      ? Icons.radio_button_checked
                      : Icons.circle_outlined,
                  size: 13,
                  color: scope == s ? T.accent : T.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  s == CalendarScope.workspace
                      ? 'This workspace'
                      : 'All workspaces',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        for (final c in calendars)
          PopupMenuItem<Object>(
            value: c.uuid,
            height: 34,
            child: Row(
              children: [
                Icon(
                  hidden.contains(c.uuid)
                      ? Icons.check_box_outline_blank
                      : Icons.check_box,
                  size: 14,
                  color: hidden.contains(c.uuid) ? T.muted : colorFor(c),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nameFor(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                // Only standalone calendars are editable here - a workspace
                // calendar's name and colour belong to the workspace.
                if (!c.isWorkspaceCalendar)
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onEditCalendar(c);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.edit, size: 12, color: T.muted),
                    ),
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'new',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.add, size: 14, color: T.muted),
              SizedBox(width: 8),
              Text('New calendar', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem<Object>(
          value: 'import',
          height: 34,
          child: Row(
            children: [
              Icon(Icons.file_download_outlined, size: 14, color: T.muted),
              SizedBox(width: 8),
              Text('Import .ics…', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.tune, size: 15, color: T.muted),
      ),
    );
  }
}
