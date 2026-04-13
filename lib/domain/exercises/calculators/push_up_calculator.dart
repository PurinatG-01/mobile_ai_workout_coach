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

/// The three positional zones the elbow angle can be in during a push-up.
enum _ElbowZone { top, mid, bottom }

/// Push-up rep and phase calculator.
///
/// ## Rep counting
/// A rep completes when the user descends to [_ElbowZone.bottom] (chest near
/// floor, elbow deeply bent) and then returns to [_ElbowZone.top] (arms
/// extended). Movements that never reach the bottom zone are not counted.
///
/// ## Phase detection
/// While the elbow angle is in the mid zone, direction is determined by the
/// last confirmed extreme zone — not by comparing angles frame-to-frame.
///   - Last confirmed = bottom → now rising    = concentric (pressing up)
///   - Last confirmed = top    → now descending = eccentric  (lowering down)
///
/// ## Arm selection
/// At set start the calculator locks onto the arm whose shoulder→elbow→wrist
/// segments are longest in screen space (the arm most visible from the side).
/// If that arm disappears mid-set it falls back to whichever arm is visible.
///
/// ## Set lifecycle
/// Always manual — driven by startCountdown / startSet / endSet signals.
/// Pose alone never starts or ends a set.
///
/// ## Missing landmarks
/// When the active arm's landmarks are missing the frame is skipped.
/// Phase and rep state are preserved until landmarks return.
class PushUpCalculator implements ExerciseCalculator {
  PushUpCalculator({
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

  /// The current hysteresis zone the elbow angle sits in.
  _ElbowZone _elbowZone = _ElbowZone.mid;

  /// Set once the user reaches the bottom zone within a rep.
  /// The rep is only counted when they subsequently return to the top zone.
  bool _hasReachedBottomInThisRep = false;

  /// Tracks the last confirmed extreme (top or bottom).
  /// Determines whether the mid zone is eccentric or concentric.
  ExerciseRepPhase _lastConfirmedZone = ExerciseRepPhase.unknown;

  // ── arm-lock state ─────────────────────────────────────────────────────────

  /// The arm (left or right) locked at set start.
  /// Null until the first set begins.
  Set<PoseLandmarkType>? _lockedArm;

  // ── angle thresholds ───────────────────────────────────────────────────────

  /// Elbow angle to enter the top zone: arms are substantially extended.
  /// Set slightly below anatomical full extension to compensate for ML Kit
  /// underreporting the angle by 5–10° due to landmark jitter.
  static const double _topEntryDeg = 155;

  /// Elbow angle to exit the top zone.
  /// 10° gap vs entry absorbs ML Kit jitter so a single noisy frame cannot
  /// knock the user out of the top zone.
  static const double _topExitDeg = 145;

  /// Elbow angle to enter the bottom zone: elbow is deeply bent (chest low).
  /// Slightly permissive compared to strict 90° to account for form variation.
  static const double _bottomEntryDeg = 95;

  /// Elbow angle to exit the bottom zone.
  /// 8° gap vs entry keeps the user in the bottom zone through small jitter
  /// when they first begin pressing up.
  static const double _bottomExitDeg = 103;

  // ── landmark sets ──────────────────────────────────────────────────────────

  static const _leftArm = <PoseLandmarkType>{
    PoseLandmarkType.leftShoulder,
    PoseLandmarkType.leftElbow,
    PoseLandmarkType.leftWrist,
  };

  static const _rightArm = <PoseLandmarkType>{
    PoseLandmarkType.rightShoulder,
    PoseLandmarkType.rightElbow,
    PoseLandmarkType.rightWrist,
  };

  // ── public API ─────────────────────────────────────────────────────────────

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _hasReachedBottomInThisRep = false;
    _elbowZone = _ElbowZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
    _lockedArm = null;
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

    // ── Record both elbow angles for the debug overlay ─────────────────────
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
    if (leftElbowDeg != null) metrics[ExerciseMetric.leftElbowDeg] = leftElbowDeg;
    if (rightElbowDeg != null) metrics[ExerciseMetric.rightElbowDeg] = rightElbowDeg;

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

    // ── Set start: lock the best-visible arm and clear phase state ─────────
    if (lifecycleEvent.didStartSet) {
      _clearRepState();
      _lockedArm = _selectBestArm(pose);
    }

    // ── Process frame while the set is active ──────────────────────────────
    if (_lifecycle.stage == ExerciseSetStage.active) {
      // Prefer the locked arm; fall back to best visible if it disappears.
      final activeArm = (_lockedArm != null && _armIsVisible(pose, _lockedArm!))
          ? _lockedArm
          : _selectBestArm(pose);

      // Lazily lock if the set started before any arm was visible.
      if (_lockedArm == null && activeArm != null) {
        _lockedArm = activeArm;
      }

      final elbowDeg = activeArm == null ? null : _elbowDeg(pose, activeArm);

      // Skip the frame when landmarks are missing; state is preserved.
      if (elbowDeg != null) {
        _updatePhaseAndReps(elbowDeg: elbowDeg);
      }
    }

    // ── Set end: clear phase state and release the arm lock ───────────────
    if (lifecycleEvent.didEndSet) {
      _clearRepState();
      _lockedArm = null;
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
    _elbowZone = _ElbowZone.mid;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
  }

  /// Returns true when all three landmarks for [arm] are present in [pose].
  bool _armIsVisible(Pose pose, Set<PoseLandmarkType> arm) {
    final c = _chainFor(arm);
    return pose.landmarks[c.shoulder] != null &&
        pose.landmarks[c.elbow] != null &&
        pose.landmarks[c.wrist] != null;
  }

  /// Picks the arm whose shoulder→elbow + elbow→wrist total segment length is
  /// greater in screen space — that arm is more side-on to the camera, giving
  /// a more reliable elbow angle reading.
  /// Returns null when neither arm has all three landmarks visible.
  Set<PoseLandmarkType>? _selectBestArm(Pose pose) {
    final lc = _chainFor(_leftArm);
    final rc = _chainFor(_rightArm);

    final ls = pose.landmarks[lc.shoulder];
    final le = pose.landmarks[lc.elbow];
    final lw = pose.landmarks[lc.wrist];
    final rs = pose.landmarks[rc.shoulder];
    final re = pose.landmarks[rc.elbow];
    final rw = pose.landmarks[rc.wrist];

    final hasLeft  = ls != null && le != null && lw != null;
    final hasRight = rs != null && re != null && rw != null;

    if (!hasLeft && !hasRight) return null;
    if (hasLeft && !hasRight)  return _leftArm;
    if (!hasLeft)              return _rightArm;

    // Both arms visible — pick the one with the longer projected chain.
    final leftScore  = _segLen(ls, le) + _segLen(le, lw);
    final rightScore = _segLen(rs, re) + _segLen(re, rw);
    return leftScore >= rightScore ? _leftArm : _rightArm;
  }

  /// Returns the shoulder–elbow–wrist angle in degrees for [arm], or null if
  /// any landmark is missing.
  double? _elbowDeg(Pose pose, Set<PoseLandmarkType> arm) {
    final c = _chainFor(arm);
    return _poseAngles.angleDegreesFromPose(
      pose: pose,
      a: c.shoulder,
      b: c.elbow,
      c: c.wrist,
    );
  }

  /// Maps a landmark set to its shoulder / elbow / wrist landmark types.
  ({PoseLandmarkType shoulder, PoseLandmarkType elbow, PoseLandmarkType wrist})
      _chainFor(Set<PoseLandmarkType> arm) {
    if (arm.contains(PoseLandmarkType.leftShoulder)) {
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

  /// Euclidean distance between two landmarks in normalised screen space.
  double _segLen(PoseLandmark? a, PoseLandmark? b) {
    if (a == null || b == null) return 0;
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Advances the elbow zone state machine and updates phase / rep count.
  void _updatePhaseAndReps({required double elbowDeg}) {
    // ── Step 1: Advance the zone with hysteresis ───────────────────────────
    // Exit thresholds are tighter than entry thresholds so an angle sitting
    // at a zone boundary doesn't flip between zones on every frame.
    switch (_elbowZone) {
      case _ElbowZone.top:
        if (elbowDeg < _topExitDeg) _elbowZone = _ElbowZone.mid;
      case _ElbowZone.bottom:
        if (elbowDeg > _bottomExitDeg) _elbowZone = _ElbowZone.mid;
      case _ElbowZone.mid:
        if (elbowDeg >= _topEntryDeg) {
          _elbowZone = _ElbowZone.top;
        } else if (elbowDeg <= _bottomEntryDeg) {
          _elbowZone = _ElbowZone.bottom;
        }
    }

    // ── Step 2: Map zone to phase and handle rep counting ──────────────────
    switch (_elbowZone) {
      case _ElbowZone.top:
        // Arms are extended. Confirm the extreme and count the rep if the
        // user previously reached the bottom zone in this rep.
        _lastConfirmedZone = ExerciseRepPhase.top;
        _repPhase = ExerciseRepPhase.top;
        if (_hasReachedBottomInThisRep) {
          _reps += 1;
          _hasReachedBottomInThisRep = false;
        }

      case _ElbowZone.bottom:
        // Chest is near the floor. Confirm the extreme and arm the rep counter.
        _lastConfirmedZone = ExerciseRepPhase.bottom;
        _repPhase = ExerciseRepPhase.bottom;
        _hasReachedBottomInThisRep = true;

      case _ElbowZone.mid:
        // Arms are between extended and fully bent.
        // Derive movement direction from the last confirmed extreme zone
        // rather than comparing angles frame-to-frame (which is noisy).
        //   bottom → mid = pressing up   = concentric
        //   top    → mid = lowering down = eccentric
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
