import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

/// Pull-up rep/phase calculator.
///
/// The set lifecycle is driven entirely by button signals — no automatic
/// start, end, or interruption based on pose.
///
// TODO(dev): implement rep counting using shoulder/elbow vertical movement.
class PullUpCalculator implements ExerciseCalculator {
  PullUpCalculator({
    SetLifecycleController? lifecycle,
  }) : _lifecycle = lifecycle ?? SetLifecycleController();

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;
  final SetLifecycleController _lifecycle;

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _lifecycle.reset();
  }

  @override
  ExerciseFrameResult? update({
    required Pose pose,
    required DateTime timestamp,
    bool startCountdown = false,
    bool startSet = false,
    bool endSet = false,
    bool autoSetLifecycle = true,
    bool autoEndSetLifecycle = true,
  }) {
    // Lifecycle is driven purely by button signals — pose never interrupts.
    final lifecycleEvent = _lifecycle.tick(
      isPreparePose: true,
      isBreakPose: false,
      timestamp: timestamp,
      startCountdownSignal: startCountdown,
      startSignal: startSet,
      endSignal: endSet,
      autoStart: autoSetLifecycle,
      autoEnd: autoEndSetLifecycle,
    );

    if (lifecycleEvent.didEndSet) {
      _repPhase = ExerciseRepPhase.unknown;
    }

    return ExerciseFrameResult(
      reps: _reps,
      setStage: _lifecycle.stage,
      repPhase: _lifecycle.stage == ExerciseSetStage.active
          ? _repPhase
          : ExerciseRepPhase.unknown,
      metrics: ExerciseFrameMetrics(),
      timestamp: timestamp,
      didStartSet: lifecycleEvent.didStartSet,
      didEndSet: lifecycleEvent.didEndSet,
      didEndSetByBreakPose: lifecycleEvent.didEndSetByBreakPose,
      countdownRemainingMs: _lifecycle.stage == ExerciseSetStage.countdown
          ? _lifecycle.countdownRemainingMsAt(timestamp)
          : null,
    );
  }
}
