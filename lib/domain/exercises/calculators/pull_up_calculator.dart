import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

class PullUpCalculator implements ExerciseCalculator {
  PullUpCalculator({
    SetLifecycleController? lifecycle,
  }) : _lifecycle = lifecycle ?? SetLifecycleController();

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;
  final SetLifecycleController _lifecycle;

  static const _requiredLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightWrist,
  };

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _lifecycle.reset();
  }

  bool _isPreparePose(Pose pose) {
    for (final t in _requiredLandmarks) {
      if (!pose.landmarks.containsKey(t)) return false;
    }
    return true;
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
    final isPreparePose = _isPreparePose(pose);
    final isBreakPose = !isPreparePose;
    final lifecycleEvent = _lifecycle.tick(
      isPreparePose: isPreparePose,
      isBreakPose: isBreakPose,
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

    // TODO: implement pull-up rep counting using shoulder/elbow + vertical movement.
    return ExerciseFrameResult(
      reps: _reps,
      setStage: _lifecycle.stage,
      repPhase: _lifecycle.stage == ExerciseSetStage.active
          ? _repPhase
          : ExerciseRepPhase.unknown,
      metrics: ExerciseFrameMetrics(),
      timestamp: timestamp,
      countdownRemainingMs: _lifecycle.stage == ExerciseSetStage.countdown
          ? _lifecycle.countdownRemainingMsAt(timestamp)
          : null,
    );
  }
}
