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
    this.didStartSet = false,
    this.didEndSet = false,
    this.didEndSetByBreakPose = false,
    this.countdownRemainingMs,
  });

  final int reps;
  final ExerciseSetStage setStage;
  final ExerciseRepPhase repPhase;
  final ExerciseFrameMetrics metrics;
  final DateTime timestamp;

  /// True only on the frame that transitions into an active set.
  final bool didStartSet;

  /// True only on the frame that transitions back to rest.
  final bool didEndSet;

  /// If [didEndSet] is true, indicates the end was triggered automatically by
  /// a break pose (as opposed to a manual end signal).
  final bool didEndSetByBreakPose;

  /// Present only while [setStage] is [ExerciseSetStage.countdown].
  final int? countdownRemainingMs;
}
