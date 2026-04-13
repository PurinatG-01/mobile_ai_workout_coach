import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class WorkoutStats extends StatelessWidget {
  const WorkoutStats({
    super.key,
    this.reps = '0',
    this.exerciseStage = '—',
    this.setStage = '—',
    this.exerciseStageColor,
  });

  final String reps;
  final String exerciseStage;
  final String setStage;
  final Color? exerciseStageColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(title: 'Reps', value: reps),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: _StatCard(
            title: 'Phase',
            value: exerciseStage,
            valueColor: exerciseStageColor,
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: _StatCard(title: 'Set', value: setStage),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.valueColor,
  });

  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.bgOverlay80,
        border: Border(
          top: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: valueColor ?? AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
