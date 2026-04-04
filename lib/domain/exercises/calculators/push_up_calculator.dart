import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../common/services/pose_angle_service.dart';
import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_metric.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

enum _ElbowZone { top, mid, bottom }

enum _ElbowTrend { unknown, goingDown, goingUp }

/// Push-up rep/phase calculator.
///
/// The set lifecycle is driven entirely by button signals — no automatic
/// start, end, or interruption based on pose. When landmarks are missing,
/// all rep/phase state is preserved until they return.
///
/// Rep counting: bottom (elbow ≤ 90°) → top (elbow ≥ 160°) = one rep.
class PushUpCalculator implements ExerciseCalculator {
  PushUpCalculator({
    SetLifecycleController? lifecycle,
    PoseAngleService? poseAngles,
  })  : _lifecycle = lifecycle ?? SetLifecycleController(),
        _poseAngles = poseAngles ?? const PoseAngleService();

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;
  final SetLifecycleController _lifecycle;
  final PoseAngleService _poseAngles;

  double? _prevActiveElbowDeg;
  bool _hasReachedBottomInThisRep = false;
  Set<PoseLandmarkType>? _lockedArmLandmarks;

  _ElbowZone _elbowZone = _ElbowZone.mid;
  _ElbowTrend _elbowTrend = _ElbowTrend.unknown;

  static const double _elbowTopDeg = 160;
  static const double _elbowTopExitDeg = 155;
  static const double _elbowBottomDeg = 90;
  static const double _elbowBottomExitDeg = 95;
  static const double _elbowDeltaDeadbandDeg = 2;

