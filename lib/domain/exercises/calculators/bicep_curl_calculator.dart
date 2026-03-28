import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../common/services/pose_angle_service.dart';
import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_metric.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

class BicepCurlCalculator implements ExerciseCalculator {
  BicepCurlCalculator({
    SetLifecycleController? lifecycle,
    PoseAngleService? poseAngles,
  })  : _lifecycle = lifecycle ?? SetLifecycleController(),
        _poseAngles = poseAngles ?? const PoseAngleService();

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;
  final SetLifecycleController _lifecycle;
  final PoseAngleService _poseAngles;

  bool _repArmed = false;
  double? _lastAvgElbowDeg;

  DateTime? _missingPrepareSince;
  double? _baselineWaistAngleDeg;

  static const double _extendedThresholdDeg = 160;
  static const double _curledThresholdDeg = 60;
  static const double _phaseDeltaEpsilonDeg = 1;

  // End-set "break" signal (intentional): bend down relative to start pose.
  //
  // We model this as a significant decrease in the waist/hip angle
  // (shoulder-hip-knee) compared to the set's starting posture.
  //
  // This works for both standing curls (baseline near 180°) and sitting curls
  // (baseline near ~90°), because the threshold is relative to baseline.
  static const double _breakWaistAngleDeltaDeg = 30;

  // Pose-missing break: if the pose disappears entirely (user steps away / big
  // camera shift), end the set only after a hold to avoid transient blips.
  static const Duration _breakMissingPoseHoldDuration =
      Duration(milliseconds: 1500);

  static const _requiredLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftWrist,
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
  };

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _repArmed = false;
    _lastAvgElbowDeg = null;
    _missingPrepareSince = null;
    _baselineWaistAngleDeg = null;
    _lifecycle.reset();
  }

  bool _isPreparePose(Pose pose) {
    for (final t in _requiredLandmarks) {
      if (!pose.landmarks.containsKey(t)) return false;
    }
    return true;
  }

  double? _waistAngleDegFromPose(Pose pose) {
    final left = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.leftShoulder,
      b: PoseLandmarkType.leftHip,
      c: PoseLandmarkType.leftKnee,
    );
    final right = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.rightShoulder,
      b: PoseLandmarkType.rightHip,
      c: PoseLandmarkType.rightKnee,
    );

    if (left == null && right == null) return null;
    if (left == null) return right;
    if (right == null) return left;
    return (left + right) / 2;
  }

  bool _isBreakPose({
    required Pose pose,
    required double? leftElbowDeg,
    required double? rightElbowDeg,
    required DateTime timestamp,
    required double? waistAngleDeg,
  }) {
    // If the pose disappears entirely (user steps away / big camera shift),
    // end the set only after a longer hold to avoid transient detection blips.
    if (!_isPreparePose(pose)) {
      _missingPrepareSince ??= timestamp;

      final since = _missingPrepareSince!;
      return timestamp.difference(since) >= _breakMissingPoseHoldDuration;
    }
    _missingPrepareSince = null;

    if (leftElbowDeg == null || rightElbowDeg == null) {
      return false;
    }

    final baseline = _baselineWaistAngleDeg;
    if (baseline == null || waistAngleDeg == null) return false;

    // Smaller hip angle => more flexion / more bent down.
    return waistAngleDeg <= baseline - _breakWaistAngleDeltaDeg;
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
    final metrics = ExerciseFrameMetrics();
    final waistAngleDeg = _waistAngleDegFromPose(pose);
    final leftElbowDeg = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.leftShoulder,
      b: PoseLandmarkType.leftElbow,
      c: PoseLandmarkType.leftWrist,
    );
    final rightElbowDeg = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.rightShoulder,
      b: PoseLandmarkType.rightElbow,
      c: PoseLandmarkType.rightWrist,
    );

    final isBreakPose = _isBreakPose(
      pose: pose,
      leftElbowDeg: leftElbowDeg,
      rightElbowDeg: rightElbowDeg,
      timestamp: timestamp,
      waistAngleDeg: waistAngleDeg,
    );

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

    if (lifecycleEvent.didStartSet) {
      _reps = 0;
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastAvgElbowDeg = null;
      _missingPrepareSince = null;
      _baselineWaistAngleDeg = waistAngleDeg;
    }

    if (lifecycleEvent.didEndSet) {
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastAvgElbowDeg = null;
      _missingPrepareSince = null;
      _baselineWaistAngleDeg = null;
    }

    // Capture baseline lazily if the set started without lower-body landmarks.
    if (_lifecycle.stage == ExerciseSetStage.active &&
        _baselineWaistAngleDeg == null &&
        waistAngleDeg != null) {
      _baselineWaistAngleDeg = waistAngleDeg;
    }
    if (leftElbowDeg != null) {
      metrics[ExerciseMetric.leftElbowDeg] = leftElbowDeg;
    }
    if (rightElbowDeg != null) {
      metrics[ExerciseMetric.rightElbowDeg] = rightElbowDeg;
    }

    if (_lifecycle.stage == ExerciseSetStage.active) {
      if (leftElbowDeg != null && rightElbowDeg != null) {
        final bothExtended = leftElbowDeg >= _extendedThresholdDeg &&
            rightElbowDeg >= _extendedThresholdDeg;
        final bothCurled = leftElbowDeg <= _curledThresholdDeg &&
            rightElbowDeg <= _curledThresholdDeg;

        final avgElbowDeg = (leftElbowDeg + rightElbowDeg) / 2;

        if (bothExtended) {
          _repPhase = ExerciseRepPhase.bottom;
          _repArmed = true;
        } else if (bothCurled) {
          _repPhase = ExerciseRepPhase.top;
          if (_repArmed) {
            _reps += 1;
            _repArmed = false;
          }
        } else {
          final lastAvg = _lastAvgElbowDeg;
          if (lastAvg == null) {
            _repPhase = ExerciseRepPhase.unknown;
          } else if (avgElbowDeg < lastAvg - _phaseDeltaEpsilonDeg) {
            _repPhase = ExerciseRepPhase.concentric;
          } else if (avgElbowDeg > lastAvg + _phaseDeltaEpsilonDeg) {
            _repPhase = ExerciseRepPhase.eccentric;
          }
        }

        _lastAvgElbowDeg = avgElbowDeg;
      } else {
        _repPhase = ExerciseRepPhase.unknown;
        _lastAvgElbowDeg = null;
      }
    }

    return ExerciseFrameResult(
      reps: _reps,
      setStage: _lifecycle.stage,
      repPhase: _lifecycle.stage == ExerciseSetStage.active
          ? _repPhase
          : ExerciseRepPhase.unknown,
      metrics: metrics,
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
