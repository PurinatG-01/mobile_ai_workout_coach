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

/// Push-up rep/phase calculator optimised for a side-camera setup.
///
/// **Prepare pose** (gates countdown) requires full plank tension:
/// - Arms fully extended: best-arm elbow angle ≥ 160°.
/// - Legs straight: best-leg knee angle ≥ 155°.
/// - Body horizontal: torso incline (shoulder-to-hip vs. horizontal) ≤ 30°.
///
/// **Break pose** (auto-ends the set) fires when the user drops their knees
/// to the ground for rest: best-leg knee angle collapses below 130° and stays
/// there for 500 ms. This never fires at push-up bottom, where the elbow
/// collapses but the knees remain fully extended throughout.
///
/// **Rep counting**: bottom (elbow ≤ 90°) → top (elbow ≥ 160°) = one rep.
/// Phase detection mirrors [SquatCalculator]: hysteresis zones + deadbanded
/// trend signal in the mid range.
///
/// **Arm lock**: the best-visible arm at set start is locked for the duration
/// to prevent left/right jitter; falls back to the current best arm if the
/// locked arm disappears mid-set.
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

  /// Arm locked at set start; avoids switching sides during the active set.
  Set<PoseLandmarkType>? _lockedArmLandmarks;

  _ElbowZone _elbowZone = _ElbowZone.mid;
  _ElbowTrend _elbowTrend = _ElbowTrend.unknown;

  /// Timestamp when the knee angle first collapsed below [_breakKneeCollapseDeg].
  DateTime? _kneeCollapseSince;

  // ── Elbow zone thresholds ─────────────────────────────────────────────────

  static const double _elbowTopDeg = 160;
  static const double _elbowTopExitDeg = 155; // hysteresis: stay top until < 155
  static const double _elbowBottomDeg = 90;
  static const double _elbowBottomExitDeg = 95; // hysteresis: stay bottom until > 95
  static const double _elbowDeltaDeadbandDeg = 2; // ignore mid-zone jitter < 2°

  // ── Prepare-pose thresholds ───────────────────────────────────────────────

  /// Legs must be at least this straight (degrees) to count as plank tension.
  static const double _prepareLegKneeDeg = 155;

  /// Body must be at most this far from horizontal (degrees) for plank shape.
  static const double _prepareTorsoInclineDeg = 30;

  // ── Break-pose thresholds ─────────────────────────────────────────────────

  /// Knee angle below this indicates knees on the ground / resting.
  static const double _breakKneeCollapseDeg = 130;

  /// The knee must stay collapsed this long before [isBreakPose] is reported.
  static const Duration _breakKneeHoldDuration = Duration(milliseconds: 500);

  // ── Landmark sets ─────────────────────────────────────────────────────────

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

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _prevActiveElbowDeg = null;
    _hasReachedBottomInThisRep = false;
    _lockedArmLandmarks = null;
    _elbowZone = _ElbowZone.mid;
    _elbowTrend = _ElbowTrend.unknown;
    _kneeCollapseSince = null;
    _lifecycle.reset();
  }

  // ── Arm helpers ───────────────────────────────────────────────────────────

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

  /// Picks the arm with the longer visible segment (shoulder→elbow + elbow→wrist).
  ///
  /// For side-camera workouts one arm is often partially occluded. A longer
  /// combined segment length is a reliable proxy for visibility.
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

    double seg(PoseLandmark a, PoseLandmark b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final leftScore = seg(ls!, le!) + seg(le!, lw!);
    final rightScore = seg(rs!, re!) + seg(re!, rw!);

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

  // ── Leg helpers ───────────────────────────────────────────────────────────

  ({
    PoseLandmarkType hip,
    PoseLandmarkType knee,
    PoseLandmarkType ankle,
  }) _legChainFor(Set<PoseLandmarkType> landmarks) {
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

  /// Picks the leg with the longer visible segment (hip→knee + knee→ankle).
  Set<PoseLandmarkType>? _selectBestLeg(Pose pose) {
    final lc = _legChainFor(_leftLegLandmarks);
    final rc = _legChainFor(_rightLegLandmarks);

    final lh = pose.landmarks[lc.hip];
    final lk = pose.landmarks[lc.knee];
    final la = pose.landmarks[lc.ankle];
    final rh = pose.landmarks[rc.hip];
    final rk = pose.landmarks[rc.knee];
    final ra = pose.landmarks[rc.ankle];

    final hasLeft = lh != null && lk != null && la != null;
    final hasRight = rh != null && rk != null && ra != null;

    if (!hasLeft && !hasRight) return null;
    if (hasLeft && !hasRight) return _leftLegLandmarks;
    if (!hasLeft) return _rightLegLandmarks;

    double seg(PoseLandmark a, PoseLandmark b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final leftScore = seg(lh!, lk!) + seg(lk!, la!);
    final rightScore = seg(rh!, rk!) + seg(rk!, ra!);

    return leftScore >= rightScore ? _leftLegLandmarks : _rightLegLandmarks;
  }

  double? _kneeDegForLeg(Pose pose, Set<PoseLandmarkType> landmarks) {
    final chain = _legChainFor(landmarks);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: chain.hip,
      b: chain.knee,
      c: chain.ankle,
    );
  }

  // ── Torso incline ─────────────────────────────────────────────────────────

  /// Angle of the shoulder-to-hip segment relative to horizontal (degrees).
  ///
  /// - 0° = perfectly horizontal (plank).
  /// - 90° = perfectly vertical (standing).
  ///
  /// Absolute differences are used so the result is view-direction agnostic
  /// (works whether the user faces left or right).
  double? _torsoInclineDeg(Pose pose) {
    final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
    final lh = pose.landmarks[PoseLandmarkType.leftHip];
    final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rh = pose.landmarks[PoseLandmarkType.rightHip];

    double incline(PoseLandmark s, PoseLandmark h) {
      final dx = (s.x - h.x).abs();
      final dy = (s.y - h.y).abs();
      return math.atan2(dy, dx) * 180.0 / math.pi;
    }

    final left = (ls != null && lh != null) ? incline(ls, lh) : null;
    final right = (rs != null && rh != null) ? incline(rs, rh) : null;

    if (left == null && right == null) return null;
    if (left == null) return right;
    if (right == null) return left;
    return (left + right) / 2;
  }

  // ── Prepare / break ───────────────────────────────────────────────────────

  bool _checkPreparePose({
    required double? elbowDeg,
    required double? kneeDeg,
    required double? torsoDeg,
  }) {
    if (elbowDeg == null || kneeDeg == null || torsoDeg == null) return false;
    return elbowDeg >= _elbowTopDeg &&
        kneeDeg >= _prepareLegKneeDeg &&
        torsoDeg <= _prepareTorsoInclineDeg;
  }

  /// Returns true once the best-visible leg's knee angle has been below
  /// [_breakKneeCollapseDeg] for at least [_breakKneeHoldDuration].
  ///
  /// Resets the hold timer whenever the knee recovers above the threshold.
  bool _checkBreakPose({
    required double? kneeDeg,
    required DateTime timestamp,
  }) {
    if (kneeDeg == null || kneeDeg >= _breakKneeCollapseDeg) {
      _kneeCollapseSince = null;
      return false;
    }
    _kneeCollapseSince ??= timestamp;
    return timestamp.difference(_kneeCollapseSince!) >= _breakKneeHoldDuration;
  }

  // ── Phase / rep tracking ──────────────────────────────────────────────────

  void _resetRepTracking() {
    _repPhase = ExerciseRepPhase.unknown;
    _prevActiveElbowDeg = null;
    _hasReachedBottomInThisRep = false;
    _elbowZone = _ElbowZone.mid;
    _elbowTrend = _ElbowTrend.unknown;
  }

  /// Updates the elbow zone, trend, rep count, and phase for one frame.
  ///
  /// Zone transitions use hysteresis to avoid flickering at boundaries.
  /// In the mid zone, phase is driven by a deadbanded delta trend to resist
  /// small noise while still detecting genuine reversals.
  ///
  /// A rep is counted the first time we reach the top zone after having
  /// reached the bottom zone — requiring a full eccentric + concentric cycle.
  void _updatePhaseAndReps({required double elbowDeg}) {
    final prev = _prevActiveElbowDeg;
    final delta = prev == null ? null : elbowDeg - prev;
    final prevZone = _elbowZone;

    // Zone transitions with hysteresis.
    // When crossing from top/bottom through mid in a single frame (e.g. a fast
    // jump from 170° directly to 75°), allow skipping straight to bottom/top
    // rather than stopping at mid for one frame.
    switch (_elbowZone) {
      case _ElbowZone.top:
        if (elbowDeg < _elbowTopExitDeg) {
          _elbowZone = _ElbowZone.mid;
          if (elbowDeg <= _elbowBottomDeg) _elbowZone = _ElbowZone.bottom;
        }
        break;
      case _ElbowZone.bottom:
        if (elbowDeg > _elbowBottomExitDeg) {
          _elbowZone = _ElbowZone.mid;
          if (elbowDeg >= _elbowTopDeg) _elbowZone = _ElbowZone.top;
        }
        break;
      case _ElbowZone.mid:
        if (elbowDeg >= _elbowTopDeg) {
          _elbowZone = _ElbowZone.top;
        } else if (elbowDeg <= _elbowBottomDeg) {
          _elbowZone = _ElbowZone.bottom;
        }
        break;
    }

    // Seed a stable trend from zone-boundary crossings.
    if (prevZone != _elbowZone) {
      if (prevZone == _ElbowZone.top && _elbowZone == _ElbowZone.mid) {
        _elbowTrend = _ElbowTrend.goingDown; // lowering → eccentric
      } else if (prevZone == _ElbowZone.bottom && _elbowZone == _ElbowZone.mid) {
        _elbowTrend = _ElbowTrend.goingUp; // pressing up → concentric
      }
    }

    // Refine trend from delta only when it clearly exceeds the deadband.
    if (_elbowZone == _ElbowZone.mid &&
        delta != null &&
        delta.abs() >= _elbowDeltaDeadbandDeg) {
      _elbowTrend = delta > 0 ? _ElbowTrend.goingUp : _ElbowTrend.goingDown;
    }

    // Rep bookkeeping: bottom then top = 1 rep.
    if (_elbowZone == _ElbowZone.bottom) {
      _hasReachedBottomInThisRep = true;
    }
    if (_elbowZone == _ElbowZone.top && _hasReachedBottomInThisRep) {
      _reps += 1;
      _hasReachedBottomInThisRep = false;
    }

    // Phase classification.
    if (_elbowZone == _ElbowZone.top) {
      _repPhase = ExerciseRepPhase.top;
    } else if (_elbowZone == _ElbowZone.bottom) {
      _repPhase = ExerciseRepPhase.bottom;
    } else {
      switch (_elbowTrend) {
        case _ElbowTrend.goingUp:
          _repPhase = ExerciseRepPhase.concentric;
          break;
        case _ElbowTrend.goingDown:
          _repPhase = ExerciseRepPhase.eccentric;
          break;
        case _ElbowTrend.unknown:
          _repPhase = ExerciseRepPhase.unknown;
          break;
      }
    }

    _prevActiveElbowDeg = elbowDeg;
  }

  // ── Per-side angle helpers for metrics ────────────────────────────────────

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

  double? _leftKneeDeg(Pose pose) => _poseAngles.angleDegreesFromPose(
        pose: pose,
        a: PoseLandmarkType.leftHip,
        b: PoseLandmarkType.leftKnee,
        c: PoseLandmarkType.leftAnkle,
      );

  double? _rightKneeDeg(Pose pose) => _poseAngles.angleDegreesFromPose(
        pose: pose,
        a: PoseLandmarkType.rightHip,
        b: PoseLandmarkType.rightKnee,
        c: PoseLandmarkType.rightAnkle,
      );

  // ── update ────────────────────────────────────────────────────────────────

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
    final bestArmNow = _selectBestArm(pose);
    final bestLegNow = _selectBestLeg(pose);

    final bestElbowDeg =
        bestArmNow == null ? null : _elbowDegForArm(pose, bestArmNow);
    final bestKneeDeg =
        bestLegNow == null ? null : _kneeDegForLeg(pose, bestLegNow);
    final torsoDeg = _torsoInclineDeg(pose);

    final isPreparePose = _checkPreparePose(
      elbowDeg: bestElbowDeg,
      kneeDeg: bestKneeDeg,
      torsoDeg: torsoDeg,
    );

    final isBreakPose = _checkBreakPose(
      kneeDeg: bestKneeDeg,
      timestamp: timestamp,
    );

    // Collect per-side metrics for the UI / debug overlay.
    final metrics = ExerciseFrameMetrics();
    final leftE = _leftElbowDeg(pose);
    final rightE = _rightElbowDeg(pose);
    final leftK = _leftKneeDeg(pose);
    final rightK = _rightKneeDeg(pose);
    if (leftE != null) metrics[ExerciseMetric.leftElbowDeg] = leftE;
    if (rightE != null) metrics[ExerciseMetric.rightElbowDeg] = rightE;
    if (leftK != null) metrics[ExerciseMetric.leftKneeDeg] = leftK;
    if (rightK != null) metrics[ExerciseMetric.rightKneeDeg] = rightK;
    if (torsoDeg != null) metrics[ExerciseMetric.torsoInclineDeg] = torsoDeg;

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
      _resetRepTracking();
      _lockedArmLandmarks = bestArmNow;
      _kneeCollapseSince = null;
    }

    // Prefer the locked arm while it's still visible; fall back otherwise.
    final activeArm = (_lifecycle.stage == ExerciseSetStage.active &&
            _lockedArmLandmarks != null &&
            _hasArmChain(pose, _lockedArmLandmarks!))
        ? _lockedArmLandmarks
        : bestArmNow;

    // Lock lazily if the set was started manually before any arm was visible.
    if (_lifecycle.stage == ExerciseSetStage.active &&
        _lockedArmLandmarks == null &&
        activeArm != null) {
      _lockedArmLandmarks = activeArm;
    }

    final activeElbowDeg =
        activeArm == null ? null : _elbowDegForArm(pose, activeArm);

    if (_lifecycle.stage == ExerciseSetStage.active && activeElbowDeg != null) {
      _updatePhaseAndReps(elbowDeg: activeElbowDeg);
    }

    if (lifecycleEvent.didEndSet) {
      _resetRepTracking();
      _lockedArmLandmarks = null;
      _kneeCollapseSince = null;
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
