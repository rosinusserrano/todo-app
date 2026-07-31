// The calendar, and everything wrapped around the three grids: the header with
// the mode switch and the navigation, and the calendar filter.
//
// This is the only view that takes over the *whole* window rather than the
// content area - it has its own header, and on desktop it grows the window to
// fit (see main.dart). A week grid inside a 340px widget gives each day 43
// pixels, which is not enough to read a title, let alone drag out a span.
//
// Scope and filter are two different questions and are answered separately:
// "this workspace or all of them" is the scope, and the tick list underneath is
// for hiding an individual calendar you do not want to look at today. Hiding is
// remembered; the scope is remembered too, but the two do not interact - see
// AppState.visibleCalendars.

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../sync/models.dart';
import '../../theme.dart';
import 'time_grid.dart';
import 'year_view.dart';

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.state,
    required this.onClose,
    required this.onOpenEvent,
    required this.onCreate,
    required this.onNewCalendar,
    required this.onEditCalendar,
  });

  final AppState state;
  final VoidCallback onClose;
  final void Function(CalendarEvent) onOpenEvent;
  final void Function(DateTime start, DateTime end) onCreate;
  final VoidCallback onNewCalendar;
  final void Function(Calendar) onEditCalendar;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: _title,
          mode: state.calendarMode,
          scope: state.calendarScope,
          calendars: state.calendars,
          hidden: state.hiddenCalendars,
          nameFor: state.calendarName,
          colorFor: state.calendarColor,
          onClose: onClose,
          onMode: state.setCalendarMode,
          onScope: state.setCalendarScope,
          onStep: state.stepCalendar,
          onToday: () => state.setCalendarAnchor(DateTime.now()),
          onToggleHidden: state.toggleCalendarHidden,
          onNewCalendar: onNewCalendar,
          onEditCalendar: onEditCalendar,
        ),
        Expanded(
          child: state.calendarMode == CalendarViewMode.year
              ? YearView(
                  year: state.calendarAnchor.year,
                  events: state.events,
                  colorFor: state.colorForEvent,
                  onPickDay: (day) async {
                    // Drilling in: the year is for finding the week that has
                    // something in it, and the day view is where you then work.
                    await state.setCalendarAnchor(day);
                    await state.setCalendarMode(CalendarViewMode.day);
                  },
                )
              : TimeGridView(
                  days: _days,
                  events: state.events,
                  colorFor: state.colorForEvent,
                  hasAttachment: (e) =>
                      state.eventsWithAttachments.contains(e.uuid),
                  onOpenEvent: onOpenEvent,
                  onCreate: onCreate,
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.mode,
    required this.scope,
    required this.calendars,
    required this.hidden,
    required this.nameFor,
    required this.colorFor,
    required this.onClose,
    required this.onMode,
    required this.onScope,
    required this.onStep,
    required this.onToday,
    required this.onToggleHidden,
    required this.onNewCalendar,
    required this.onEditCalendar,
  });

  final String title;
  final CalendarViewMode mode;
  final CalendarScope scope;
  final List<Calendar> calendars;
  final Set<String> hidden;
  final String Function(Calendar) nameFor;
  final Color Function(Calendar) colorFor;

  final VoidCallback onClose;
  final void Function(CalendarViewMode) onMode;
  final void Function(CalendarScope) onScope;
  final void Function(int) onStep;
  final VoidCallback onToday;
  final void Function(String) onToggleHidden;
  final VoidCallback onNewCalendar;
  final void Function(Calendar) onEditCalendar;

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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: T.muted),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  scope == s ? Icons.radio_button_checked : Icons.circle_outlined,
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
      ],
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.tune, size: 15, color: T.muted),
      ),
    );
  }
}
