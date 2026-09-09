// The content area's slot in the shell's column.
//
// One function, and the whole of it is a key and an unconditional Stack. Both
// exist because the chrome *around* the content comes and goes while the
// content itself stays: opening a note or expanding a task on a phone takes
// the workspace bar off the top and the view bar and footer off the bottom
// (`_takesScreen` in main.dart), and the thought bubble appears and disappears
// with them.
//
// Flutter matches unkeyed children of a multi-child widget by position. Take
// the bar away and the content is suddenly child 0 where it was child 2, no
// child matches, and every element in that subtree is rebuilt from scratch -
// which throws away the State underneath it. That is not cosmetic: JournalView
// keeps *which rung of its ladder you are on* in its own State, so opening a
// note reported "a note is open", the shell hid the chrome, the rebuild reset
// the panel to its list, and the note appeared to close itself one frame after
// being opened. Wrapping the bubble in a Stack only when the bubble is there is
// the same structural change one level down.
//
// So: one key, so the reconciler knows this is the same subtree in a new slot,
// and one Stack that is always built, so the overlay is a child rather than a
// reason to change shape.

import 'package:flutter/material.dart';

/// Identity for the content area across every rearrangement of the chrome.
const contentSlotKey = ValueKey('content-slot');

/// The content area as a [Flex] child. [overlay] is drawn on top of it and is
/// expected to position itself; null simply leaves the stack with one child.
///
/// Returns an [Expanded] rather than wrapping one, because a parent data widget
/// has to be the direct child of the [Flex] it is talking to.
Expanded contentSlot({required Widget child, Widget? overlay}) => Expanded(
      key: contentSlotKey,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          ?overlay,
        ],
      ),
    );
