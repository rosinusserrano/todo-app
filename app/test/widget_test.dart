// Widget tests run on the Dart VM with no real window, so anything touching
// window_manager is skipped here - the pin toggle calls into the platform
// channel and is verified by running the app, not by this test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/main.dart';

void main() {
  testWidgets('shell renders the title bar and always-on-top state',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProofApp());

    expect(find.text('Todo Widget'), findsOneWidget);
    expect(find.text('Always on top: ON'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });
}
