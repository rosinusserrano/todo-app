// The hour grid behind the day and week views.
//
// One widget for both: a day is a week with a single column, and forking them
// would mean maintaining two copies of the geometry, the drag handling and the
// overlap packing - the three things here that are actually hard.
//
// Creating by dragging is split by input device on purpose:
//
//   - A **mouse** drag creates. Flutter's default scroll behaviour excludes
//     the mouse from `dragDevices`, so a mouse drag is not competing with the
//     scroll view for the gesture and a plain Listener can own it outright.
//   - A **touch** drag has to scroll - it is the only way to reach the rest of
//     the day - so on a phone creating is long-press-then-drag, which is the
//     gesture every touch calendar uses for the same reason.
//
// Both paths feed the same draft, so there is one code path for what a drag
// actually means and only the way it starts differs.
//
// Both of them also sit *below* the event blocks in the stack rather than
// around them: an ancestor is handed the pointer even when a child took it, so
// creating used to run on top of opening and a click on an event wrote a new
// 15-minute block behind the editor.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';

/// Height of one hour of the grid. Everything vertical is derived from this.
const double kHourHeight = 44;

/// The time-of-day gutter down the left edge.
const double kGutter = 38;

/// What that gutter shrinks to when the columns are tight - "9" instead of
/// "09:00". Seven columns on a phone cannot spare 38px for a label that is the
/// same on every screenful, and this is 16px given back to the days.
const double kGutterCompact = 22;

/// Below this a day column switches to the compact geometry: the narrow gutter
/// above, weekday initials instead of names, and the title alone in a block.
/// A phone week is ~45px per day, which is where every phone calendar sits.
const double kCompactColumn = 70;

/// Drags snap to this. Fifteen minutes is fine enough to place a real meeting
/// and coarse enough that a shaky drag still lands on a round number.
const int kSnapMinutes = 15;

/// Height of the band above the grid that holds multi-day events.
const double kSpanRowHeight = 18;

class TimeGridView extends StatefulWidget {
  const TimeGridView({
    super.key,
    required this.days,
    required this.events,
    required this.colorFor,
    required this.hasAttachment,
    required this.taskCountFor,
    required this.onOpenEvent,
    required this.onCreate,
    this.blockTitle,
    this.blockColor,
  });

  /// The columns, left to right, each at local midnight.
  final List<DateTime> days;

  final List<CalendarEvent> events;
  final Color Function(CalendarEvent) colorFor;
  final bool Function(CalendarEvent) hasAttachment;

  /// How many todos are planned into an event, for the count on its blob. Zero
  /// draws nothing - most blocks have none, and an empty badge on every one of
  /// them would be noise.
  final int Function(CalendarEvent) taskCountFor;

  final void Function(CalendarEvent) onOpenEvent;

  /// A drag finished. The editor opens prefilled with this span - unless time
  /// block mode is on, in which case the caller saves it outright.
  final void Function(DateTime start, DateTime end) onCreate;

