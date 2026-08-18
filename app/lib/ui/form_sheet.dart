// The panel every form in this app opens as.
//
// This started as `_Surface` inside task_composer.dart, written when the task
// editor stopped being an `AlertDialog`. It is here now because the event
// editor and the event details card needed exactly the same thing, and a second
// copy of a shape whose whole point is that every form looks the same would be
// the one file guaranteed to drift.
//
// What it replaces, and why: `AlertDialog` brings Material's own surface,
// insets, title styling and button bar, so on a phone a form arrived as a small
// grey card floating in the middle of the screen in stock purple and blue,
// cropped by the keyboard, with its last row cut off - a different
// application's dialog wearing this app's data. [showFormSheet] is
// `showGeneralDialog` with the surface drawn from the same tokens as
// SettingsSheet, so a form reads as this app opening a panel.
//
// The shape is one decision made twice, on [Layout.touch]:
//
//   - Touch: full width, anchored to the bottom, rounded at the top only, and
//     rising from the bottom edge. A phone form belongs against the thumb and
//     against the keyboard, and a card inset by 40px on each side is 40px of
//     line length given away on the narrowest screen there is.
//   - Pointer: a centred column at the width the fields were drawn for, fading
//     in with a small rise. A full-width sheet on a 1400px monitor would be a
//     form with a metre of nothing beside it.
//
// Either way the body scrolls and the surface is pushed up by the keyboard
// rather than covered by it (`viewInsets`), which is what makes the last row of
// controls reachable while a field has the caret.
//
// A modal *route*, unlike Settings and the sublist. The rule in main.dart is
// about things that live on screen while you work around them - a sheet leaves
// the title bar reachable so the window can still be dragged and closed. A form
// is modal by nature: it is one row's fields, saved or cancelled.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';

/// Opens [builder]'s panel as a modal route.
///
/// The [Layout] is resolved here and handed to the builder, because everything
/// inside is built by a route that sits *above* the shell's `LayoutScope` and
/// so cannot look it up for itself.
/// The type parameter is `R`, not `T`: `T` is the design-token class this file
/// draws every colour from, and shadowing it here would make `T.sheetDur` below
/// resolve to the type parameter.
Future<R?> showFormSheet<R>(
  BuildContext context, {
  required Widget Function(BuildContext context, Layout layout) builder,
}) {
  final layout = Layout.of(context);

  return showGeneralDialog<R>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x99000000),
    // Matched to the sheets in the shell, since the two animate the same way
    // and arriving at different speeds would read as two different kinds of
    // thing.
    transitionDuration: T.sheetDur,
    pageBuilder: (context, _, _) => builder(context, layout),
    transitionBuilder: (context, anim, _, child) {
      final t = T.sheetEase.transform(anim.value);
      return FadeTransition(
        opacity: anim,
        child: Transform.translate(
          // Touch rises the full height of a thumb's travel; a pointer gets a
          // token 12px, which reads as "this appeared" without the panel
          // sliding across a desk-sized screen.
          offset: Offset(0, (1 - t) * (layout.touch ? 64 : 12)),
          child: child,
        ),
      );
    },
  );
}

/// The panel itself: a titled surface in [accent], a scrolling body, and a row
/// of [actions] along the bottom.
///
/// [actions] rather than a fixed Cancel/Save pair, because the three forms that
/// use this do not agree on what the ways out are - the details card has four
/// named ones and no Save at all. Build them with [cancelButton], [saveButton]
/// and [dangerButton] so they stay the same size and colour everywhere.
class FormSheet extends StatelessWidget {
  const FormSheet({
    super.key,
    required this.accent,
    required this.layout,
    required this.title,
    required this.onClose,
    required this.actions,
    required this.child,
    this.maxWidth = 380,
  });

  /// The colour this panel belongs to - the workspace's, or the calendar's.
  /// Not Material's seed purple: a panel opened from a green calendar being
  /// blue is how a form reads as somebody else's.
  final Color accent;

  /// Passed in rather than read from context - see [showFormSheet].
  final Layout layout;

  final String title;

  /// The ✕ in the corner, and what the barrier means. Always "leave without
  /// saving".
  final VoidCallback onClose;

  final List<Widget> actions;
  final Widget child;

  /// Only used away from touch, where the panel is a centred column.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final touch = layout.touch;

    // What the keyboard is covering. Padding the panel by it lifts the whole
    // form clear rather than letting the caret sit behind the keys - which is
    // what the AlertDialog did, and why the last row was unreachable on a phone
    // with a text field focused.
    final keyboard = media.viewInsets.bottom;

    // AlertDialog used to bring this along, and dropping it is what broke the
    // fields: an InkWell needs a Material to paint its splash onto and a
    // TextField needs one for its decoration, so without it the whole form
    // asserts. Transparent, because the surface below is drawn by the Container
    // and a second opaque layer would flatten it.
    final panel = Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, accent, 0.14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          borderRadius: touch
              // Square at the bottom on touch: the panel is against the edge of
              // the screen, and a rounded corner there shows a sliver of the
              // list behind it that reads as a rendering fault.
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : BorderRadius.circular(T.radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 34,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: T.text,
                      ),
                    ),
                  ),
                  // A real close control, not just the barrier. On a phone the
                  // barrier is a thin strip above a full-width panel and is
                  // nobody's first guess at how to get out.
                  Semantics(
                    label: 'Close',
                    button: true,
                    child: InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: touch ? 40 : 28,
                        height: touch ? 40 : 28,
                        child: Icon(
                          Icons.close_rounded,
                          size: touch ? 20 : 16,
                          color: T.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: child,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, touch ? 18 : 14),
              // Wrapped rather than a Row: four named actions at
              // finger-size do not fit across a phone, and shrinking them
              // below a fingertip to keep one line is the trade this app
              // does not make (see the task row's action bar).
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );

    if (touch) {
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Never taller than most of the screen, so there is always a strip
            // of barrier left to tap and the panel never reads as a new page.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * 0.88 - keyboard,
              ),
              child: panel,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: media.size.height * 0.86 - keyboard,
          ),
          child: panel,
        ),
      ),
    );
  }

  /// A quiet way out.
  static Widget cancelButton({
    required bool touch,
    required VoidCallback onTap,
    String label = 'Cancel',
  }) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: T.muted,
      minimumSize: Size(0, touch ? 44 : 32),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12.5)),
  );

  /// The one that commits, in the panel's own colour.
  static Widget saveButton({
    required bool touch,
    required Color accent,
    required VoidCallback onTap,
    String label = 'Save',
  }) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: T.bgSolid,
      minimumSize: Size(touch ? 96 : 64, touch ? 44 : 32),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );

  /// Delete, and anything else that cannot be undone.
  static Widget dangerButton({
    required bool touch,
    required VoidCallback onTap,
    String label = 'Delete',
  }) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: T.danger,
      minimumSize: Size(0, touch ? 44 : 32),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12.5)),
  );

  /// A named action that is neither the commit nor a way out - *Edit* and
  /// *Todos* on the details card.
  static Widget plainButton({
    required bool touch,
    required VoidCallback onTap,
    required String label,
    IconData? icon,
  }) => TextButton.icon(
    onPressed: onTap,
    icon: icon == null ? null : Icon(icon, size: touch ? 17 : 14),
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
    style: TextButton.styleFrom(
      foregroundColor: T.text,
      minimumSize: Size(0, touch ? 44 : 32),
    ),
  );
}
