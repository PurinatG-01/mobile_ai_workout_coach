import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../common/services/pose_angle_service.dart';
import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_metric.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

/// The three positional zones the combined arm position can be in during a pull-up.
enum _PullUpZone { top, mid, bottom }

/// Pull-up rep and phase calculator for a back-facing camera.
///
/// ## Rep counting
/// A rep completes when both arms reach [_PullUpZone.bottom] (arms fully
/// extended, hanging) and then both return to [_PullUpZone.top] (arms deeply
/// bent, chin at bar). Partial movements that never reach either extreme are
/// not counted.
///
/// ## Zone detection
/// Uses a three-zone state machine with hysteresis on the elbow angle
/// (shoulder → elbow → wrist), the same approach used by all other
/// calculators. The pull-up's elbow range of motion (~100°+) is large enough
/// that angle alone reliably distinguishes hanging from fully pulled up.
///
/// Zone entry requires both arms to clear the threshold simultaneously.
/// Zone exit is triggered when either arm leaves the hysteresis band.
///
/// ## Both-arms requirement
/// Both elbow angles must be available to update state. When either arm's
/// landmarks are missing the frame is skipped and state is preserved.
/// There is no arm-lock or best-arm selection — pull-ups require symmetric
/// bilateral movement by design.
///
/// ## Phase detection
/// Mid-zone direction is determined by the last confirmed extreme (top/bottom),
/// not by comparing angles frame-to-frame.
///   - Last confirmed = bottom → now rising     = concentric (pulling up)
///   - Last confirmed = top    → now descending = eccentric  (lowering down)
///
/// ## Set lifecycle
/// Always manual — driven by startCountdown / startSet / endSet signals.
/// Pose alone never starts or ends a set.
///
/// ## Thresholds
/// Starting values based on expected pull-up range of motion. Calibrate
/// against physical testing — a real pull-up travels ~100°+ so angle alone
/// is a strong signal, but ML Kit may underreport extension angles by 5–10°.
class PullUpCalculator implements ExerciseCalculator {
  PullUpCalculator({
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

  /// The current hysteresis zone for the combined arm position.
  _PullUpZone _pullUpZone = _PullUpZone.mid;

  /// Set once both arms reach the bottom zone within a rep.
  /// The rep is only counted when they subsequently return to the top zone.
  bool _hasReachedBottomInThisRep = false;

  /// Tracks the last confirmed extreme (top or bottom).
  /// Determines whether the mid zone is eccentric or concentric.
  ExerciseRepPhase _lastConfirmedZone = ExerciseRepPhase.unknown;

  // ── angle thresholds ───────────────────────────────────────────────────────

  /// Elbow angle to enter the bottom zone: both arms fully extended (hanging).
  /// Set below anatomical extension to compensate for ML Kit underreporting
  /// angles by 5–10° due to landmark jitter.
  static const double _bottomEntryDeg = 150;

  /// Elbow angle to exit the bottom zone.
  /// 7° gap vs entry — either arm dropping below this threshold returns
  /// the zone to mid.
  static const double _bottomExitDeg = 143;

  /// Elbow angle to enter the top zone: both arms deeply bent (chin at bar).
  static const double _topEntryDeg = 70;

  /// Elbow angle to exit the top zone.
  /// 8° gap vs entry — either arm rising above this threshold returns
  /// the zone to mid.
  static const double _topExitDeg = 78;

  // ── public API ─────────────────────────────────────────────────────────────

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _pullUpZone = _PullUpZone.mid;
    _hasReachedBottomInThisRep = false;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
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

    // ── Set start: clear phase state ───────────────────────────────────────
    if (lifecycleEvent.didStartSet) {
      _clearRepState();
    }

    // ── Process frame while the set is active ──────────────────────────────
    if (_lifecycle.stage == ExerciseSetStage.active) {
      // Both elbow angles must be present to update state. Skip frames where
      // either arm's landmarks are missing — state is preserved.
      if (leftElbowDeg != null && rightElbowDeg != null) {
        _updatePhaseAndReps(leftDeg: leftElbowDeg, rightDeg: rightElbowDeg);
      }
    }

    // ── Set end: clear phase state ─────────────────────────────────────────
    if (lifecycleEvent.didEndSet) {
      _clearRepState();
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
    _pullUpZone = _PullUpZone.mid;
    _hasReachedBottomInThisRep = false;
    _lastConfirmedZone = ExerciseRepPhase.unknown;
  }

  /// Advances the pull-up zone state machine and updates phase / rep count.
  ///
  /// Zone entry requires **both** arms to clear the threshold simultaneously.
  /// Zone exit is triggered when **either** arm leaves the hysteresis band.
  void _updatePhaseAndReps({
    required double leftDeg,
    required double rightDeg,
  }) {
    // ── Step 1: Advance the zone with hysteresis ───────────────────────────
    // Exit thresholds are tighter than entry thresholds so a zone boundary
    // angle doesn't flip the zone on every frame.
    switch (_pullUpZone) {
      case _PullUpZone.bottom:
        // Leave hanging zone when either arm starts to bend.
        if (leftDeg < _bottomExitDeg || rightDeg < _bottomExitDeg) {
          _pullUpZone = _PullUpZone.mid;
        }
      case _PullUpZone.top:
        // Leave top zone when either arm starts to lower.
        if (leftDeg > _topExitDeg || rightDeg > _topExitDeg) {
          _pullUpZone = _PullUpZone.mid;
        }
      case _PullUpZone.mid:
        if (leftDeg >= _bottomEntryDeg && rightDeg >= _bottomEntryDeg) {
          // Both arms straight — enter hanging (bottom) zone.
          _pullUpZone = _PullUpZone.bottom;
        } else if (leftDeg <= _topEntryDeg && rightDeg <= _topEntryDeg) {
          // Both arms deeply bent — enter top zone.
          _pullUpZone = _PullUpZone.top;
        }
    }

    // ── Step 2: Map zone to phase and handle rep counting ──────────────────
    switch (_pullUpZone) {
      case _PullUpZone.bottom:
        // Arms are fully extended (hanging). Confirm the extreme and arm
        // the rep counter.
        _lastConfirmedZone = ExerciseRepPhase.bottom;
        _repPhase = ExerciseRepPhase.bottom;
        _hasReachedBottomInThisRep = true;

      case _PullUpZone.top:
        // Arms are deeply bent (chin at bar). Confirm the extreme and count
        // the rep if the user previously reached the bottom zone in this rep.
        _lastConfirmedZone = ExerciseRepPhase.top;
        _repPhase = ExerciseRepPhase.top;
        if (_hasReachedBottomInThisRep) {
          _reps += 1;
          _hasReachedBottomInThisRep = false;
        }

      case _PullUpZone.mid:
        // Arms are between hanging and fully pulled up.
        // Derive movement direction from the last confirmed extreme zone
        // rather than comparing angles frame-to-frame (which is noisy).
        //   bottom → mid = pulling up   = concentric
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
