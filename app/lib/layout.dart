// How much room the widget has, and what it is therefore allowed to show.
//
// This app is one window that ranges from a 260px sliver pinned to the corner
// of a screen, through the 340x480 it was designed against, to a half-screen
// panel on a 4K monitor - and it is the *same* window the whole time. Rather
// than each view guessing at its own thresholds, every size-dependent decision
// in the app is a getter on this class, so the breakpoints are readable in one
// place and testable without pumping a widget.
//
// Two rules the getters below all follow:
//
//   1. **Nothing is ever unreachable.** A feature may change shape when it does
//      not fit - the week grid becomes an agenda, the year stacks into one
//      column, the workspace bar unrolls into a rail - but no size takes a
//      feature away. That is what separates this from a mobile/desktop fork.
//   2. **The design width is the floor, not the target.** Every padding and
//      font size in this app was picked against [T.designWidth]; extra room is
//      spent on *more at once* (a rail, a second pane) rather than on stretching
//      what is already there, which is why the task column has a cap.
//
// The numbers are minimum *contents*, worked backwards from what the thing
// being laid out needs, not round numbers picked by eye.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'ui/calendar/time_grid.dart' show kGutter, kGutterCompact;

@immutable
class Layout {
  const Layout(this.size, {this.touch = false});

  /// The box the shell itself was given - *after* [UiScale], so a phone
  /// reports the size its layout actually runs at rather than its raw screen.
  final Size size;

  /// Whether a fingertip is the pointer.
  ///
  /// **The one axis here that is not a size**, and it is separate because the
  /// two questions genuinely are. Everything else on this class asks "does it
  /// fit"; this asks "can it be reached at all", and the answers differ: a
  /// 340px desktop window and a 340pt phone lay out identically and still need
  /// different controls, because one of them has a hover state and a 3px
  /// pointer and the other has neither.
  ///
  /// It exists because pretending otherwise had already cost real function -
  /// every action on a task row was drawn behind `visible: _hovered`, which on
  /// a phone meant reminders, parking, focus and delete were not small, they
  /// were **absent**, and no width would ever have brought them back.
  ///
  /// It is a field rather than a `Platform` check at the point of use for the
  /// same reason every threshold here is a getter: one place to read, one place
  /// to change, and a test can pump a touch layout on a desktop machine. The
  /// shell sets it from `!isDesktop`; the fallback is false, which is what
  /// keeps a widget test of the desktop layout honest by default.
  final bool touch;

  double get width => size.width;
  double get height => size.height;

  // ------------------------------------------------------------ hit targets

  /// The side of a square control, in layout units.
  ///
  /// 40 rather than the 44 Apple asks for, because this number is spent
  /// *inside* [UiScale]: the phone zoom is `clamp(width / 340, 1, 1.28)`, so
  /// the smallest zoom any real phone applies is about 1.1 (a 375pt device) and
  /// 40 lands at 44pt or more on screen. Asking for 44 here would render at 48
  /// and up, which on a 340-unit-wide layout is a bar of five buttons and no
  /// room for what they are next to.
  ///
  /// Zero-ish on desktop is deliberate: a mouse hits a 16px icon exactly as
  /// well as a 40px one, and the widget is 340px wide.
  static const touchTargetSide = 40.0;
  static const pointerTargetSide = 26.0;

  double get tapTarget => touch ? touchTargetSide : pointerTargetSide;

  /// Icon inside that target. The glyph grows with the target, or a 40px
  /// button around a 14px icon reads as a mis-click waiting to happen.
  double get actionIcon => touch ? 20.0 : 15.0;

  /// Whether an action may be revealed by hovering.
  ///
  /// False on touch, and every hover-gated control has to ask - there is no
  /// hover to reveal it, so "shown on hover" means "never shown".
  bool get canHover => !touch;

  // ------------------------------------------------------------------- rail

  /// The workspace bar, unrolled down the left edge.
  static const railWidth = 190.0;

  /// Below this the bar's popup menus are the only way the workspace list and
  /// the views fit at all; above it there is room to have them permanently on
  /// screen, which is a menu press saved on every switch.
  ///
  /// [railWidth] + [taskColumnMax] would be 810; the rail is worth having well
  /// before that, so this is set at the point where the task column still gets
  /// its design width with the rail taken out: 190 + 340 + slack.
  static const railMinWidth = 560.0;

  /// The rail lists workspaces *and* views. In a short window that list would
  /// scroll, which is worse than the menu it replaced.
  static const railMinHeight = 400.0;

  bool get hasRail => width >= railMinWidth && height >= railMinHeight;

  // ------------------------------------------------------------ content area

