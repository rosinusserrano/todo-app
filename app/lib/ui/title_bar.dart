// Custom title bar - the drag handle, since the window is frameless.
//
// This sits above the focus overlay in the stack (the old z-index: 3), so the
// window stays draggable, pinnable and closable while focus mode covers
// everything else. Anything that must stay reachable during focus belongs here.
//
// It holds the *window and global* controls: settings (where sync lives),
// concentration sound, and the window buttons. The per-workspace views (Notes,
// Parked, History) moved to the ▾ menu on the workspace bar, where they read as
// belonging to the workspace rather than the window.
//
// On iOS and Android there is no OS window to drag or close, so the window
// controls are dropped and only the title and the global controls remain.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../layout.dart';
import '../theme.dart';
import '../window_spots.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.isDesktop,
    required this.pinned,
    required this.onTogglePin,
    this.onToggleSound,
    required this.soundPlaying,
    required this.soundPaused,
    required this.onTogglePause,
    required this.volume,
    required this.onVolumeChanged,
    required this.accent,
    required this.onClose,
    this.onOpenSettings,
    this.onToggleCalendar,
    required this.calendarOpen,
    this.onToggleList,
    required this.listOpen,
    required this.syncColor,
    required this.syncTooltip,
    this.dock,
    this.windowModes,
    this.onWindowMode,
    this.onSaveWindowMode,
    this.onRemoveWindowMode,
  });

  /// The window modes (see window_spots.dart), dropped down from a button
  /// beside Minimize. Desktop only; null on anything that is not a window of
  /// its own.
  final List<WindowMode>? windowModes;
  final ValueChanged<WindowMode>? onWindowMode;
  final VoidCallback? onSaveWindowMode;
  final ValueChanged<WindowMode>? onRemoveWindowMode;

  static const height = 40.0;

  final bool isDesktop;
  final bool pinned;
  final VoidCallback onTogglePin;

  /// Null hides the button: the browser build has no concentration sound.
  final VoidCallback? onToggleSound;

  /// Lights the headphones in the workspace colour while something is loaded,
  /// so the sheet does not have to be open to tell. True while paused too - the
  /// source is still the one this widget is on.
  final bool soundPlaying;

  /// Splits that lit state in two: paused shows ▶ on the transport button and
  /// drops the headphones back to outlined, so "loaded but silent" cannot be
  /// mistaken for "playing".
  final bool soundPaused;

  /// Pause/resume without opening the sheet. The button only exists while
  /// [soundPlaying] - a transport with nothing to transport is just clutter in
  /// a 340px bar.
  final VoidCallback onTogglePause;

  /// 0..1. Shown in the panel that drops out of the transport button on hover,
  /// so the volume is adjustable without opening the sheet either.
  final double volume;
  final ValueChanged<double> onVolumeChanged;

  /// The active workspace colour, so the lit headphones match the window tint.
  final Color accent;

  final VoidCallback onClose;
  final VoidCallback? onOpenSettings;

  /// Sync state, surfaced as the settings icon's colour. A silent failure is
  /// worse than a visible one here: the user would otherwise believe two devices
  /// are in step when they are not.
  final Color syncColor;
  final String syncTooltip;

  /// Unused since the dock took the calendar, the list and settings (see
  /// `_dock` in main.dart); kept as parameters so a build without the dock
  /// could put them back.
  final VoidCallback? onToggleCalendar;
  final bool calendarOpen;

  /// The shopping list, beside the calendar for the same reason: it belongs
  /// to no workspace and replaces the whole body.
  final VoidCallback? onToggleList;
  final bool listOpen;

  /// The dock, when it runs along the top: in this bar, beside the name,
  /// rather than in a second bar under it. Exactly [height] tall.
  final Widget? dock;

  /// The widest the dock is drawn up here. Past it the rest of the bar stays
  /// empty, which on a desktop is the part you move the window by.
  static const dockMaxWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        const SizedBox(width: T.s3),
        // Not hit-testable, so a press on the name falls through to the
        // drag area behind it.
        const IgnorePointer(
          child: Text(
            'Todo',
            style: TextStyle(
              fontSize: T.fsBody,
              fontWeight: T.wMedium,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (dock case final dock?) ...[
          const SizedBox(width: T.s3),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: dockMaxWidth),
              child: dock,
            ),
          ),
        ],
        const Spacer(),
        if (onToggleList != null)
          _Btn(
            tooltip: listOpen ? 'Back to tasks' : 'Shopping list',
            icon: listOpen
                ? Icons.shopping_basket
                : Icons.shopping_basket_outlined,
            tint: listOpen ? accent : null,
            onPressed: onToggleList!,
          ),
        if (onToggleCalendar != null)
          _Btn(
            tooltip: calendarOpen ? 'Back to tasks' : 'Calendar',
            icon: calendarOpen
                ? Icons.calendar_month
                : Icons.calendar_month_outlined,
            tint: calendarOpen ? accent : null,
            onPressed: onToggleCalendar!,
          ),
        if (onOpenSettings != null)
          _Btn(
            tooltip: syncTooltip,
            icon: Icons.settings_outlined,
            tint: syncColor,
            onPressed: onOpenSettings!,
          ),
        if (soundPlaying)
          _TransportButton(
            paused: soundPaused,
            accent: accent,
            onPressed: onTogglePause,
            volume: volume,
            onVolumeChanged: onVolumeChanged,
          ),
        if (onToggleSound case final onToggleSound?)
          _Btn(
            tooltip: 'Concentration sound',
            icon: soundPlaying && !soundPaused
                ? Icons.headphones
                : Icons.headphones_outlined,
            tint: soundPlaying ? accent : null,
            onPressed: onToggleSound,
          ),
        if (isDesktop) ...[
          _Btn(
            tooltip: pinned ? 'Unpin' : 'Always on top',
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            // The workspace colour rather than the fixed theme accent, so
            // every lit control in this bar reads as one family.
            tint: pinned ? accent : null,
            onPressed: onTogglePin,
          ),
          _Btn(
            tooltip: 'Minimize',
            icon: Icons.remove,
            onPressed: windowManager.minimize,
          ),
          // Where a maximise button would be: this is the window's size too,
          // just more than two of them.
          if (windowModes case final modes?)
            _WindowModes(
              modes: modes,
              accent: accent,
              onPick: onWindowMode!,
              onSave: onSaveWindowMode!,
              onRemove: onRemoveWindowMode!,
            ),
          _Btn(tooltip: 'Close', icon: Icons.close, onPressed: onClose),
        ],
        const SizedBox(width: 6),
      ],
    );

    // The drag area is *behind* the row, not around it. Wrapped around, it is
    // an ancestor of every button and of the dock, and its pan recogniser
    // would take a press-and-slide on a dock segment and move the window
    // instead. Behind, it gets only the presses nothing in the row took: the
    // name and the empty stretch.
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          if (isDesktop)
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          Positioned.fill(child: row),
        ],
      ),
    );
  }
}

