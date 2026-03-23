import 'exercise_frame_metrics.dart';
import 'exercise_rep_phase.dart';
import 'exercise_set_stage.dart';

/// Output of an [ExerciseCalculator] after processing one pose frame.
class ExerciseFrameResult {
  const ExerciseFrameResult({
    required this.reps,
    required this.setStage,
    required this.repPhase,
    required this.metrics,
    required this.timestamp,
    this.countdownRemainingMs,
  });

  final int reps;
  final ExerciseSetStage setStage;
  final ExerciseRepPhase repPhase;
  final ExerciseFrameMetrics metrics;
  final DateTime timestamp;

  /// Present only while [setStage] is [ExerciseSetStage.countdown].
  final int? countdownRemainingMs;
}