  /// What the drag will be saved as in time-block mode, or null when it is off
  /// and the drag only opens the editor. The draft carries them because in that
  /// mode nothing else ever shows what is about to be written.
  final String? blockTitle;
  final Color? blockColor;

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<TimeGridView> {
  // Opens on the working day rather than at midnight, which is eight hours of
  // empty grid nobody wants to scroll past.
  final _scroll = ScrollController(initialScrollOffset: 7 * kHourHeight);

  _Draft? _draft;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Whether the columns are narrow enough for the compact geometry, and so
  /// which gutter the grid drew with. Both are decided once per build from the
  /// measured width and recorded here, because the drag maths runs from a
  /// pointer callback that has no builder context - the same reason the shell
  /// keeps its [Layout]. Nothing notifies off them.
  bool _compact = false;
  double _gutter = kGutter;

  /// Decided against the *roomy* gutter, so the answer cannot depend on itself:
  /// a column that is tight even with 38px to spare is tight.
  bool _isCompact(double width) =>
      (width - kGutter) / widget.days.length < kCompactColumn;

  double get _columnWidth {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    return (width - _gutter) / widget.days.length;
  }

  /// Which column and minute a point in the grid falls on.
  _Draft? _pointToSlot(Offset local, {int? anchorMinutes, int? anchorDay}) {
    final colWidth = _columnWidth;
    if (colWidth <= 0) return null;

    final day = anchorDay ??
        ((local.dx - _gutter) / colWidth).floor().clamp(0, widget.days.length - 1);

    final raw = (local.dy / kHourHeight) * 60;
    final snapped = (raw / kSnapMinutes).round() * kSnapMinutes;
    final minutes = snapped.clamp(0, 24 * 60);

    if (anchorMinutes == null) {
      return _Draft(dayIndex: day, fromMinutes: minutes, toMinutes: minutes);
    }
    return _Draft(
      dayIndex: day,
      fromMinutes: anchorMinutes,
      toMinutes: minutes,
    );
  }

  void _begin(Offset local) {
    final slot = _pointToSlot(local);
    if (slot == null) return;
    setState(() => _draft = slot);
  }

  void _extend(Offset local) {
    final start = _draft;
    if (start == null) return;
    final slot = _pointToSlot(
      local,
      anchorMinutes: start.fromMinutes,
      // Locked to the column the drag started in: a diagonal drag across a week
      // grid otherwise silently retargets the event to another day.
      anchorDay: start.dayIndex,
    );
    if (slot == null) return;
    setState(() => _draft = slot);
  }

  void _commit() {
    final draft = _draft;
    setState(() => _draft = null);
    if (draft == null) return;

    final day = widget.days[draft.dayIndex];
    var from = draft.lowMinutes;
    var to = draft.highMinutes;
    // A click that never moved still means "something here" - give it a
    // default block rather than discarding the gesture.
    if (to - from < kSnapMinutes) to = from + kSnapMinutes;

    widget.onCreate(
      day.add(Duration(minutes: from)),
      day.add(Duration(minutes: to)),
    );
  }

  /// Events that sit inside the hour grid, split per column.
  List<List<CalendarEvent>> get _timedByDay {
    final out = [for (var i = 0; i < widget.days.length; i++) <CalendarEvent>[]];
    for (final e in widget.events) {
      if (e.spansDays) continue;
      for (var i = 0; i < widget.days.length; i++) {
        final day = widget.days[i];
        final next = day.add(const Duration(days: 1));
        if (!e.start.isBefore(day) && e.start.isBefore(next)) {
          out[i].add(e);
          break;
        }
      }
    }
    return out;
  }

  /// Events crossing a day boundary, which are drawn in the band on top.
  List<CalendarEvent> get _spanning =>
      [for (final e in widget.events) if (e.spansDays) e];

  @override
  Widget build(BuildContext context) {
    final spanning = _spanning;

    return LayoutBuilder(
      builder: (context, constraints) {
        _compact = _isCompact(constraints.maxWidth);
        _gutter = _compact ? kGutterCompact : kGutter;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayHeaderRow(
              days: widget.days,
              gutter: _gutter,
              compact: _compact,
            ),
            if (spanning.isNotEmpty)
              _SpanBand(
                days: widget.days,
                events: spanning,
                colorFor: widget.colorFor,
                onOpen: widget.onOpenEvent,
                gutter: _gutter,
                compact: _compact,
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * kHourHeight,
                  child: _GridBody(
                    days: widget.days,
                    timedByDay: _timedByDay,
                    draft: _draft,
                    colorFor: widget.colorFor,
                    hasAttachment: widget.hasAttachment,
                    taskCountFor: widget.taskCountFor,
                    onOpenEvent: widget.onOpenEvent,
                    onDragBegin: _begin,
                    onDragExtend: _extend,
                    onDragCommit: _commit,
                    blockTitle: widget.blockTitle,
                    blockColor: widget.blockColor,
                    gutter: _gutter,
                    compact: _compact,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// An in-progress drag. [fromMinutes] is where it started, which may be *after*
/// where it is now - dragging upwards is a normal way to pick a span.
class _Draft {
  const _Draft({
    required this.dayIndex,
    required this.fromMinutes,
    required this.toMinutes,
  });

  final int dayIndex;
  final int fromMinutes;
  final int toMinutes;

  int get lowMinutes => fromMinutes < toMinutes ? fromMinutes : toMinutes;
  int get highMinutes => fromMinutes < toMinutes ? toMinutes : fromMinutes;
}

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.days,
    required this.timedByDay,
    required this.draft,
    required this.colorFor,
    required this.hasAttachment,
    required this.taskCountFor,
    required this.onOpenEvent,
    required this.onDragBegin,
    required this.onDragExtend,
    required this.onDragCommit,
    required this.blockTitle,
    required this.blockColor,
    required this.gutter,
    required this.compact,
  });

  final List<DateTime> days;
  final List<List<CalendarEvent>> timedByDay;
  final _Draft? draft;
  final Color Function(CalendarEvent) colorFor;
  final bool Function(CalendarEvent) hasAttachment;
  final int Function(CalendarEvent) taskCountFor;
  final void Function(CalendarEvent) onOpenEvent;

  /// The create-by-dragging gesture, in the grid's own coordinates.
  final void Function(Offset) onDragBegin;
  final void Function(Offset) onDragExtend;
  final VoidCallback onDragCommit;

  final String? blockTitle;
  final Color? blockColor;

  /// The grid's geometry, decided once by the view above and passed down so
  /// every part of it - painter, labels, blocks - draws to the same one.
  final double gutter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - gutter) / days.length;
        final today = DateTime.now();

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(columns: days.length, gutter: gutter),
              ),
            ),
            Positioned.fill(child: _HourLabels(gutter: gutter)),

            // The now line, only on the column that is actually today.
            for (var i = 0; i < days.length; i++)
              if (_isSameDay(days[i], today))
                Positioned(
                  left: gutter + i * colWidth,
                  width: colWidth,
                  top: (today.hour * 60 + today.minute) / 60 * kHourHeight,
                  height: 2,
                  child: const _NowLine(),
                ),

            // Creating sits *below* the event blocks in the stack, which is
            // what stops a click on an event from also starting a draft: a
            // Stack hit-tests top-down and stops at the first child that takes
            // the pointer, where an ancestor listener would have been handed
            // the down as well and created a block behind the editor.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                // Mouse only. Touch drags belong to the scroll view, which is
                // why the long-press path below exists for them.
                onPointerDown: (e) {
                  if (e.kind != PointerDeviceKind.mouse) return;
                  onDragBegin(e.localPosition);
                },
                onPointerMove: (e) {
                  if (e.kind != PointerDeviceKind.mouse) return;
                  onDragExtend(e.localPosition);
                },
                onPointerUp: (e) {
                  if (e.kind != PointerDeviceKind.mouse) return;
                  onDragCommit();
                },
                child: GestureDetector(
                  onLongPressStart: (d) => onDragBegin(d.localPosition),
                  onLongPressMoveUpdate: (d) => onDragExtend(d.localPosition),
                  onLongPressEnd: (_) => onDragCommit(),
                ),
              ),
            ),

            for (var i = 0; i < days.length; i++)
              ..._positionedEvents(
                events: timedByDay[i],
                day: days[i],
                left: gutter + i * colWidth,
                width: colWidth,
              ),

            if (draft != null)
              Positioned(
                left: gutter + draft!.dayIndex * colWidth + 1,
                width: colWidth - 2,
                top: draft!.lowMinutes / 60 * kHourHeight,
                height: ((draft!.highMinutes - draft!.lowMinutes) / 60 * kHourHeight)
                    .clamp(6.0, double.infinity),
                child: _DraftBlock(
                  from: days[draft!.dayIndex]
                      .add(Duration(minutes: draft!.lowMinutes)),
                  to: days[draft!.dayIndex]
                      .add(Duration(minutes: draft!.highMinutes)),
                  title: blockTitle,
                  color: blockColor,
                  compact: compact,
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _positionedEvents({
    required List<CalendarEvent> events,
    required DateTime day,
    required double left,
    required double width,
  }) {
    final placed = packOverlaps(events);
    return [
      for (final p in placed)
        () {
          final startMin = p.event.start.difference(day).inMinutes.clamp(0, 24 * 60);
          final endMin = p.event.end.difference(day).inMinutes.clamp(0, 24 * 60);
          final slotWidth = (width - 2) / p.columns;
          return Positioned(
            left: left + 1 + p.column * slotWidth,
            width: slotWidth,
            top: startMin / 60 * kHourHeight,
            // Floor of ~14px: a 15-minute event still has to be legible and,
            // more to the point, tappable.
            height: (((endMin - startMin) / 60) * kHourHeight).clamp(14.0, 24 * kHourHeight),
            child: EventBlock(
              event: p.event,
              color: colorFor(p.event),
              hasAttachment: hasAttachment(p.event),
              taskCount: taskCountFor(p.event),
              onTap: () => onOpenEvent(p.event),
              // Two events side by side in a phone column are ~22px each, so
              // the blob's own ornament goes by its slot, not by the day's.
              compact: compact || slotWidth < kCompactColumn,
            ),
          );
        }(),
    ];
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One event's slot within its overlap cluster.
class PlacedEvent {
  const PlacedEvent({
    required this.event,
    required this.column,
    required this.columns,
  });

  final CalendarEvent event;

  /// Which lane this sits in, and how many lanes its cluster needs.
  final int column;
  final int columns;
}

/// Lay overlapping events out side by side.
///
/// Greedy left-most-free-lane, which is what every calendar does: an event
/// takes the first lane whose previous occupant has already ended. The lane
/// *count* is then per cluster rather than per day, so one busy morning does
/// not squeeze the whole afternoon into a sliver.
@visibleForTesting
List<PlacedEvent> packOverlaps(List<CalendarEvent> events) {
  if (events.isEmpty) return const [];

  final sorted = [...events]..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });

  final out = <PlacedEvent>[];
  var cluster = <CalendarEvent>[];
  var clusterLanes = <DateTime>[];
  var clusterStart = 0;
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;
    final lanes = clusterLanes.length;
    for (var i = clusterStart; i < out.length; i++) {
      out[i] = PlacedEvent(
        event: out[i].event,
        column: out[i].column,
        columns: lanes,
      );
    }
    cluster = [];
    clusterLanes = [];
    clusterEnd = null;
    clusterStart = out.length;
  }

  for (final e in sorted) {
    // A gap with nothing running closes the cluster: what follows cannot
    // overlap anything before it, so it should not inherit its lane count.
    if (clusterEnd != null && !e.start.isBefore(clusterEnd!)) flush();

    var lane = clusterLanes.indexWhere((end) => !end.isAfter(e.start));
    if (lane < 0) {
      clusterLanes.add(e.end);
      lane = clusterLanes.length - 1;
    } else {
      clusterLanes[lane] = e.end;
    }

    cluster.add(e);
    clusterEnd = clusterEnd == null || e.end.isAfter(clusterEnd!) ? e.end : clusterEnd;
    out.add(PlacedEvent(event: e, column: lane, columns: 1));
  }
  flush();
  return out;
}

