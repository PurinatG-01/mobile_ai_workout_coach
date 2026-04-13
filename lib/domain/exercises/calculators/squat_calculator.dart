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

/// The three positional zones the knee angle can be in during a squat.
enum _KneeZone { top, mid, bottom }

/// Squat rep and phase calculator, optimised for a side-camera view.
///
/// ## Rep counting
/// A rep completes when the user descends to [_KneeZone.bottom] (deep squat)
/// and then returns to [_KneeZone.top] (standing). Movements that never
/// reach the bottom zone are not counted.
///
/// ## Phase detection
/// While the knee angle is in the mid zone, the direction is determined by
/// the last confirmed extreme zone — not by comparing angles frame-to-frame.
///   - Last confirmed = bottom → now rising    = concentric (coming up)
///   - Last confirmed = top    → now descending = eccentric  (going down)
///
/// ## Leg selection
/// At set start the calculator locks onto the leg whose hip→knee→ankle
/// segments are longest in screen space (the leg most visible from the side).
/// If that leg disappears mid-set it falls back to whichever leg is visible.
///
/// ## Set lifecycle
/// Always manual — driven by startCountdown / startSet / endSet signals.
/// Pose alone never starts or ends a set.
///
/// ## Missing landmarks
/// When the active leg's landmarks are missing the frame is skipped.
/// Phase and rep state are preserved until landmarks return.
class SquatCalculator implements ExerciseCalculator {
  SquatCalculator({
    SetLifecycleController? lifecycle,
    PoseAngleService? poseAngles,
  })  : _lifecycle = lifecycle ?? SetLifecycleController(),
        _poseAngles = poseAngles ?? const PoseAngleService();

  // ── dependencies ───────────────────────────────────────────────────────────

  final SetLifecycleController _lifecycle;
  final PoseAngleService _poseAngles;

  // ── phase / rep state ──────────────────────────────────────────────────────

  int _reps = 0;
  ExerciseRepPhase _repPhase = ExerciseRepPhase.unknown;

  /// The current hysteresis zone the knee angle sits in.
  _KneeZone _kneeZone = _KneeZone.mid;

  /// Set once the user reaches the bottom zone within a rep.
  /// The rep is only counted when they subsequently return to the top zone.
  bool _hasReachedBottomInThisRep = false;

  /// Tracks the last confirmed extreme (top or bottom).
  /// Determines whether the mid zone is eccentric or concentric.
  ExerciseRepPhase _lastConfirmedZone = ExerciseRepPhase.unknown;

  // ── leg-lock state ─────────────────────────────────────────────────────────

  /// The leg (left or right) locked at set start.
  /// Null until the first set begins.
  Set<PoseLandmarkType>? _lockedLeg;

  // ── angle thresholds ───────────────────────────────────────────────────────

  /// Knee angle to enter the top zone: leg is substantially straight (standing).
  /// Set lower than anatomical full extension (~170°+) to compensate for ML Kit
  /// underreporting the angle by 5–10° due to landmark jitter.
  static const double _topEntryDeg = 160;

  /// Knee angle to exit the top zone.
  /// 10° gap vs entry absorbs ML Kit jitter so a single noisy frame cannot
  /// knock the user out of the top zone.
  static const double _topExitDeg = 150;

  /// Knee angle to enter the bottom zone: knee is adequately bent (squat depth).
  /// Slightly permissive to allow for camera angle and minor form variation.
  static const double _bottomEntryDeg = 125;

  /// Knee angle to exit the bottom zone.
  /// 8° gap vs entry keeps the user in bottom zone through small jitter
  /// when they first begin rising out of the squat.
  static const double _bottomExitDeg = 133;

  // ── landmark sets ──────────────────────────────────────────────────────────

  static const _leftLeg = <PoseLandmarkType>{
    PoseLandmarkType.leftHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.leftAnkle,
  };

  static const _rightLeg = <PoseLandmarkType>{
    PoseLandmarkType.rightHip,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.rightAnkle,
  };

