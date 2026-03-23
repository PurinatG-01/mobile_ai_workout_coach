import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'dart:math' as math;

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

  DateTime? _relaxedBreakCandidateSince;
  DateTime? _missingPrepareSince;

  static const double _extendedThresholdDeg = 160;
  static const double _curledThresholdDeg = 60;
  static const double _phaseDeltaEpsilonDeg = 1;

  // End-set "break" signal (intentional): raise both hands above shoulders.
  // This must be distinct from any rep position so slow reps don't end the set.
  static const double _breakHandsUpMinLiftUpperArmRatio = 0.6;
  static const double _breakMinElbowExtendedDeg = 120;

  // Natural break: arms relaxed down (e.g. after dropping the weight).
  // We require this posture to be held for a bit to avoid ending sets during
  // slow reps or brief pauses.
  static const Duration _breakRelaxedHoldDuration =
      Duration(milliseconds: 1500);
  static const double _breakRelaxedMinElbowExtendedDeg = 160;

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
    _relaxedBreakCandidateSince = null;
    _missingPrepareSince = null;
    _lifecycle.reset();
  }

  bool _isPreparePose(Pose pose) {
    for (final t in _requiredLandmarks) {
      if (!pose.landmarks.containsKey(t)) return false;
    }
    return true;
  }

  double _dist(PoseLandmark a, PoseLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _isBreakPose({
    required Pose pose,
    required double? leftElbowDeg,
    required double? rightElbowDeg,
    required DateTime timestamp,
  }) {
    // If the pose disappears entirely (user steps away / big camera shift),
    // end the set only after a longer hold to avoid transient detection blips.
    if (!_isPreparePose(pose)) {
      _missingPrepareSince ??= timestamp;
      _relaxedBreakCandidateSince = null;

      final since = _missingPrepareSince!;
      return timestamp.difference(since) >= _breakRelaxedHoldDuration;
    }
    _missingPrepareSince = null;

    if (leftElbowDeg == null || rightElbowDeg == null) {
      _relaxedBreakCandidateSince = null;
      return false;
    }

    final ls = pose.landmarks[PoseLandmarkType.leftShoulder]!;
    final le = pose.landmarks[PoseLandmarkType.leftElbow]!;
    final lw = pose.landmarks[PoseLandmarkType.leftWrist]!;
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder]!;
    final re = pose.landmarks[PoseLandmarkType.rightElbow]!;
    final rw = pose.landmarks[PoseLandmarkType.rightWrist]!;

    // 1) Explicit break gesture: both hands above shoulders.
    if (leftElbowDeg >= _breakMinElbowExtendedDeg &&
        rightElbowDeg >= _breakMinElbowExtendedDeg) {
      // ML Kit coordinates are image-space; y increases downward.
      // "Hands up" => wrist is above shoulder => (shoulder.y - wrist.y) positive.
      final leftUpperArmLen = _dist(ls, le);
      final rightUpperArmLen = _dist(rs, re);
      if (leftUpperArmLen > 0 && rightUpperArmLen > 0) {
        final leftLift = ls.y - lw.y;
        final rightLift = rs.y - rw.y;
        final leftHandsUp =
            leftLift >= _breakHandsUpMinLiftUpperArmRatio * leftUpperArmLen;
        final rightHandsUp =
            rightLift >= _breakHandsUpMinLiftUpperArmRatio * rightUpperArmLen;
        if (leftHandsUp && rightHandsUp) {
          _relaxedBreakCandidateSince = null;
          return true;
        }
      }
    }

    // 2) Natural break: relaxed arms down, held for a while.
    final elbowsExtendedEnough =
        leftElbowDeg >= _breakRelaxedMinElbowExtendedDeg &&
            rightElbowDeg >= _breakRelaxedMinElbowExtendedDeg;
    final wristsBelowElbows = lw.y > le.y && rw.y > re.y;
    final elbowsBelowShoulders = le.y > ls.y && re.y > rs.y;
    final relaxedArmsDown =
        elbowsExtendedEnough && wristsBelowElbows && elbowsBelowShoulders;

    if (!relaxedArmsDown) {
      _relaxedBreakCandidateSince = null;
      return false;
    }

    _relaxedBreakCandidateSince ??= timestamp;
    final since = _relaxedBreakCandidateSince!;
    return timestamp.difference(since) >= _breakRelaxedHoldDuration;
  }

  @override
  ExerciseFrameResult? update({
    required Pose pose,
    required DateTime timestamp,
    bool startSet = false,
    bool endSet = false,
    bool autoSetLifecycle = true,
  }) {
    final isPreparePose = _isPreparePose(pose);
    final metrics = ExerciseFrameMetrics();
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
    );

    final lifecycleEvent = _lifecycle.tick(
      isPreparePose: isPreparePose,
      isBreakPose: isBreakPose,
      timestamp: timestamp,
      startSignal: startSet,
      endSignal: endSet,
      autoStart: autoSetLifecycle,
      autoEnd: autoSetLifecycle,
    );

    if (lifecycleEvent.didStartSet) {
      _reps = 0;
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastAvgElbowDeg = null;
      _relaxedBreakCandidateSince = null;
      _missingPrepareSince = null;
    }

    if (lifecycleEvent.didEndSet) {
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastAvgElbowDeg = null;
      _relaxedBreakCandidateSince = null;
      _missingPrepareSince = null;
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
      countdownRemainingMs: _lifecycle.stage == ExerciseSetStage.countdown
          ? _lifecycle.countdownRemainingMsAt(timestamp)
          : null,
    );
  }
}