  static const _leftArmLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftWrist,
  };

  static const _rightArmLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
  };

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _prevActiveElbowDeg = null;
    _hasReachedBottomInThisRep = false;
    _lockedArmLandmarks = null;
    _elbowZone = _ElbowZone.mid;
    _elbowTrend = _ElbowTrend.unknown;
    _lifecycle.reset();
  }

  ({
    PoseLandmarkType shoulder,
    PoseLandmarkType elbow,
    PoseLandmarkType wrist,
  }) _armChainFor(Set<PoseLandmarkType> landmarks) {
    if (landmarks.contains(PoseLandmarkType.leftShoulder)) {
      return (
        shoulder: PoseLandmarkType.leftShoulder,
        elbow: PoseLandmarkType.leftElbow,
        wrist: PoseLandmarkType.leftWrist,
      );
    }
    return (
      shoulder: PoseLandmarkType.rightShoulder,
      elbow: PoseLandmarkType.rightElbow,
      wrist: PoseLandmarkType.rightWrist,
    );
  }

  bool _hasArmChain(Pose pose, Set<PoseLandmarkType> landmarks) {
    final c = _armChainFor(landmarks);
    return pose.landmarks[c.shoulder] != null &&
        pose.landmarks[c.elbow] != null &&
        pose.landmarks[c.wrist] != null;
  }

  Set<PoseLandmarkType>? _selectBestArm(Pose pose) {
    final lc = _armChainFor(_leftArmLandmarks);
    final rc = _armChainFor(_rightArmLandmarks);

    final ls = pose.landmarks[lc.shoulder];
    final le = pose.landmarks[lc.elbow];
    final lw = pose.landmarks[lc.wrist];
    final rs = pose.landmarks[rc.shoulder];
    final re = pose.landmarks[rc.elbow];
    final rw = pose.landmarks[rc.wrist];

    final hasLeft = ls != null && le != null && lw != null;
    final hasRight = rs != null && re != null && rw != null;

    if (!hasLeft && !hasRight) return null;
    if (hasLeft && !hasRight) return _leftArmLandmarks;
    if (!hasLeft) return _rightArmLandmarks;

    double seg(PoseLandmark? a, PoseLandmark? b) {
      if (a == null || b == null) return 0;
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final leftScore = seg(ls, le) + seg(le, lw);
    final rightScore = seg(rs, re) + seg(re, rw);

    return leftScore >= rightScore ? _leftArmLandmarks : _rightArmLandmarks;
  }

  double? _elbowDegForArm(Pose pose, Set<PoseLandmarkType> landmarks) {
    final chain = _armChainFor(landmarks);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: chain.shoulder,
      b: chain.elbow,
      c: chain.wrist,
    );
  }

  void _resetRepTracking() {
    _repPhase = ExerciseRepPhase.unknown;
    _prevActiveElbowDeg = null;
    _hasReachedBottomInThisRep = false;
    _elbowZone = _ElbowZone.mid;
    _elbowTrend = _ElbowTrend.unknown;
  }

  void _updatePhaseAndReps({required double elbowDeg}) {
    final prev = _prevActiveElbowDeg;
    final delta = prev == null ? null : elbowDeg - prev;
    final prevZone = _elbowZone;

    switch (_elbowZone) {
      case _ElbowZone.top:
        if (elbowDeg < _elbowTopExitDeg) {
          _elbowZone = _ElbowZone.mid;
          if (elbowDeg <= _elbowBottomDeg) _elbowZone = _ElbowZone.bottom;
        }
      case _ElbowZone.bottom:
        if (elbowDeg > _elbowBottomExitDeg) {
          _elbowZone = _ElbowZone.mid;
          if (elbowDeg >= _elbowTopDeg) _elbowZone = _ElbowZone.top;
        }
      case _ElbowZone.mid:
        if (elbowDeg >= _elbowTopDeg) {
          _elbowZone = _ElbowZone.top;
        } else if (elbowDeg <= _elbowBottomDeg) {
          _elbowZone = _ElbowZone.bottom;
        }
    }

    if (prevZone != _elbowZone) {
      if (prevZone == _ElbowZone.top && _elbowZone == _ElbowZone.mid) {
        _elbowTrend = _ElbowTrend.goingDown;
      } else if (prevZone == _ElbowZone.bottom && _elbowZone == _ElbowZone.mid) {
        _elbowTrend = _ElbowTrend.goingUp;
      }
    }

    if (_elbowZone == _ElbowZone.mid &&
        delta != null &&
        delta.abs() >= _elbowDeltaDeadbandDeg) {
      _elbowTrend = delta > 0 ? _ElbowTrend.goingUp : _ElbowTrend.goingDown;
    }

    if (_elbowZone == _ElbowZone.bottom) {
      _hasReachedBottomInThisRep = true;
    }
    if (_elbowZone == _ElbowZone.top && _hasReachedBottomInThisRep) {
      _reps += 1;
      _hasReachedBottomInThisRep = false;
    }

    if (_elbowZone == _ElbowZone.top) {
      _repPhase = ExerciseRepPhase.top;
    } else if (_elbowZone == _ElbowZone.bottom) {
      _repPhase = ExerciseRepPhase.bottom;
    } else {
      switch (_elbowTrend) {
        case _ElbowTrend.goingUp:
          _repPhase = ExerciseRepPhase.concentric;
        case _ElbowTrend.goingDown:
          _repPhase = ExerciseRepPhase.eccentric;
        case _ElbowTrend.unknown:
          _repPhase = ExerciseRepPhase.unknown;
      }
    }

    _prevActiveElbowDeg = elbowDeg;
  }

  double? _leftElbowDeg(Pose pose) => _poseAngles.angleDegreesFromPose(
        pose: pose,
        a: PoseLandmarkType.leftShoulder,
        b: PoseLandmarkType.leftElbow,
        c: PoseLandmarkType.leftWrist,
      );

  double? _rightElbowDeg(Pose pose) => _poseAngles.angleDegreesFromPose(
        pose: pose,
        a: PoseLandmarkType.rightShoulder,
        b: PoseLandmarkType.rightElbow,
        c: PoseLandmarkType.rightWrist,
      );

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
    final metrics = ExerciseFrameMetrics();
    final leftE = _leftElbowDeg(pose);
    final rightE = _rightElbowDeg(pose);
    if (leftE != null) metrics[ExerciseMetric.leftElbowDeg] = leftE;
    if (rightE != null) metrics[ExerciseMetric.rightElbowDeg] = rightE;

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

    if (lifecycleEvent.didStartSet) {
      _resetRepTracking();
      _lockedArmLandmarks = _selectBestArm(pose);
    }

    if (_lifecycle.stage == ExerciseSetStage.active) {
      final bestArmNow = _selectBestArm(pose);

      // Prefer locked arm while still visible; fall back to best visible arm.
      final activeArm = (_lockedArmLandmarks != null &&
              _hasArmChain(pose, _lockedArmLandmarks!))
          ? _lockedArmLandmarks
          : bestArmNow;

      // Lock lazily if set started before any arm was visible.
      if (_lockedArmLandmarks == null && activeArm != null) {
        _lockedArmLandmarks = activeArm;
      }

      final activeElbowDeg =
          activeArm == null ? null : _elbowDegForArm(pose, activeArm);

      // When landmarks are missing, skip this frame — state is preserved.
      if (activeElbowDeg != null) {
        _updatePhaseAndReps(elbowDeg: activeElbowDeg);
      }
    }

    if (lifecycleEvent.didEndSet) {
      _resetRepTracking();
      _lockedArmLandmarks = null;
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