/// The coloured blob for one event.
class EventBlock extends StatelessWidget {
  const EventBlock({
    super.key,
    required this.event,
    required this.color,
    required this.hasAttachment,
    required this.onTap,
    this.taskCount = 0,
    this.compact = false,
  });

  final CalendarEvent event;
  final Color color;
  final bool hasAttachment;
  final VoidCallback onTap;

  /// Open todos planned into this block. Drawn as a bare number beside the
  /// paperclip: at this size a labelled badge would cost the title its width.
  final int taskCount;

  /// A column too narrow for anything but the title. The marks below - the
  /// todo count, the paperclip, the description - are each ~9px of a ~45px
  /// column, and three of them leave the title nothing; they are all one tap
  /// away in the event itself, and the title is what makes the block findable.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 1, bottom: 1),
      child: Material(
        color: Color.lerp(T.bgSolid, color, 0.34),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              // The calendar's colour, stated once down the leading edge. A
              // fully saturated fill at this size drowns the text.
              border: Border(
                  left: BorderSide(color: color, width: compact ? 2 : 2.5)),
            ),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 2.5 : 4, vertical: compact ? 1 : 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 9.5 : 10.5,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: T.text,
                        ),
                      ),
                    ),
                    if (!compact && taskCount > 0) ...[
                      const Icon(Icons.check_circle_outline,
                          size: 9, color: T.muted),
                      Text(
                        '$taskCount',
                        style: const TextStyle(fontSize: 9, color: T.muted),
                      ),
                    ],
                    if (!compact && hasAttachment)
                      const Icon(Icons.attach_file, size: 9, color: T.muted),
                  ],
                ),
                if (!compact && event.description.isNotEmpty)
                  Flexible(
                    child: Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        height: 1.15,
                        color: T.muted,
                      ),
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

