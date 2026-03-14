// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_ai_workout_coach/app/app.dart';

void main() {
  testWidgets('Can navigate between Workout and Log',
      (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Workout'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ready. Tap Start to begin.'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('Phase'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Workout Log'),
      ),
      findsOneWidget,
    );
    expect(find.text('Workout log (WIP)'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    await tester.pumpAndSettle();
    expect(find.text('Ready. Tap Start to begin.'), findsOneWidget);
  });
}
