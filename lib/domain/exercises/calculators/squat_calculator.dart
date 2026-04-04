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

enum _KneeZone {
  top,
  mid,
  bottom,
}

enum _KneeTrend {
  unknown,
  goingDown,
  goingUp,
}

/// Squat rep/phase calculator optimized for a side-camera setup.
///
/// Design goals:
/// - **Robustness to occlusion**: side view often yields only one reliable leg.
/// - **Stable phases under jitter**: avoid top/bottom flicker due to landmark noise.
/// - **Avoid set-end at squat bottom**: break pose is defined only as "no leg".
/// - **Avoid left/right switching jitter while active**: lock a leg for the set.
///
/// High-level logic:
/// 1) Pick a "best" visible leg each frame for *prepare/break* decisions.
/// 2) When the set becomes `active`, lock the chosen leg to drive rep detection.
/// 3) If the locked leg disappears, fall back to the current best visible leg.
/// 4) Use knee angle thresholds + hysteresis to classify zones (top/mid/bottom).
/// 5) In mid-zone, classify eccentric/concentric via a deadbanded trend signal.
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

  /// Previous knee angle used by rep detection (only meaningful during `active`).
  double? _prevActiveKneeDeg;

  /// True once we have reached bottom at least once in the current rep.
  ///
  /// A rep is counted when we later return to top.
  bool _hasReachedBottomInThisRep = false;

  /// When a set is active, keep using the same leg to avoid jittery switching
  /// between left/right when both are visible.
  Set<PoseLandmarkType>? _lockedLegLandmarks;

  /// Knee zone (top/mid/bottom) with hysteresis.
  _KneeZone _kneeZone = _KneeZone.mid;

  /// Knee motion trend used to classify eccentric vs concentric while in mid.
  _KneeTrend _kneeTrend = _KneeTrend.unknown;

  /// Absolute knee angle threshold for standing/top (degrees).
  static const double _kneeTopDeg = 165;

  /// Absolute knee angle threshold for bottom (degrees).
  static const double _kneeBottomDeg = 120;

  /// Hysteresis thresholds to reduce flicker around boundaries.
  ///
  /// - While in `top`, we stay `top` until knee angle drops below `_kneeTopExitDeg`.
  /// - While in `bottom`, we stay `bottom` until knee angle rises above
  ///   `_kneeBottomExitDeg`.
  static const double _kneeTopExitDeg = 160;
  static const double _kneeBottomExitDeg = 125;

  /// Movement direction deadband (degrees) to ignore small jitter.
  static const double _kneeDeltaDeadbandDeg = 2;

  /// Landmark sets representing a complete hip->knee->ankle chain.
  ///
  /// Side camera note: often only one leg is reliably detected. We treat either
  /// complete chain as sufficient.
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
    _prevActiveKneeDeg = null;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _kneeTrend = _KneeTrend.unknown;
    _lockedLegLandmarks = null;
    _lifecycle.reset();
  }

  /// Returns true if [pose] contains the hip/knee/ankle chain described by
  /// [landmarks].
  bool _hasLegChain(Pose pose, Set<PoseLandmarkType> landmarks) {
    final chain = _legChainForLandmarks(landmarks);
    return pose.landmarks[chain.hip] != null &&
        pose.landmarks[chain.knee] != null &&
        pose.landmarks[chain.ankle] != null;
  }

  /// Converts a landmark set (left/right) into the concrete (hip,knee,ankle)
  /// landmark types.
  ({PoseLandmarkType hip, PoseLandmarkType knee, PoseLandmarkType ankle})
      _legChainForLandmarks(Set<PoseLandmarkType> landmarks) {
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

  /// Picks the leg that is most likely to be reliably detected.
  ///
  /// For side-camera workouts, one leg is often partially occluded.
  /// We select the leg with the larger detected segment length
  /// (hip->knee + knee->ankle) as a proxy for visibility.
  Set<PoseLandmarkType>? _selectBestLeg(Pose pose) {
    final left = _legChainForLandmarks(_leftLegLandmarks);
    final right = _legChainForLandmarks(_rightLegLandmarks);

    final leftHip = pose.landmarks[left.hip];
    final leftKnee = pose.landmarks[left.knee];
    final leftAnkle = pose.landmarks[left.ankle];

    final rightHip = pose.landmarks[right.hip];
    final rightKnee = pose.landmarks[right.knee];
    final rightAnkle = pose.landmarks[right.ankle];

    final hasLeft = leftHip != null && leftKnee != null && leftAnkle != null;
    final hasRight =
        rightHip != null && rightKnee != null && rightAnkle != null;

    if (!hasLeft && !hasRight) {
      return null;
    }
    if (hasLeft && !hasRight) {
      return _leftLegLandmarks;
    }
    if (!hasLeft && hasRight) {
      return _rightLegLandmarks;
    }

    double segmentLength(PoseLandmark a, PoseLandmark b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final leftScore = segmentLength(leftHip!, leftKnee!) +
        segmentLength(leftKnee, leftAnkle!);
    final rightScore = segmentLength(rightHip!, rightKnee!) +
        segmentLength(rightKnee, rightAnkle!);

    return leftScore >= rightScore ? _leftLegLandmarks : _rightLegLandmarks;
  }

  double? _kneeDegForSelectedLeg(
      Pose pose, Set<PoseLandmarkType> legLandmarks) {
    final chain = _legChainForLandmarks(legLandmarks);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: chain.hip,
      b: chain.knee,
      c: chain.ankle,
    );
  }

void _resetRepTracking() {
    _repPhase = ExerciseRepPhase.unknown;
    _prevActiveKneeDeg = null;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _kneeTrend = _KneeTrend.unknown;
  }

  /// Updates phase (top/mid/bottom + eccentric/concentric) and increments reps.
  ///
  /// Rep counting:
  /// - Mark bottom once we enter `bottom` zone.
  /// - Count one rep the first time we reach `top` after that bottom.
  ///
  /// Phase stability:
  /// - Use hysteresis for zone edges.
  /// - In `mid`, use a deadbanded trend signal to resist jitter.
  void _updatePhaseAndReps({required double selectedKneeDeg}) {
    final prev = _prevActiveKneeDeg;
    final delta = prev == null ? null : selectedKneeDeg - prev;

    final prevZone = _kneeZone;

    // Update knee zone with hysteresis.
    switch (_kneeZone) {
      case _KneeZone.top:
        if (selectedKneeDeg < _kneeTopExitDeg) {
          _kneeZone = _KneeZone.mid;
        }
        break;
      case _KneeZone.bottom:
        if (selectedKneeDeg > _kneeBottomExitDeg) {
          _kneeZone = _KneeZone.mid;
        }
        break;
      case _KneeZone.mid:
        if (selectedKneeDeg >= _kneeTopDeg) {
          _kneeZone = _KneeZone.top;
        } else if (selectedKneeDeg <= _kneeBottomDeg) {
          _kneeZone = _KneeZone.bottom;
        }
        break;
    }

    // Seed a stable trend from zone transitions.
    if (prevZone != _kneeZone) {
      if (prevZone == _KneeZone.top && _kneeZone == _KneeZone.mid) {
        _kneeTrend = _KneeTrend.goingDown;
      } else if (prevZone == _KneeZone.bottom && _kneeZone == _KneeZone.mid) {
        _kneeTrend = _KneeTrend.goingUp;
      }
    }

    // Update trend from delta only when it's confidently above deadband.
    // This allows mid-range reversals without flickering due to jitter.
    if (_kneeZone == _KneeZone.mid &&
        delta != null &&
        delta.abs() >= _kneeDeltaDeadbandDeg) {
      _kneeTrend = delta > 0 ? _KneeTrend.goingUp : _KneeTrend.goingDown;
    }

    // Rep bookkeeping.
    if (_kneeZone == _KneeZone.bottom) {
      _hasReachedBottomInThisRep = true;
    }
    if (_kneeZone == _KneeZone.top && _hasReachedBottomInThisRep) {
      _reps += 1;
      _hasReachedBottomInThisRep = false;
    }

    // Phase classification:
    // - `top` and `bottom` come directly from zone.
    // - In `mid`, use the current trend to decide eccentric vs concentric.
    if (_kneeZone == _KneeZone.top) {
      _repPhase = ExerciseRepPhase.top;
    } else if (_kneeZone == _KneeZone.bottom) {
      _repPhase = ExerciseRepPhase.bottom;
    } else {
      switch (_kneeTrend) {
        case _KneeTrend.goingUp:
          _repPhase = ExerciseRepPhase.concentric;
          break;
        case _KneeTrend.goingDown:
          _repPhase = ExerciseRepPhase.eccentric;
          break;
        case _KneeTrend.unknown:
          _repPhase = ExerciseRepPhase.unknown;
          break;
      }
    }

    _prevActiveKneeDeg = selectedKneeDeg;
  }

  double? _leftKneeDeg(Pose pose) {
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.leftHip,
      b: PoseLandmarkType.leftKnee,
      c: PoseLandmarkType.leftAnkle,
    );
  }

  double? _rightKneeDeg(Pose pose) {
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: PoseLandmarkType.rightHip,
      b: PoseLandmarkType.rightKnee,
      c: PoseLandmarkType.rightAnkle,
    );
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
    final bestLegNow = _selectBestLeg(pose);
    final metrics = ExerciseFrameMetrics();

    // Expose both knee angles (when available) for debugging/UI.
    final leftKneeDeg = _leftKneeDeg(pose);
    final rightKneeDeg = _rightKneeDeg(pose);

    if (leftKneeDeg != null) {
      metrics[ExerciseMetric.leftKneeDeg] = leftKneeDeg;
    }
    if (rightKneeDeg != null) {
      metrics[ExerciseMetric.rightKneeDeg] = rightKneeDeg;
    }

    // Never let pose state interrupt or auto-end the set — lifecycle is driven
    // purely by the start/end button signals.
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
      // Fresh set: clear rep tracking.
      _resetRepTracking();

      // Lock leg at set start to avoid switching jitter while active.
      _lockedLegLandmarks = bestLegNow;
    }

    // While active:
    // - Prefer locked leg (if its chain is still present).
    // - Otherwise fall back to the current best leg.
    final activeLeg = (_lifecycle.stage == ExerciseSetStage.active &&
            _lockedLegLandmarks != null &&
            _hasLegChain(pose, _lockedLegLandmarks!))
        ? _lockedLegLandmarks
        : bestLegNow;

    // If we became active without a lock (e.g. manual start), lock as soon as
    // we have a usable leg.
    if (_lifecycle.stage == ExerciseSetStage.active &&
        _lockedLegLandmarks == null &&
        activeLeg != null) {
      _lockedLegLandmarks = activeLeg;
    }

    final activeKneeDeg =
        activeLeg == null ? null : _kneeDegForSelectedLeg(pose, activeLeg);

    if (_lifecycle.stage == ExerciseSetStage.active && activeKneeDeg != null) {
      _updatePhaseAndReps(selectedKneeDeg: activeKneeDeg);
    }

    if (lifecycleEvent.didEndSet) {
      // Clear lock/tracking so the next set can re-select cleanly.
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
