import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'models/exercise_frame_result.dart';

/// Contract for exercise-specific logic that consumes pose frames.
///
/// Implementations are intended to be stateful per workout session.
abstract class ExerciseCalculator {
  /// Clears internal state (rep count, stage history, etc.).
  void reset();

  /// Updates calculator state using a new [pose] frame.
  ///
  /// Returns `null` when the pose is insufficient for calculation.
  ExerciseFrameResult? update({
    required Pose pose,
    required DateTime timestamp,

    /// Manual control signals (e.g. from UI buttons).
    ///
    /// When [autoSetLifecycle] is false, callers should drive the set lifecycle
    /// via these signals.
    bool startCountdown = false,
    bool startSet = false,
    bool endSet = false,

    /// Whether the calculator should start/end sets automatically based on
    /// pose-derived predicates.
    bool autoSetLifecycle = true,

    /// Whether the calculator should end sets automatically based on
    /// pose-derived predicates.
    ///
    /// Useful when you want manual start but automatic end.
    bool autoEndSetLifecycle = true,
  });
}