/// The pause/resume button, plus a volume slider that drops out of it on hover.
///
/// The slider lives in an [OverlayEntry] rather than in the bar: the bar is 40px
/// tall and would clip it, and the panel has to float over the workspace bar
/// underneath. [LayerLink] keeps it stuck to the button as the window moves.
///
/// The fiddly part is that the pointer must cross a gap to reach the panel. Both
/// the button and the panel feed one hover count, and leaving starts a short
/// timer rather than closing outright - without that the panel disappears in the
/// few pixels between the two and can never be reached.
class _TransportButton extends StatefulWidget {
  const _TransportButton({
    required this.paused,
    required this.accent,
    required this.onPressed,
    required this.volume,
    required this.onVolumeChanged,
  });

  final bool paused;
  final Color accent;
  final VoidCallback onPressed;
  final double volume;
  final ValueChanged<double> onVolumeChanged;

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  final _link = LayerLink();
  OverlayEntry? _panel;
  Timer? _closing;

  /// Long enough to cross the gap between button and panel, short enough not to
  /// linger once the pointer has genuinely left.
  static const _grace = Duration(milliseconds: 180);

  @override
  void dispose() {
    _closing?.cancel();
    // The button is removed the moment the sound stops, which can happen with
    // the panel open - it has to come down with it rather than be orphaned in
    // the overlay. Checked rather than assumed: the overlay may already be
    // going down itself, and removing a detached entry asserts.
    if (_panel?.mounted ?? false) _panel!.remove();
    _panel = null;
    super.dispose();
  }

