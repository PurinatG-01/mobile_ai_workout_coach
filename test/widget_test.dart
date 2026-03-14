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
  testWidgets('Workout screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Ready. Tap Start to begin.'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('Phase'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);
  });
}
