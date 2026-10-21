// Where the shell's own keys are heard: Ctrl+E, N, Esc, Ctrl +/-.
//
// A **FocusScope**, not a Focus, and that is the whole file. Key events start
// at the focused node and travel *up*. When a text field lets go of focus -
// a click outside it on a desktop (Flutter's default), the add card closing -
// `unfocus()` hands focus to the nearest enclosing *scope*. With a plain
// Focus here that scope was the route's, which sits above this node, so from
// then on no key reached the shell at all: Ctrl+E worked after launch and
// "only sometimes" after that, until something happened to focus a widget
// inside again (Marco, 2026-10-21). As a scope, this node is where the focus
// lands, and the keys keep arriving.

import 'package:flutter/widgets.dart';

class ShellKeys extends StatelessWidget {
  const ShellKeys({super.key, required this.onKeyEvent, required this.child});

  final FocusOnKeyEventCallback onKeyEvent;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusScope(autofocus: true, onKeyEvent: onKeyEvent, child: child);
}
