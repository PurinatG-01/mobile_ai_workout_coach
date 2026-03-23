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
  });
}
