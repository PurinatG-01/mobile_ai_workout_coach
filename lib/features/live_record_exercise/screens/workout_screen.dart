import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/exercise_type.dart';
import '../../../app/router.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  ExerciseType _exercise = ExerciseType.squat;
  bool _isRunning = false;

  Future<void> _startWorkoutAndOpenCamera() async {
    if (_isRunning) return;
    setState(() => _isRunning = true);

    // Push onto the root navigator so the live camera experience is truly
    // full-screen (no AppShell app bar/bottom nav).
    await context.push(AppRoutes.liveCamera);

    // If the user backs out without stopping,
    // keep the state consistent and stop recording.
    if (!mounted) return;
    if (_isRunning) {
      _stopWorkout();
    }
  }

  void _stopWorkout() {
    setState(() => _isRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ExerciseType>(
                    value: _exercise,
                    decoration: const InputDecoration(
                      labelText: 'Exercise',
                      border: OutlineInputBorder(),
                    ),
                    items: ExerciseType.values
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _exercise = value);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Start control lives in the center of the screen.
            Expanded(
              child: Center(
                child: FilledButton(
                  onPressed: _isRunning ? null : _startWorkoutAndOpenCamera,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    fixedSize: const Size(120, 120),
                  ),
                  child: const Text('START'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
