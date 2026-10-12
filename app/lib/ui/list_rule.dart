// What separates two rows of a list: a short bar that stops before both edges.
//
// Rows used to be tiles - each its own rounded, filled box with a gap between -
// which is the look of every stock productivity app and the thing that made
// this one read as one. A row is now just its content on the window's own
// colour, and the list is told apart by a hairline that does not reach the
// edges: enough to say where one item ends, not so much that each is fenced in.
// A row keeps a fill only when the fill *says* something (selected, overdue,
// in focus) - colour as information rather than as packaging.

import 'package:flutter/material.dart';

import '../theme.dart';

class ListRule extends StatelessWidget {
  const ListRule({super.key, this.inset = T.s4});

  /// How far the bar stops short of each edge.
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: inset),
    child: Container(height: 1, color: T.text.withValues(alpha: 0.08)),
  );
}
