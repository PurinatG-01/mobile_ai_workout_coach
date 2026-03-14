import 'package:flutter/material.dart';

import '../../../shared/models/exercise_type.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  ExerciseType _exercise = ExerciseType.squat;
  bool _isRunning = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
      ),
      body: SafeArea(
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
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isRunning
                        ? null
                        : () {
                            setState(() => _isRunning = true);
                          },
                    child: const Text('Start'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isRunning
                        ? () {
                            setState(() => _isRunning = false);
                          }
                        : null,
                    child: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isRunning
                        ? 'Camera preview (next)'
                        : 'Ready. Tap Start to begin.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Reps',
                      value: '0',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Phase',
                      value: '—',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Tempo',
                      value: '—',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}
