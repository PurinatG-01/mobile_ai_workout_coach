import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/squat_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_rep_phase.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

PoseLandmark _lm(PoseLandmarkType type, double x, double y) {
  return PoseLandmark(
    type: type,
    x: x,
    y: y,
    z: 0,
    likelihood: 1,
  );
}

/// Builds a pose that contains ONLY the left hip/knee/ankle chain.
///
/// Geometry: knee is at origin, hip at (1, 0), ankle at (cos(theta), sin(theta)).
/// This yields the requested knee angle in a deterministic way.
Pose _poseLeftKneeAngleDeg(double deg) {
  final theta = deg * math.pi / 180.0;
  return Pose(landmarks: {
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, 0, 0),
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, 1, 0),
    PoseLandmarkType.leftAnkle:
        _lm(PoseLandmarkType.leftAnkle, math.cos(theta), math.sin(theta)),
  });
}

/// Builds a pose with BOTH legs present.
///
/// `leftScale/rightScale` controls the apparent segment length, which impacts
/// the calculator's "best visible leg" selection score.
Pose _poseBothLegs({
  required double leftDeg,
  required double leftScale,
  required double rightDeg,
  required double rightScale,
}) {
  // Each leg uses a scaled construction:
  // knee at base position, hip at (L,0), ankle at (L*cos(theta), L*sin(theta)).
  // This gives knee angle = deg and a visibility score proportional to L.
  final leftTheta = leftDeg * math.pi / 180.0;
  final rightTheta = rightDeg * math.pi / 180.0;

  const leftKneeX = 0.0;
  const leftKneeY = 0.0;
  const rightKneeX = 10.0;
  const rightKneeY = 0.0;

  return Pose(landmarks: {
    PoseLandmarkType.leftKnee:
        _lm(PoseLandmarkType.leftKnee, leftKneeX, leftKneeY),
    PoseLandmarkType.leftHip:
        _lm(PoseLandmarkType.leftHip, leftKneeX + leftScale, leftKneeY),
    PoseLandmarkType.leftAnkle: _lm(
      PoseLandmarkType.leftAnkle,
      leftKneeX + leftScale * math.cos(leftTheta),
      leftKneeY + leftScale * math.sin(leftTheta),
    ),
    PoseLandmarkType.rightKnee:
        _lm(PoseLandmarkType.rightKnee, rightKneeX, rightKneeY),
    PoseLandmarkType.rightHip:
        _lm(PoseLandmarkType.rightHip, rightKneeX + rightScale, rightKneeY),
    PoseLandmarkType.rightAnkle: _lm(
      PoseLandmarkType.rightAnkle,
      rightKneeX + rightScale * math.cos(rightTheta),
      rightKneeY + rightScale * math.sin(rightTheta),
    ),
  });
}

/// Builds a pose that contains ONLY the right hip/knee/ankle chain.
Pose _poseRightOnly({required double rightDeg, required double rightScale}) {
  final rightTheta = rightDeg * math.pi / 180.0;
  const rightKneeX = 10.0;
  const rightKneeY = 0.0;
  return Pose(landmarks: {
    PoseLandmarkType.rightKnee:
        _lm(PoseLandmarkType.rightKnee, rightKneeX, rightKneeY),
    PoseLandmarkType.rightHip:
        _lm(PoseLandmarkType.rightHip, rightKneeX + rightScale, rightKneeY),
    PoseLandmarkType.rightAnkle: _lm(
      PoseLandmarkType.rightAnkle,
      rightKneeX + rightScale * math.cos(rightTheta),
      rightKneeY + rightScale * math.sin(rightTheta),
    ),
  });
}

