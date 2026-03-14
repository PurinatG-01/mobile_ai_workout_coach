import 'package:flutter/material.dart';

import '../features/live_record_exercise/screens/workout_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Workout Coach',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const WorkoutScreen(),
    );
  }
}
