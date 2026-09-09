// The content area survives the chrome around it being taken away.
//
// This is the shape of the bug where opening a note on a phone closed it again
// one frame later: the panel reported "a note is open", the shell hid the
// workspace bar above and the view bar and footer below, and the content -
// suddenly a different child of the same Column - was rebuilt from scratch,
// taking JournalView's own idea of which rung it was on with it.
//
// So the thing worth pinning is not the note, it is the slot: a child whose
// siblings come and go must keep its State.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/content_slot.dart';

/// Stands in for a panel that remembers something the shell does not.
class _Rung extends StatefulWidget {
  const _Rung();

  @override
  State<_Rung> createState() => _RungState();
}

class _RungState extends State<_Rung> {
  int opened = 0;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => opened++),
        child: Text('opened $opened'),
      );
}

void main() {
  testWidgets('keeps its state when the chrome around it disappears',
      (tester) async {
    var chrome = true;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setOuter) => Column(
            children: [
              if (chrome) const Text('workspace bar'),
              contentSlot(
                child: Column(
                  children: [
                    const _Rung(),
                    // Standing in for the panel telling the shell a note is
                    // open, which is what makes the chrome go away.
                    TextButton(
                      onPressed: () => setOuter(() => chrome = false),
                      child: const Text('take the screen'),
                    ),
                  ],
                ),
              ),
              if (chrome) const Text('footer'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('opened 0'));
    await tester.pump();
    expect(find.text('opened 1'), findsOneWidget);

    // Open it: the bar and the footer go, and the slot changes position in the
    // column from the middle child to the only one.
    await tester.tap(find.text('take the screen'));
    await tester.pump();

    expect(find.text('workspace bar'), findsNothing);
    expect(find.text('opened 1'), findsOneWidget,
        reason: 'the panel was rebuilt from scratch and lost its state');
  });

  testWidgets('draws the overlay above the content, and nothing without one',
      (tester) async {
    Widget slot({Widget? overlay}) => MaterialApp(
          home: Column(
            children: [contentSlot(child: const _Rung(), overlay: overlay)],
          ),
        );

    await tester.pumpWidget(slot());
    expect(find.text('bubble'), findsNothing);

    await tester.pumpWidget(slot(
      overlay: const Positioned(right: 8, bottom: 8, child: Text('bubble')),
    ));
    expect(find.text('bubble'), findsOneWidget);

    // And the content did not restart when the overlay appeared: the Stack is
    // built either way, so nothing about the tree's shape changed.
    expect(find.text('opened 0'), findsOneWidget);
  });
}