void main() {
  test('SquatCalculator counts 1 rep for top -> bottom -> top', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Standing (prepare) => countdown.
    final r0 = calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0)!;
    expect(r0.setStage, ExerciseSetStage.countdown);

    // Next tick completes countdown => active.
    final r1 = calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0)!;
    expect(r1.setStage, ExerciseSetStage.active);
    expect(r1.repPhase, ExerciseRepPhase.top);
    expect(r1.reps, 0);

    // Go down (eccentric) to bottom.
    final r2 = calc.update(pose: _poseLeftKneeAngleDeg(150), timestamp: t0)!;
    expect(r2.setStage, ExerciseSetStage.active);
    expect(r2.repPhase, ExerciseRepPhase.eccentric);
    expect(r2.reps, 0);

    final r3 = calc.update(pose: _poseLeftKneeAngleDeg(118), timestamp: t0)!;
    expect(r3.repPhase, ExerciseRepPhase.bottom);
    expect(r3.reps, 0);

    // Stand up (concentric) and count when reaching top.
    final r4 = calc.update(pose: _poseLeftKneeAngleDeg(150), timestamp: t0)!;
    expect(r4.repPhase, ExerciseRepPhase.concentric);
    expect(r4.reps, 0);

    final r5 = calc.update(pose: _poseLeftKneeAngleDeg(170), timestamp: t0)!;
    expect(r5.repPhase, ExerciseRepPhase.top);
    expect(r5.reps, 1);

    // Staying at top should not double-count.
    final r6 = calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0)!;
    expect(r6.repPhase, ExerciseRepPhase.top);
    expect(r6.reps, 1);
  });

  test('SquatCalculator does not count without reaching bottom', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);
    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);

    // Partial squat (never hits <= 120).
    calc.update(pose: _poseLeftKneeAngleDeg(135), timestamp: t0);
    final r = calc.update(pose: _poseLeftKneeAngleDeg(170), timestamp: t0)!;
    expect(r.setStage, ExerciseSetStage.active);
    expect(r.reps, 0);
  });

  test('SquatCalculator hysteresis keeps top until < 160', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);
    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);

    final r1 = calc.update(pose: _poseLeftKneeAngleDeg(163), timestamp: t0)!;
    expect(r1.repPhase, ExerciseRepPhase.top);

    final r2 = calc.update(pose: _poseLeftKneeAngleDeg(159), timestamp: t0)!;
    expect(r2.repPhase, ExerciseRepPhase.eccentric);
  });

  test('SquatCalculator keeps phase stable under jitter and allows reversal',
      () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start set.
    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);
    calc.update(pose: _poseLeftKneeAngleDeg(175), timestamp: t0);

    // Go down: eccentric.
    final r1 = calc.update(pose: _poseLeftKneeAngleDeg(150), timestamp: t0)!;
    expect(r1.repPhase, ExerciseRepPhase.eccentric);

    // Small jitter upward (< 2 deg deadband) should not flip phase.
    final r2 = calc.update(pose: _poseLeftKneeAngleDeg(151), timestamp: t0)!;
    expect(r2.repPhase, ExerciseRepPhase.eccentric);

    // A clear reversal upward should switch to concentric even without bottom.
    final r3 = calc.update(pose: _poseLeftKneeAngleDeg(156), timestamp: t0)!;
    expect(r3.repPhase, ExerciseRepPhase.concentric);
  });

  test('SquatCalculator locks selected leg during active set', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Make LEFT be best leg at set start (bigger scale), and LEFT is top.
    // RIGHT is bottom. If selection flips to right, repPhase would become bottom.
    final startPose = _poseBothLegs(
      leftDeg: 175,
      leftScale: 2.0,
      rightDeg: 110,
      rightScale: 1.0,
    );

    calc.update(pose: startPose, timestamp: t0);
    final active0 = calc.update(pose: startPose, timestamp: t0)!;
    expect(active0.setStage, ExerciseSetStage.active);
    expect(active0.repPhase, ExerciseRepPhase.top);

    // Now swap visibility scores so RIGHT would become "best" if not locked.
    final flippedBestPose = _poseBothLegs(
      leftDeg: 175,
      leftScale: 1.0,
      rightDeg: 110,
      rightScale: 2.0,
    );

    final r1 = calc.update(pose: flippedBestPose, timestamp: t0)!;
    expect(r1.setStage, ExerciseSetStage.active);
    // Still top => locked to left.
    expect(r1.repPhase, ExerciseRepPhase.top);
  });

  test('SquatCalculator switches leg if locked leg disappears', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = SquatCalculator(lifecycle: lifecycle);
    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    final startPose = _poseBothLegs(
      leftDeg: 175,
      leftScale: 2.0,
      rightDeg: 110,
      rightScale: 1.0,
    );

    calc.update(pose: startPose, timestamp: t0);
    calc.update(pose: startPose, timestamp: t0);

    // Only RIGHT leg remains visible => should switch and show bottom.
    final rightOnly = _poseRightOnly(rightDeg: 110, rightScale: 2.0);
    final r1 = calc.update(pose: rightOnly, timestamp: t0)!;
    expect(r1.setStage, ExerciseSetStage.active);
    // Because the prior locked leg was at top, the hysteresis zone update can
    // transition top->mid first (eccentric) before mid->bottom on the next
    // frame. The key requirement is that we no longer stick to top.
    expect(r1.repPhase, isNot(ExerciseRepPhase.top));

    final r2 = calc.update(pose: rightOnly, timestamp: t0)!;
    expect(r2.setStage, ExerciseSetStage.active);
    expect(r2.repPhase, ExerciseRepPhase.bottom);
  });
}