/// The span under the pointer mid-drag.
///
/// In time-block mode it is drawn in the target calendar's colour and carries
/// its name, because there the drag is the *whole* interaction - letting go
/// writes the event - so this is the only sight of what is being created. With
/// no block target it is the accent and just the times, which is all a draft
/// about to open the editor has to say.
class _DraftBlock extends StatelessWidget {
  const _DraftBlock({
    required this.from,
    required this.to,
    this.title,
    this.color,
    this.compact = false,
  });

  final DateTime from;
  final DateTime to;
  final String? title;
  final Color? color;

  /// A phone-width column: "09:00 – 10:00" is half as wide again as the column
  /// it is in, so the two ends of the span stack instead of being clipped.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? T.accent;
    return Container(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tint, width: 1),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 2.5 : 4, vertical: 1),
      // The box is as tall as the span dragged so far, which starts at six
      // pixels. Two lines only go in once there is room for two lines - a
      // Column that merely overflows would paint the debug stripes over the
      // grid, and the times are the half that changes as you drag.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final times = Text(
            compact
                ? '${hhmm(from)}\n${hhmm(to)}'
                : '${hhmm(from)} – ${hhmm(to)}',
            maxLines: compact && constraints.maxHeight >= 22 ? 2 : 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
                fontSize: compact ? 8.5 : 9.5, height: 1.15, color: T.text),
          );
          if (title == null || constraints.maxHeight < (compact ? 40 : 26)) {
            return times;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: T.text,
                ),
              ),
              times,
            ],
          );
        },
      ),
    );
  }
}

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: T.danger,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(child: Container(height: 1.5, color: T.danger)),
      ],
    );
  }
}

