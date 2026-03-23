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

Pose _poseHandsUpExtendedElbows() {
  // Arms reaching upward with elbows extended.
  return Pose(landmarks: {
    // Left: shoulder -> elbow -> wrist in a vertical line upward.
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 0, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, -1),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, 0, -2),

    // Right: shoulder -> elbow -> wrist in a vertical line upward.
    PoseLandmarkType.rightShoulder: _lm(PoseLandmarkType.rightShoulder, 1, 0),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, 1, -1),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist, 1, -2),
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

  test('BicepCurlCalculator: bottom hold does not end set; hands-up ends set',
      () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = BicepCurlCalculator(lifecycle: lifecycle);

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start set.
    calc.update(pose: _poseExtendedBothArms(), timestamp: t0);
    final rActive = calc.update(pose: _poseExtendedBothArms(), timestamp: t0)!;
    expect(rActive.setStage, ExerciseSetStage.active);

    // Hold bottom for > grace duration: should remain active.
    final rHold = calc.update(
      pose: _poseExtendedBothArms(),
      timestamp: t0.add(const Duration(milliseconds: 1500)),
    )!;
    expect(rHold.setStage, ExerciseSetStage.active);

    // Enter hands-up break pose, but not long enough: still active.
    final rBreakSoon = calc.update(
      pose: _poseHandsUpExtendedElbows(),
      timestamp: t0.add(const Duration(milliseconds: 1600)),
    )!;
    expect(rBreakSoon.setStage, ExerciseSetStage.active);

    // Sustain hands-up for >= grace: end set.
    final rBreak = calc.update(
      pose: _poseHandsUpExtendedElbows(),
      timestamp: t0.add(const Duration(milliseconds: 2700)),
    )!;
    expect(rBreak.setStage, ExerciseSetStage.rest);
  });

  test('BicepCurlCalculator: relaxed arms-down ends set after hold + grace',
      () {
    final lifecycle = SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: const Duration(seconds: 1),
    );
    final calc = BicepCurlCalculator(lifecycle: lifecycle);

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start set.
    calc.update(pose: _poseExtendedBothArms(), timestamp: t0);
    calc.update(pose: _poseExtendedBothArms(), timestamp: t0);
    expect(lifecycle.stage, ExerciseSetStage.active);

    // Enter relaxed arms-down posture.
    final tRelax0 = t0.add(const Duration(milliseconds: 100));
    final r0 = calc.update(
      pose: _poseRelaxedArmsDownExtendedElbows(),
      timestamp: tRelax0,
    )!;
    expect(r0.setStage, ExerciseSetStage.active);

    // Hold long enough to qualify as break pose, but not long enough for grace.
    final tRelaxHold = tRelax0.add(const Duration(milliseconds: 1600));
    final r1 = calc.update(
      pose: _poseRelaxedArmsDownExtendedElbows(),
      timestamp: tRelaxHold,
    )!;
    expect(r1.setStage, ExerciseSetStage.active);

    // After grace elapses while still relaxed => end set.
    final tRelaxEnd = tRelaxHold.add(const Duration(milliseconds: 1100));
    final r2 = calc.update(
      pose: _poseRelaxedArmsDownExtendedElbows(),
      timestamp: tRelaxEnd,
    )!;
    expect(r2.setStage, ExerciseSetStage.rest);
  });
}
