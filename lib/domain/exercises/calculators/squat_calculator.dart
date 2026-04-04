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

enum _KneeZone { top, mid, bottom }

/// Squat rep/phase calculator optimised for a side-camera setup.
///
/// The set lifecycle is driven entirely by button signals — no automatic
/// start, end, or interruption based on pose. When landmarks are missing,
/// all rep/phase state is preserved until they return.
///
/// Mid-zone phase (eccentric/concentric) is derived from the last confirmed
/// extreme zone (top/bottom), not from a frame-to-frame delta, so it is
/// stable under landmark jitter.
class SquatCalculator implements ExerciseCalculator {
  SquatCalculator({
    SetLifecycleController? lifecycle,
    PoseAngleService? poseAngles,
  })  : _lifecycle = lifecycle ?? SetLifecycleController(),
        _poseAngles = poseAngles ?? const PoseAngleService();

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;
  final SetLifecycleController _lifecycle;
  final PoseAngleService _poseAngles;

  bool _hasReachedBottomInThisRep = false;
  Set<PoseLandmarkType>? _lockedLegLandmarks;
  _KneeZone _kneeZone = _KneeZone.mid;

  /// Last confirmed extreme zone (top or bottom).
  /// Mid-zone phase is read from this rather than a frame-to-frame delta.
  ExerciseRepPhase _lastConfirmedZone = ExerciseRepPhase.unknown;

  static const double _kneeTopDeg = 165;
  static const double _kneeBottomDeg = 120;
  static const double _kneeTopExitDeg = 160;
  static const double _kneeBottomExitDeg = 125;

  static const _leftLegLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
  };

  static const _rightLegLandmarks = <PoseLandmarkType>{
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
  };

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
    _lockedLegLandmarks = null;
    _lifecycle.reset();
  }

  void _resetRepTracking() {
    _repPhase = ExerciseRepPhase.unknown;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
  }

  bool _hasLegChain(Pose pose, Set<PoseLandmarkType> landmarks) {
    final chain = _legChainFor(landmarks);
    return pose.landmarks[chain.hip] != null &&
        pose.landmarks[chain.knee] != null &&
        pose.landmarks[chain.ankle] != null;
  }

  ({PoseLandmarkType hip, PoseLandmarkType knee, PoseLandmarkType ankle})
      _legChainFor(Set<PoseLandmarkType> landmarks) {
    if (landmarks.contains(PoseLandmarkType.leftHip)) {
      return (
        hip: PoseLandmarkType.leftHip,
        knee: PoseLandmarkType.leftKnee,
        ankle: PoseLandmarkType.leftAnkle,
      );
    }
    return (
      hip: PoseLandmarkType.rightHip,
      knee: PoseLandmarkType.rightKnee,
      ankle: PoseLandmarkType.rightAnkle,
    );
  }

  Set<PoseLandmarkType>? _selectBestLeg(Pose pose) {
    final left = _legChainFor(_leftLegLandmarks);
    final right = _legChainFor(_rightLegLandmarks);

    final lh = pose.landmarks[left.hip];
    final lk = pose.landmarks[left.knee];
    final la = pose.landmarks[left.ankle];
    final rh = pose.landmarks[right.hip];
    final rk = pose.landmarks[right.knee];
    final ra = pose.landmarks[right.ankle];

    final hasLeft = lh != null && lk != null && la != null;
    final hasRight = rh != null && rk != null && ra != null;

    if (!hasLeft && !hasRight) return null;
    if (hasLeft && !hasRight) return _leftLegLandmarks;
    if (!hasLeft) return _rightLegLandmarks;

    double seg(PoseLandmark? a, PoseLandmark? b) {
      if (a == null || b == null) return 0;
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final leftScore = seg(lh, lk) + seg(lk, la);
    final rightScore = seg(rh, rk) + seg(rk, ra);
    return leftScore >= rightScore ? _leftLegLandmarks : _rightLegLandmarks;
  }

  double? _kneeDegFor(Pose pose, Set<PoseLandmarkType> leg) {
    final chain = _legChainFor(leg);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: chain.hip,
      b: chain.knee,
      c: chain.ankle,
    );
  }

  void _updatePhaseAndReps({required double kneeDeg}) {
    // Zone transitions with hysteresis.
    switch (_kneeZone) {
      case _KneeZone.top:
        if (kneeDeg < _kneeTopExitDeg) _kneeZone = _KneeZone.mid;
      case _KneeZone.bottom:
        if (kneeDeg > _kneeBottomExitDeg) _kneeZone = _KneeZone.mid;
      case _KneeZone.mid:
        if (kneeDeg >= _kneeTopDeg) {
          _kneeZone = _KneeZone.top;
        } else if (kneeDeg <= _kneeBottomDeg) {
          _kneeZone = _KneeZone.bottom;
        }
    }

    // Confirm extreme zones and count reps.
    switch (_kneeZone) {
      case _KneeZone.top:
        _lastConfirmedZone = ExerciseRepPhase.top;
        _repPhase = ExerciseRepPhase.top;
        if (_hasReachedBottomInThisRep) {
          _reps += 1;
          _hasReachedBottomInThisRep = false;
        }
      case _KneeZone.bottom:
        _lastConfirmedZone = ExerciseRepPhase.bottom;
        _repPhase = ExerciseRepPhase.bottom;
        _hasReachedBottomInThisRep = true;
      case _KneeZone.mid:
        // Mid-zone direction comes from the last confirmed extreme, not a delta.
        // bottom → mid = going up = concentric
        // top → mid   = going down = eccentric
        switch (_lastConfirmedZone) {
          case ExerciseRepPhase.bottom:
            _repPhase = ExerciseRepPhase.concentric;
          case ExerciseRepPhase.top:
            _repPhase = ExerciseRepPhase.eccentric;
          case ExerciseRepPhase.unknown:
          case ExerciseRepPhase.concentric:
          case ExerciseRepPhase.eccentric:
            _repPhase = ExerciseRepPhase.unknown;
        }
    }
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
    final metrics = ExerciseFrameMetrics();
    final bestLegNow = _selectBestLeg(pose);

    final leftKneeDeg = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.leftHip,
      b: PoseLandmarkType.leftKnee,
      c: PoseLandmarkType.leftAnkle,
    );
    final rightKneeDeg = _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.rightHip,
      b: PoseLandmarkType.rightKnee,
      c: PoseLandmarkType.rightAnkle,
    );
    if (leftKneeDeg != null) metrics[ExerciseMetric.leftKneeDeg] = leftKneeDeg;
    if (rightKneeDeg != null) metrics[ExerciseMetric.rightKneeDeg] = rightKneeDeg;

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
      _lockedLegLandmarks = bestLegNow;
    }

    if (_lifecycle.stage == ExerciseSetStage.active) {
      // Prefer locked leg while still visible; fall back to best visible leg.
      final activeLeg = (_lockedLegLandmarks != null &&
              _hasLegChain(pose, _lockedLegLandmarks!))
          ? _lockedLegLandmarks
          : bestLegNow;

      // Lock lazily if set started before any leg was visible.
      if (_lockedLegLandmarks == null && activeLeg != null) {
        _lockedLegLandmarks = activeLeg;
      }

      final activeKneeDeg = activeLeg == null ? null : _kneeDegFor(pose, activeLeg);

      // When landmarks are missing, skip this frame — state is preserved.
      if (activeKneeDeg != null) {
        _updatePhaseAndReps(kneeDeg: activeKneeDeg);
      }
    }

    if (lifecycleEvent.didEndSet) {
      _resetRepTracking();
      _lockedLegLandmarks = null;
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