  void _enter() {
    _closing?.cancel();
    if (_panel != null) return;

    _panel = OverlayEntry(
      builder: (_) => Positioned(
        // Width is fixed here rather than on the panel so the follower has a
        // definite box to align; CompositedTransformFollower is otherwise
        // unbounded and the Slider inside has no width to lay out against.
        width: _VolumePanel.width,
        child: CompositedTransformFollower(
          link: _link,
          // Hung from the button's right edge and extending left, not centred
          // on it. Every control in this bar lives in its right-hand end, so a
          // centred panel wider than twice the remaining margin would spill off
          // the window; growing leftwards it always has the whole bar to use.
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: _VolumePanel(
            accent: widget.accent,
            initial: widget.volume,
            onChanged: widget.onVolumeChanged,
            onEnter: _enter,
            onExit: _exit,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_panel!);
  }

  void _exit() {
    _closing?.cancel();
    _closing = Timer(_grace, () {
      _panel?.remove();
      _panel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        child: _Btn(
          tooltip: widget.paused ? 'Resume sound' : 'Pause sound',
          icon: widget.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          tint: widget.accent,
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}

/// The hover panel itself. Holds the slider value locally so dragging is smooth
/// without the overlay having to be rebuilt from above on every frame; it is
/// seeded on each open, which is often enough given the panel is transient.
class _VolumePanel extends StatefulWidget {
  const _VolumePanel({
    required this.accent,
    required this.initial,
    required this.onChanged,
    required this.onEnter,
    required this.onExit,
  });

  static const width = 132.0;

  final Color accent;
  final double initial;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  State<_VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<_VolumePanel> {
  late double _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => widget.onExit(),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s1),
          decoration: BoxDecoration(
            color: T.bgSolid,
            borderRadius: BorderRadius.circular(T.radius),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                _value == 0
                    ? Icons.volume_off_rounded
                    : _value < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                size: 14,
                color: T.muted,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: widget.accent,
                    inactiveTrackColor: T.surfaceHover,
                    thumbColor: widget.accent,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: _value,
                    onChanged: (v) {
                      setState(() => _value = v);
                      widget.onChanged(v);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The window modes: a button where a maximise button would be, whose list
/// drops down while the mouse is over it - each row a size and a place in
/// one, with a picture of where the window goes - plus a row that keeps the
/// window as it is now as another. Same hover arrangement as the volume
/// panel above: button and panel feed one hover, and leaving either starts a
/// short timer rather than closing outright, so the gap can be crossed.
class _WindowModes extends StatefulWidget {
  const _WindowModes({
    required this.modes,
    required this.accent,
    required this.onPick,
    required this.onSave,
    required this.onRemove,
  });

  final List<WindowMode> modes;
  final Color accent;
  final ValueChanged<WindowMode> onPick;
  final VoidCallback onSave;
  final ValueChanged<WindowMode> onRemove;

  @override
  State<_WindowModes> createState() => _WindowModesState();
}

class _WindowModesState extends State<_WindowModes> {
  final _link = LayerLink();
  OverlayEntry? _panel;
  Timer? _timer;

  /// Resting on the button opens it; passing over it on the way to Close
  /// does not.
  static const _openDelay = Duration(milliseconds: 150);
  static const _grace = Duration(milliseconds: 250);

  @override
  void didUpdateWidget(_WindowModes oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The entry is built from this widget's fields; a mode saved or removed
    // while the panel is up has to show in it.
    _panel?.markNeedsBuild();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_panel?.mounted ?? false) _panel!.remove();
    _panel = null;
    super.dispose();
  }

  void _enter() {
    _timer?.cancel();
    if (_panel != null) return;
    _timer = Timer(_openDelay, _open);
  }

  void _exit() {
    _timer?.cancel();
    _timer = Timer(_grace, _close);
  }

  void _open() {
    if (_panel != null || !mounted) return;
    _panel = OverlayEntry(
      builder: (_) => Positioned(
        width: _ModesPanel.width,
        child: CompositedTransformFollower(
          link: _link,
          // Hung from the button's right edge and growing left, like the
          // volume panel: the button is at the right-hand end of the bar.
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: MouseRegion(
            onEnter: (_) => _timer?.cancel(),
            onExit: (_) => _exit(),
            child: _ModesPanel(
              modes: widget.modes,
              accent: widget.accent,
              onPick: (m) {
                _close();
                widget.onPick(m);
              },
              onSave: widget.onSave,
              onRemove: widget.onRemove,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_panel!);
  }

  void _close() {
    _timer?.cancel();
    if (_panel?.mounted ?? false) _panel!.remove();
    _panel = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        // A click opens it at once, for a touch screen or anyone who clicks
        // before the hover has caught up; a second click closes it.
        child: _Btn(
          tooltip: 'Window size and place',
          icon: Icons.crop_square_rounded,
          onPressed: () => _panel == null ? _open() : _close(),
        ),
      ),
    );
  }
}

class _ModesPanel extends StatelessWidget {
  const _ModesPanel({
    required this.modes,
    required this.accent,
    required this.onPick,
    required this.onSave,
    required this.onRemove,
  });

  static const width = 236.0;
  static const _rowHeight = 34.0;

  final List<WindowMode> modes;
  final Color accent;
  final ValueChanged<WindowMode> onPick;
  final VoidCallback onSave;
  final ValueChanged<WindowMode> onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: T.s1),
        decoration: BoxDecoration(
          color: T.bgSolid,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in modes)
              _ModeRow(
                mode: m,
                accent: accent,
                onTap: () => onPick(m),
                onRemove: () => onRemove(m),
              ),
            if (modes.isNotEmpty)
              const Divider(
                height: T.s2,
                thickness: 1,
                color: Color(0x14FFFFFF),
              ),
            InkWell(
              onTap: onSave,
              child: SizedBox(
                height: _rowHeight,
                child: Row(
                  children: [
                    const SizedBox(width: T.s3),
                    const SizedBox(
                      width: _MiniScreen.width,
                      child: Icon(Icons.add_rounded, size: 16, color: T.muted),
                    ),
                    const SizedBox(width: T.s3),
                    const Expanded(
                      child: Text(
                        'Save this window',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: T.fsLabel, color: T.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatefulWidget {
  const _ModeRow({
    required this.mode,
    required this.accent,
    required this.onTap,
    required this.onRemove,
  });

  final WindowMode mode;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_ModeRow> createState() => _ModeRowState();
}

class _ModeRowState extends State<_ModeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: SizedBox(
          height: _ModesPanel._rowHeight,
          child: Row(
            children: [
              const SizedBox(width: T.s3),
              _MiniScreen(mode: widget.mode, accent: widget.accent),
              const SizedBox(width: T.s3),
              Expanded(
                child: Text(
                  widget.mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: T.fsLabel, color: T.text),
                ),
              ),
              // Removing is there only under the mouse, so the list reads
              // as a list of places rather than a list of delete buttons.
              Opacity(
                opacity: _hovered ? 1 : 0,
                child: Tooltip(
                  message: 'Remove',
                  child: InkWell(
                    onTap: _hovered ? widget.onRemove : null,
                    borderRadius: BorderRadius.circular(T.radius),
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: T.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: T.s1),
            ],
          ),
        ),
      ),
    );
  }
}

/// A screen in miniature with the window drawn where [mode] puts it.
class _MiniScreen extends StatelessWidget {
  const _MiniScreen({required this.mode, required this.accent});

  static const width = 28.0;
  static const height = 18.0;

  /// The screen the picture assumes: a common laptop's work area. Only the
  /// proportions matter.
  static const _screen = Rect.fromLTWH(0, 0, 1920, 1032);

  final WindowMode mode;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(width, height),
      painter: _MiniScreenPainter(
        window: mode.placeIn(_screen),
        screen: _screen,
        accent: accent,
      ),
    );
  }
}

class _MiniScreenPainter extends CustomPainter {
  _MiniScreenPainter({
    required this.window,
    required this.screen,
    required this.accent,
  });

  final Rect window;
  final Rect screen;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame.deflate(0.5), const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = T.muted,
    );
    final inner = frame.deflate(2);
    final sx = inner.width / screen.width;
    final sy = inner.height / screen.height;
    final r = Rect.fromLTWH(
      inner.left + (window.left - screen.left) * sx,
      inner.top + (window.top - screen.top) * sy,
      math.max(2, window.width * sx),
      math.max(2, window.height * sy),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1)),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_MiniScreenPainter old) =>
      old.window != window || old.accent != accent;
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tint,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Lit colour. Every lit control in this bar is tinted by its caller - the
  /// workspace colour for sound and pin, sync health for the gear - so there is
  /// no generic "active" state left to fall back on.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? T.muted;
    final layout = Layout.of(context);

    // A square rather than a padded glyph, so the target is a number this
    // widget states instead of one that falls out of an icon size plus 6.
    // Capped at the bar's own height: these are the controls the calendar,
    // sound and settings are opened from, and on a phone a 15px icon with 6px
    // around it is a 27pt target that misses about a third of the time.
    final side = math.min(layout.tapTarget, TitleBar.height);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(T.radius),
        child: SizedBox(
          width: side,
          height: side,
          child: Icon(icon, size: layout.actionIcon, color: color),
        ),
      ),
    );
  }
}