  /// The widest the task list is allowed to get. A checklist is a column of
  /// short lines; run it to 900px and the eye has to sweep back to the tick box
  /// on every row. Extra width goes to the panes beside it instead.
  static const taskColumnMax = 620.0;

  /// Notes / Parked / History / Thoughts stop *replacing* the task list and sit
  /// beside it instead. Needs the task column plus a pane wide enough to be
  /// worth splitting off - a 200px History column would be neither.
  static const splitMinWidth = 900.0;

  bool get splitsContent =>
      width >= splitMinWidth && height >= railMinHeight;

  /// Width available to the content column, rail already taken out.
  double get contentWidth => hasRail ? width - railWidth : width;

  // --------------------------------------------------------------- calendar

  /// The narrowest a day column can be and still carry an event title and a
  /// drag. Forty pixels is about six characters of a title at the grid's
  /// compact geometry - which is what a phone week is, and is the size every
  /// phone calendar shows one at. Below it the seven columns really are
  /// unreadable slivers and the agenda takes over.
  static const minDayColumn = 40.0;

  /// Whether the week grid fits, or the week has to be shown as an agenda.
  ///
  /// Measured against the real grid geometry rather than a tier, because that
  /// is the actual question - and against [kGutterCompact], because a week this
  /// narrow is drawn with the narrow gutter, so the roomy one would be
  /// measuring space the grid was never going to spend.
  bool get weekGridFits => (width - kGutterCompact) / 7 >= minDayColumn;

  /// A day column drawn at the *roomy* geometry - a title, its times and the
  /// marks on a blob. This is the number [minDayColumn] used to be, before the
  /// compact grid gave a phone a narrower one to be measured against.
  static const roomyDayColumn = 62.0;

  /// Past this the calendar stops replacing the whole window and opens beside
  /// the task list, which is where a task can be dragged onto a block.
  ///
  /// Worked backwards from contents like the rest: the task column at its
  /// design width, plus a week grid whose seven columns are still roomy, plus
  /// the divider between them. Below it nothing changes - the calendar takes
  /// the window, as it always has.
  static const calendarSplitMinWidth =
      calendarTaskPaneWidth + kGutter + 7 * roomyDayColumn + 1;

  /// The task list's share when the two are side by side.
  ///
  /// Fixed rather than proportional: the list was drawn against
  /// [T.designWidth] and gains nothing from being wider (see [taskColumnMax]),
  /// while the grid gains a legible day per [roomyDayColumn]. Every extra pixel
  /// is therefore worth more to the calendar.
  static const calendarTaskPaneWidth = T.designWidth;

  /// Height as well as width, for the same reason the rail is gated on it: a
  /// short window makes both halves scroll, and two scrolling halves are worse
  /// than the one full-window view they replaced.
  bool get splitsCalendar =>
      width >= calendarSplitMinWidth && height >= railMinHeight;

  /// A month tile wants this much to keep two-digit day numbers legible, and
  /// the 8px the year view puts between tiles.
  static const monthTileMin = 190.0;
  static const monthTileGap = 8.0;

  /// How many months the year view puts side by side. **One is a legitimate
  /// answer**: twelve months stacked in a single column is how a year fits in
  /// a 340px widget, and it reads perfectly well - it is only wide.
  int get yearColumns {
    final usable = width - 16 + monthTileGap; // the view's own padding
    return (usable / (monthTileMin + monthTileGap)).floor().clamp(1, 6);
  }

  // ------------------------------------------------------------- focus tile

  /// How far the focus tile stays clear of the window edges.
  static const focusTileMargin = 28.0;

  /// And the widest it may get. A title stretched across a wide window is a
  /// line you have to sweep your head along; the tile is meant to be one glance.
  static const focusTileMax = 460.0;

  /// The tile's width at rest. Used by both the resting layout and the
  /// flight's landing rect - if those two disagree the tile visibly jumps
  /// sideways the instant the flight ends, which is why it is computed once
  /// here instead of twice at the call sites.
  double get focusTileWidth =>
      math.min(width - focusTileMargin * 2, focusTileMax);

  @override
  bool operator ==(Object other) =>
      other is Layout && other.size == size && other.touch == touch;

  @override
  int get hashCode => Object.hash(size, touch);

  /// The layout the enclosing shell measured.
  ///
  /// Falls back to the design window rather than throwing, so a panel can be
  /// pumped on its own in a test - and so the fallback is the size everything
  /// here was drawn for in the first place.
  static Layout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.layout ??
      const Layout(Size(T.designWidth, 480));
}

/// Publishes the shell's measured box to everything under it.
class LayoutScope extends InheritedWidget {
  const LayoutScope({super.key, required this.layout, required super.child});

  final Layout layout;

  @override
  bool updateShouldNotify(LayoutScope oldWidget) =>
      oldWidget.layout != layout;
}