  // ── public API ─────────────────────────────────────────────────────────────

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
    _lockedLeg = null;
    _lifecycle.reset();
  }

  @override
  ExerciseFrameResult? update({
    required Pose pose,
    required DateTime timestamp,
    bool startCountdown = false,
    bool startSet = false,
    bool endSet = false,
    bool autoSetLifecycle = false,
    bool autoEndSetLifecycle = false,
  }) {
    final metrics = ExerciseFrameMetrics();

    // ── Record both knee angles for the debug overlay ──────────────────────
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

    // ── Advance lifecycle (manual signals only — no auto start/end) ────────
    final lifecycleEvent = _lifecycle.tick(
      isPreparePose: true,
      isBreakPose: false,
      timestamp: timestamp,
      startCountdownSignal: startCountdown,
      startSignal: startSet,
      endSignal: endSet,
      autoStart: false,
      autoEnd: false,
    );

    // ── Set start: lock the best-visible leg and clear phase state ─────────
    if (lifecycleEvent.didStartSet) {
      _clearRepState();
      _lockedLeg = _selectBestLeg(pose);
    }

    // ── Process frame while the set is active ──────────────────────────────
    if (_lifecycle.stage == ExerciseSetStage.active) {
      // Prefer the locked leg; fall back to best visible if it disappears.
      final activeLeg = (_lockedLeg != null && _legIsVisible(pose, _lockedLeg!))
          ? _lockedLeg
          : _selectBestLeg(pose);

      // Lazily lock if the set started before any leg was visible.
      if (_lockedLeg == null && activeLeg != null) {
        _lockedLeg = activeLeg;
      }

      final kneeDeg = activeLeg == null ? null : _kneeDeg(pose, activeLeg);

      // Skip the frame when landmarks are missing; state is preserved.
      if (kneeDeg != null) {
        _updatePhaseAndReps(kneeDeg: kneeDeg);
      }
    }

    // ── Set end: clear phase state and release the leg lock ───────────────
    if (lifecycleEvent.didEndSet) {
      _clearRepState();
      _lockedLeg = null;
    }

    return ExerciseFrameResult(
      reps: _reps,
      setStage: _lifecycle.stage,
      // Phase is only meaningful while the set is active.
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

  // ── private helpers ────────────────────────────────────────────────────────

  /// Resets phase/rep-tracking state between sets.
  /// [_reps] is intentionally NOT reset here — reps accumulate across sets
  /// until [reset] is called explicitly.
  void _clearRepState() {
    _repPhase = ExerciseRepPhase.unknown;
    _hasReachedBottomInThisRep = false;
    _kneeZone = _KneeZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
  }

  /// Returns true when all three landmarks for [leg] are present in [pose].
  bool _legIsVisible(Pose pose, Set<PoseLandmarkType> leg) {
    final c = _chainFor(leg);
    return pose.landmarks[c.hip] != null &&
        pose.landmarks[c.knee] != null &&
        pose.landmarks[c.ankle] != null;
  }

  /// Picks the leg whose hip→knee + knee→ankle total segment length is greater.
  /// A longer projected chain means that leg is more side-on to the camera,
  /// giving a more reliable knee angle reading.
  /// Returns null when neither leg has all three landmarks visible.
  Set<PoseLandmarkType>? _selectBestLeg(Pose pose) {
    final lc = _chainFor(_leftLeg);
    final rc = _chainFor(_rightLeg);

    final lh = pose.landmarks[lc.hip];
    final lk = pose.landmarks[lc.knee];
    final la = pose.landmarks[lc.ankle];
    final rh = pose.landmarks[rc.hip];
    final rk = pose.landmarks[rc.knee];
    final ra = pose.landmarks[rc.ankle];

    final hasLeft  = lh != null && lk != null && la != null;
    final hasRight = rh != null && rk != null && ra != null;

    if (!hasLeft && !hasRight) return null;
    if (hasLeft && !hasRight)  return _leftLeg;
    if (!hasLeft)              return _rightLeg;

    // Both legs visible — pick the one with the longer projected chain.
    final leftScore  = _segLen(lh, lk) + _segLen(lk, la);
    final rightScore = _segLen(rh, rk) + _segLen(rk, ra);
    return leftScore >= rightScore ? _leftLeg : _rightLeg;
  }

  /// Returns the hip–knee–ankle angle in degrees for [leg], or null if any
  /// landmark is missing.
  double? _kneeDeg(Pose pose, Set<PoseLandmarkType> leg) {
    final c = _chainFor(leg);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: c.hip,
      b: c.knee,
      c: c.ankle,
    );
  }

  /// Maps a landmark set to its hip / knee / ankle landmark types.
  ({PoseLandmarkType hip, PoseLandmarkType knee, PoseLandmarkType ankle})
      _chainFor(Set<PoseLandmarkType> leg) {
    if (leg.contains(PoseLandmarkType.leftHip)) {
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

  /// Euclidean distance between two landmarks in normalised screen space.
  double _segLen(PoseLandmark? a, PoseLandmark? b) {
    if (a == null || b == null) return 0;
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Advances the knee zone state machine and updates phase / rep count.
  void _updatePhaseAndReps({required double kneeDeg}) {
    // ── Step 1: Advance the zone with hysteresis ───────────────────────────
    // Exit thresholds are tighter than entry thresholds so an angle sitting
    // at a zone boundary doesn't flip between zones on every frame.
    switch (_kneeZone) {
      case _KneeZone.top:
        if (kneeDeg < _topExitDeg) _kneeZone = _KneeZone.mid;
      case _KneeZone.bottom:
        if (kneeDeg > _bottomExitDeg) _kneeZone = _KneeZone.mid;
      case _KneeZone.mid:
        if (kneeDeg >= _topEntryDeg) {
          _kneeZone = _KneeZone.top;
        } else if (kneeDeg <= _bottomEntryDeg) {
          _kneeZone = _KneeZone.bottom;
        }
    }

    // ── Step 2: Map zone to phase and handle rep counting ──────────────────
    switch (_kneeZone) {
      case _KneeZone.top:
        // User is standing. Confirm the extreme and count the rep if they
        // previously reached the bottom zone in this rep.
        _lastConfirmedZone = ExerciseRepPhase.top;
        _repPhase = ExerciseRepPhase.top;
        if (_hasReachedBottomInThisRep) {
          _reps += 1;
          _hasReachedBottomInThisRep = false;
        }

      case _KneeZone.bottom:
        // User is at squat depth. Confirm the extreme and arm the rep counter.
        _lastConfirmedZone = ExerciseRepPhase.bottom;
        _repPhase = ExerciseRepPhase.bottom;
        _hasReachedBottomInThisRep = true;

      case _KneeZone.mid:
        // User is between standing and squat depth.
        // Derive movement direction from the last confirmed extreme zone
        // rather than comparing angles frame-to-frame (which is noisy).
        //   bottom → mid = rising back up = concentric
        //   top    → mid = descending     = eccentric
        switch (_lastConfirmedZone) {
          case ExerciseRepPhase.bottom:
            _repPhase = ExerciseRepPhase.concentric;
          case ExerciseRepPhase.top:
            _repPhase = ExerciseRepPhase.eccentric;
          case ExerciseRepPhase.unknown:
          case ExerciseRepPhase.concentric:
          case ExerciseRepPhase.eccentric:
            // Set just started and no extreme has been confirmed yet.
            _repPhase = ExerciseRepPhase.unknown;
        }
    }
  }
}