class _HourLabels extends StatelessWidget {
  const _HourLabels({required this.gutter});

  final double gutter;

  @override
  Widget build(BuildContext context) {
    // A narrow gutter drops the ":00", which is the same on all 23 of them.
    final compact = gutter < kGutter;
    return Stack(
      children: [
        for (var h = 1; h < 24; h++)
          Positioned(
            left: 0,
            width: gutter - (compact ? 4 : 6),
            top: h * kHourHeight - 6,
            child: Text(
              compact ? '$h' : '${h.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: compact ? 8.5 : 9, color: T.muted),
            ),
          ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.columns, required this.gutter});

  final int columns;
  final double gutter;

  @override
  void paint(Canvas canvas, Size size) {
    final hour = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    final half = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1;

    for (var h = 0; h <= 24; h++) {
      final y = h * kHourHeight;
      canvas.drawLine(Offset(gutter, y), Offset(size.width, y), hour);
      if (h < 24) {
        final mid = y + kHourHeight / 2;
        canvas.drawLine(Offset(gutter, mid), Offset(size.width, mid), half);
      }
    }

    final colWidth = (size.width - gutter) / columns;
    for (var c = 0; c <= columns; c++) {
      final x = gutter + c * colWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), hour);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.columns != columns || old.gutter != gutter;
}

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({
    required this.days,
    required this.gutter,
    required this.compact,
  });

  final List<DateTime> days;
  final double gutter;
  final bool compact;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(width: gutter),
          for (final d in days)
            Expanded(
              child: Builder(builder: (context) {
                final isToday = _isSameDay(d, today);
                final name = _names[d.weekday - 1];
                return Center(
                  child: Text(
                    // Initials in a narrow column, as every phone calendar
                    // does: two of them repeat, but their position says which.
                    compact ? '${name[0]} ${d.day}' : '$name ${d.day}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 10.5,
                      color: isToday ? T.accent : T.muted,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

/// The band above the grid for events that cross a day boundary.
///
/// They are not drawn in the hour grid at all: a block running from Tuesday
/// 09:00 to Thursday 17:00 has no single column to live in, and slicing it into
/// three would read as three separate events. Here it is one bar spanning the
/// days it covers, with the start and end times at its ends.
class _SpanBand extends StatelessWidget {
  const _SpanBand({
    required this.days,
    required this.events,
    required this.colorFor,
    required this.onOpen,
    required this.gutter,
    required this.compact,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final Color Function(CalendarEvent) colorFor;
  final void Function(CalendarEvent) onOpen;
  final double gutter;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Each event gets its own row: stacking two bars that overlap in time on
    // one line would hide whichever was drawn second.
    final rows = events.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - gutter) / days.length;
        final last = days.last.add(const Duration(days: 1));

        return SizedBox(
          height: rows * kSpanRowHeight + 4,
          child: Stack(
            children: [
              for (var i = 0; i < events.length; i++)
                () {
                  final e = events[i];
                  // Clipped to the window: an event that began last month still
                  // has to start at the left edge rather than off-screen.
                  final from = e.start.isBefore(days.first) ? days.first : e.start;
                  final to = e.end.isAfter(last) ? last : e.end;

                  final startCol = from.difference(days.first).inMinutes / (24 * 60);
                  final endCol = to.difference(days.first).inMinutes / (24 * 60);

                  final left = gutter + startCol * colWidth;
                  final width = ((endCol - startCol) * colWidth).clamp(18.0, double.infinity);

                  return Positioned(
                    left: left + 1,
                    width: width - 2,
                    top: i * kSpanRowHeight + 2,
                    height: kSpanRowHeight - 2,
                    child: _SpanBar(
                      event: e,
                      color: colorFor(e),
                      // Only label the ends that are really in view - a time
                      // shown at a clipped edge would be the wrong time. In a
                      // phone week the two times are the whole bar, so the
                      // title wins and they go.
                      showStart: !compact && !e.start.isBefore(days.first),
                      showEnd: !compact && !e.end.isAfter(last),
                      onTap: () => onOpen(e),
                    ),
                  );
                }(),
            ],
          ),
        );
      },
    );
  }
}

class _SpanBar extends StatelessWidget {
  const _SpanBar({
    required this.event,
    required this.color,
    required this.showStart,
    required this.showEnd,
    required this.onTap,
  });

  final CalendarEvent event;
  final Color color;
  final bool showStart;
  final bool showEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.lerp(T.bgSolid, color, 0.42),
      borderRadius: BorderRadius.circular(3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              if (showStart)
                Text(
                  hhmm(event.start),
                  style: const TextStyle(fontSize: 9, color: T.muted),
                ),
              if (showStart) const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: T.text,
                  ),
                ),
              ),
              if (showEnd) const SizedBox(width: 5),
              if (showEnd)
                Text(
                  hhmm(event.end),
                  style: const TextStyle(fontSize: 9, color: T.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
