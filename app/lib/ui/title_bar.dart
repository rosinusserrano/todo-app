// Custom title bar - the drag handle, since the window is frameless.
//
// This sits above the focus overlay in the stack (the old z-index: 3), so the
// window stays draggable, pinnable and closable while focus mode covers
// everything else. Anything that must stay reachable during focus belongs here.
//
// On iOS and Android there is no OS window to drag or close, so the window
// controls are dropped and only the title and history button remain.

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.isDesktop,
    required this.pinned,
    required this.onTogglePin,
    required this.onToggleHistory,
    required this.onClose,
    required this.onOpenSettings,
    required this.syncColor,
    required this.syncTooltip,
  });

  static const height = 40.0;

  final bool isDesktop;
  final bool pinned;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleHistory;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  /// Sync state, surfaced as the cloud icon's colour. A silent failure is worse
  /// than a visible one here: the user would otherwise believe two devices are
  /// in step when they are not.
  final Color syncColor;
  final String syncTooltip;

  @override
  Widget build(BuildContext context) {
    final bar = SizedBox(
      height: height,
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Text(
            'Todo',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          _Btn(
            tooltip: syncTooltip,
            icon: Icons.cloud_outlined,
            tint: syncColor,
            onPressed: onOpenSettings,
          ),
          _Btn(
            tooltip: 'History',
            icon: Icons.history_rounded,
            onPressed: onToggleHistory,
          ),
          if (isDesktop) ...[
            _Btn(
              tooltip: pinned ? 'Unpin' : 'Always on top',
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              active: pinned,
              onPressed: onTogglePin,
            ),
            _Btn(
              tooltip: 'Minimize',
              icon: Icons.remove,
              onPressed: windowManager.minimize,
            ),
            _Btn(
              tooltip: 'Close',
              icon: Icons.close,
              onPressed: onClose,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );

    // DragToMoveArea must not wrap the buttons themselves or it swallows their
    // clicks - the same trap as putting data-tauri-drag-region on a child.
    return isDesktop ? DragToMoveArea(child: bar) : bar;
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.tint,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 15,
            color: tint ?? (active ? T.accent : T.muted),
          ),
        ),
      ),
    );
  }
}
