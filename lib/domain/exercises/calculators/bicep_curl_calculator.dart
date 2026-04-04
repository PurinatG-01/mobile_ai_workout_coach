import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../common/services/pose_angle_service.dart';
import '../exercise_calculator.dart';
import '../models/exercise_frame_metrics.dart';
import '../models/exercise_frame_result.dart';
import '../models/exercise_metric.dart';
import '../models/exercise_rep_phase.dart';
import '../models/exercise_set_stage.dart';
import '../set_lifecycle_controller.dart';

/// Bicep curl rep/phase calculator.
///
/// The set lifecycle is driven entirely by button signals — no automatic
/// start, end, or interruption based on pose. When landmarks are missing,
/// all rep/phase state is preserved until they return.
///
/// Rep counting: both arms extended (≥ 160°) → both arms curled (≤ 60°) = one rep.
/// Mid-zone phase is derived from the last confirmed extreme (top/bottom) to
/// avoid flickering from frame-to-frame noise.
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

  /// Last confirmed extreme zone: bottom (extended) or top (curled).
  ///
  /// Used to classify the mid-zone phase without relying on frame-to-frame
  /// deltas, which are noisy. Once we know the user was last at bottom, any
  /// mid-zone frame must be concentric (curling up). Once last at top, any
  /// mid-zone frame must be eccentric (uncurling down).
  ExerciseRepPhase _lastConfirmedZone = ExerciseRepPhase.unknown;

  static const double _extendedThresholdDeg = 160;
  static const double _curledThresholdDeg = 60;

  @override
  void reset() {
    _reps = 0;
    _repPhase = ExerciseRepPhase.unknown;
    _repArmed = false;
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
    bool autoSetLifecycle = true,
    bool autoEndSetLifecycle = true,
  }) {
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

    if (leftElbowDeg != null) metrics[ExerciseMetric.leftElbowDeg] = leftElbowDeg;
    if (rightElbowDeg != null) metrics[ExerciseMetric.rightElbowDeg] = rightElbowDeg;

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
      _reps = 0;
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastConfirmedZone = ExerciseRepPhase.unknown;
    }

    if (lifecycleEvent.didEndSet) {
      _repPhase = ExerciseRepPhase.unknown;
      _repArmed = false;
      _lastConfirmedZone = ExerciseRepPhase.unknown;
    }

    if (_lifecycle.stage == ExerciseSetStage.active) {
      // When landmarks are missing, skip this frame — state is preserved.
      if (leftElbowDeg != null && rightElbowDeg != null) {
        final bothExtended = leftElbowDeg >= _extendedThresholdDeg &&
            rightElbowDeg >= _extendedThresholdDeg;
        final bothCurled = leftElbowDeg <= _curledThresholdDeg &&
            rightElbowDeg <= _curledThresholdDeg;

        if (bothExtended) {
          _repPhase = ExerciseRepPhase.bottom;
          _lastConfirmedZone = ExerciseRepPhase.bottom;
          _repArmed = true;
        } else if (bothCurled) {
          _repPhase = ExerciseRepPhase.top;
          _lastConfirmedZone = ExerciseRepPhase.top;
          if (_repArmed) {
            _reps += 1;
            _repArmed = false;
          }
        } else {
          // Mid-zone: direction based on last confirmed extreme.
          // bottom → mid = curling up = concentric
          // top → mid   = uncurling down = eccentric
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
