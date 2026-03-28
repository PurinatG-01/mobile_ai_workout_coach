import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/bicep_curl_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_metric.dart';
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

Pose _poseExtendedBothArms() {
  return Pose(landmarks: {
    // Left arm (straight line => 180° at elbow)
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 0, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 1, 0),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, 2, 0),

    // Right arm (straight line => 180° at elbow)
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 0, 1),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 1, 1),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist, 2, 1),
  });
}

Pose _poseCurledBothArms60Deg() {
  const cos60 = 0.5;
  const sin60 = 0.8660254037844386;

  return Pose(landmarks: {
    // Left arm (60° at elbow)
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 0),
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 1, 0),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, cos60, sin60),

    // Right arm (60° at elbow)
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 0, 1),
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 1, 1),
    PoseLandmarkType.rightWrist:
        _lm(PoseLandmarkType.rightWrist, cos60, 1 + sin60),
  });
}

Pose _poseUprightTorsoExtendedArmsWithLegs() {
  // Upright torso: shoulder-hip-knee almost collinear => waist angle near 180°.
  // Includes arms so the calculator remains in prepare pose.
  return Pose(landmarks: {
    // Left torso + leg
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 0, 0),
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, 0, 2),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, 0, 4),

    // Right torso + leg
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 1, 0),
    PoseLandmarkType.rightHip: _lm(PoseLandmarkType.rightHip, 1, 2),
    PoseLandmarkType.rightKnee: _lm(PoseLandmarkType.rightKnee, 1, 4),

    // Left arm (extended)
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 1, 0),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, 2, 0),

    // Right arm (extended)
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 2, 0),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist, 3, 0),
  });
}

Pose _poseBentDownTorsoExtendedArmsWithLegs() {
  // Forward-bent torso: shoulder moves forward relative to hip while knee stays
  // below hip => waist angle decreases significantly.
  // Includes arms so the calculator remains in prepare pose.
  return Pose(landmarks: {
    // Left torso + leg
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, 0, 2),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, 0, 4),
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 2, 1),

    // Right torso + leg
    PoseLandmarkType.rightHip: _lm(PoseLandmarkType.rightHip, 1, 2),
    PoseLandmarkType.rightKnee: _lm(PoseLandmarkType.rightKnee, 1, 4),
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 3, 1),

    // Left arm (extended)
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 3, 1),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, 4, 1),

    // Right arm (extended)
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 4, 1),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist, 5, 1),
  });
}

Pose _poseRelaxedArmsDownExtendedElbows() {
  // Arms hanging down with elbows extended.
  // y increases downward, so elbows/wrists have larger y than shoulders.
  return Pose(landmarks: {
    // Left
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 0, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 1),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, 0, 2),

    // Right
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 1, 0),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 1, 1),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist, 1, 2),
  });
}

void main() {
  test('BicepCurlCalculator counts 1 rep when both arms curl', () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = BicepCurlCalculator(lifecycle: lifecycle);

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Enter prepare pose => countdown (even if countdown is 0ms).
    final r0 = calc.update(pose: _poseExtendedBothArms(), timestamp: t0)!;
    expect(r0.setStage, ExerciseSetStage.countdown);
    expect(r0.reps, 0);

    // Next tick completes countdown => active.
    final r1 = calc.update(pose: _poseExtendedBothArms(), timestamp: t0)!;
    expect(r1.setStage, ExerciseSetStage.active);
    expect(r1.repPhase, ExerciseRepPhase.bottom);
    expect(r1.reps, 0);
    expect(r1.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
    expect(r1.metrics[ExerciseMetric.rightElbowDeg], isNotNull);

    // Curl both arms => count 1 rep.
    final r2 = calc.update(
      pose: _poseCurledBothArms60Deg(),
      timestamp: t0.add(const Duration(milliseconds: 100)),
    )!;
    expect(r2.setStage, ExerciseSetStage.active);
    expect(r2.repPhase, ExerciseRepPhase.top);
    expect(r2.reps, 1);

    // Return to extended => no extra rep, just re-armed.
    final r3 = calc.update(
      pose: _poseExtendedBothArms(),
      timestamp: t0.add(const Duration(milliseconds: 200)),
    )!;
    expect(r3.repPhase, ExerciseRepPhase.bottom);
    expect(r3.reps, 1);
  });

  test('BicepCurlCalculator: bottom hold does not end set; bend-down ends set',
      () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = BicepCurlCalculator(lifecycle: lifecycle);

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start set.
    calc.update(pose: _poseUprightTorsoExtendedArmsWithLegs(), timestamp: t0);
    final rActive = calc.update(
        pose: _poseUprightTorsoExtendedArmsWithLegs(), timestamp: t0)!;
    expect(rActive.setStage, ExerciseSetStage.active);

    // Hold bottom for > grace duration: should remain active.
    final rHold = calc.update(
      pose: _poseUprightTorsoExtendedArmsWithLegs(),
      timestamp: t0.add(const Duration(milliseconds: 1500)),
    )!;
    expect(rHold.setStage, ExerciseSetStage.active);

    // Enter bend-down posture, but not long enough (hold + grace): still active.
    final rBreakSoon = calc.update(
      pose: _poseBentDownTorsoExtendedArmsWithLegs(),
      timestamp: t0.add(const Duration(milliseconds: 1600)),
    )!;
    expect(rBreakSoon.setStage, ExerciseSetStage.active);

    // Sustain bend-down for >= grace: end set.
    final rBreak = calc.update(
      pose: _poseBentDownTorsoExtendedArmsWithLegs(),
      timestamp: t0.add(const Duration(milliseconds: 2700)),
    )!;
    expect(rBreak.setStage, ExerciseSetStage.rest);
  });

  test('BicepCurlCalculator: arms-down does not end set; bend-down ends set',
      () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = BicepCurlCalculator(lifecycle: lifecycle);

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start set.
    calc.update(pose: _poseUprightTorsoExtendedArmsWithLegs(), timestamp: t0);
    calc.update(pose: _poseUprightTorsoExtendedArmsWithLegs(), timestamp: t0);
    expect(lifecycle.stage, ExerciseSetStage.active);

    // Arms-down is a valid bicep-curl rep position; it must NOT auto-end sets.
    final tRelax0 = t0.add(const Duration(milliseconds: 100));
    final r0 = calc.update(
      pose: _poseRelaxedArmsDownExtendedElbows(),
      timestamp: tRelax0,
    )!;
    expect(r0.setStage, ExerciseSetStage.active);

    // Hold arms-down well beyond any previous break thresholds: should remain active.
    final tHold = tRelax0.add(const Duration(seconds: 5));
    final r1 = calc.update(
      pose: _poseRelaxedArmsDownExtendedElbows(),
      timestamp: tHold,
    )!;
    expect(r1.setStage, ExerciseSetStage.active);

    // Bend-down should end the set (after hold + grace).
    final tBend0 = tHold.add(const Duration(milliseconds: 100));
    final rBend0 = calc.update(
      pose: _poseBentDownTorsoExtendedArmsWithLegs(),
      timestamp: tBend0,
    )!;
    expect(rBend0.setStage, ExerciseSetStage.active);

    final tBendEnd = tBend0.add(const Duration(milliseconds: 1100));
    final rBendEnd = calc.update(
      pose: _poseBentDownTorsoExtendedArmsWithLegs(),
      timestamp: tBendEnd,
    )!;
    expect(rBendEnd.setStage, ExerciseSetStage.rest);
  });
}
