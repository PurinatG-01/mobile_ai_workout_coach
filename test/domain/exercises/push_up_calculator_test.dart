import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/push_up_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_metric.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_rep_phase.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

PoseLandmark _lm(PoseLandmarkType type, double x, double y) {
  return PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: 1);
}

/// Builds a left-only pose with exact elbow angle, knee angle, and torso
/// incline.
///
/// Geometry derivation:
///
/// Torso: hip at (0,0), shoulder at (cos(tRad), −sin(tRad)).
///   → |dx| = cos(tRad), |dy| = sin(tRad) → incline = tRad ✓
///
/// Arm (vertex at elbow): elbow at (cos(tRad)+1, −sin(tRad)).
///   BA = shoulder − elbow = (−1, 0).
///   We want angle = elbowDeg → BC = (−cos(eRad), sin(eRad)).
///   wrist = elbow + BC.
///   Verify: dot(BA, BC) = cos(eRad), |BA|=|BC|=1 → angle = eRad ✓
///
/// Leg (vertex at knee): knee at (−1, 0), hip at (0, 0).
///   BA = hip − knee = (1, 0).
///   BC = (cos(kRad), sin(kRad)).
///   ankle = knee + BC.
///   Verify: dot(BA, BC) = cos(kRad), |BA|=|BC|=1 → angle = kRad ✓
Pose _plankLeft({
  required double elbowDeg,
  required double kneeDeg,
  required double torsoInclineDeg,
}) {
  final eRad = elbowDeg * math.pi / 180;
  final kRad = kneeDeg * math.pi / 180;
  final tRad = torsoInclineDeg * math.pi / 180;

  final shoulderX = math.cos(tRad);
  final shoulderY = -math.sin(tRad);

  final elbowX = shoulderX + 1;
  final elbowY = shoulderY;

  final wristX = elbowX - math.cos(eRad);
  final wristY = elbowY + math.sin(eRad);

  const hipX = 0.0, hipY = 0.0;
  const kneeX = -1.0, kneeY = 0.0;
  final ankleX = kneeX + math.cos(kRad);
  final ankleY = kneeY + math.sin(kRad);

  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder:
        _lm(PoseLandmarkType.leftShoulder, shoulderX, shoulderY),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, elbowX, elbowY),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist, wristX, wristY),
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, hipX, hipY),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, kneeX, kneeY),
    PoseLandmarkType.leftAnkle:
        _lm(PoseLandmarkType.leftAnkle, ankleX, ankleY),
  });
}

/// Builds a pose with both arms, controlled by segment scale to drive arm
/// selection. Legs are straight (kneeDeg = 170) and torso is horizontal (5°).
///
/// [leftScale]/[rightScale] stretch each arm's segments; larger scale →
/// longer combined length → selected as best arm.
Pose _poseBothArms({
  required double leftElbowDeg,
  required double leftScale,
  required double rightElbowDeg,
  required double rightScale,
}) {
  final le = leftElbowDeg * math.pi / 180;
  final re = rightElbowDeg * math.pi / 180;
  const kRad = 170 * math.pi / 180;
  const tRad = 5 * math.pi / 180;

  // Left arm at origin.
  final lShoulderX = math.cos(tRad);
  final lShoulderY = -math.sin(tRad);
  final lElbowX = lShoulderX + leftScale;
  final lElbowY = lShoulderY;
  final lWristX = lElbowX - leftScale * math.cos(le);
  final lWristY = lElbowY + leftScale * math.sin(le);

  // Right arm offset to the right.
  const offset = 20.0;
  final rShoulderX = offset + math.cos(tRad);
  final rShoulderY = -math.sin(tRad);
  final rElbowX = rShoulderX + rightScale;
  final rElbowY = rShoulderY;
  final rWristX = rElbowX - rightScale * math.cos(re);
  final rWristY = rElbowY + rightScale * math.sin(re);

  // Legs + torso on the left side only (right-side legs are not needed for
  // these tests which focus on arm locking).
  const hipX = 0.0, hipY = 0.0;
  const kneeX = -1.0, kneeY = 0.0;
  final ankleX = kneeX + math.cos(kRad);
  final ankleY = kneeY + math.sin(kRad);

  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder:
        _lm(PoseLandmarkType.leftShoulder, lShoulderX, lShoulderY),
    PoseLandmarkType.leftElbow:
        _lm(PoseLandmarkType.leftElbow, lElbowX, lElbowY),
    PoseLandmarkType.leftWrist:
        _lm(PoseLandmarkType.leftWrist, lWristX, lWristY),
    PoseLandmarkType.rightShoulder:
        _lm(PoseLandmarkType.rightShoulder, rShoulderX, rShoulderY),
    PoseLandmarkType.rightElbow:
        _lm(PoseLandmarkType.rightElbow, rElbowX, rElbowY),
    PoseLandmarkType.rightWrist:
        _lm(PoseLandmarkType.rightWrist, rWristX, rWristY),
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, hipX, hipY),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, kneeX, kneeY),
    PoseLandmarkType.leftAnkle:
        _lm(PoseLandmarkType.leftAnkle, ankleX, ankleY),
  });
}

/// Pose with right-arm only (no left arm) for fallback tests.
Pose _poseRightArmOnly({required double elbowDeg, required double kneeDeg}) {
  final eRad = elbowDeg * math.pi / 180;
  const tRad = 5 * math.pi / 180;
  final kRad = kneeDeg * math.pi / 180;

  final rShoulderX = math.cos(tRad);
  final rShoulderY = -math.sin(tRad);
  final rElbowX = rShoulderX + 1;
  final rElbowY = rShoulderY;
  final rWristX = rElbowX - math.cos(eRad);
  final rWristY = rElbowY + math.sin(eRad);

  const hipX = 0.0, hipY = 0.0;
  const kneeX = -1.0, kneeY = 0.0;
  final ankleX = kneeX + math.cos(kRad);
  final ankleY = kneeY + math.sin(kRad);

  // Use right-side hip/knee/ankle for the leg chain.
  const rHipX = 5.0, rHipY = 0.0;
  const rKneeX = 4.0, rKneeY = 0.0;
  final rAnkleX = rKneeX + math.cos(kRad);
  final rAnkleY = rKneeY + math.sin(kRad);

  return Pose(landmarks: {
    PoseLandmarkType.rightShoulder:
        _lm(PoseLandmarkType.rightShoulder, rShoulderX, rShoulderY),
    PoseLandmarkType.rightElbow:
        _lm(PoseLandmarkType.rightElbow, rElbowX, rElbowY),
    PoseLandmarkType.rightWrist:
        _lm(PoseLandmarkType.rightWrist, rWristX, rWristY),
    // Include right-side hip for torso incline (shoulder is already placed above).
    PoseLandmarkType.rightHip: _lm(PoseLandmarkType.rightHip, rHipX, rHipY),
    PoseLandmarkType.rightKnee:
        _lm(PoseLandmarkType.rightKnee, rKneeX, rKneeY),
    PoseLandmarkType.rightAnkle:
        _lm(PoseLandmarkType.rightAnkle, rAnkleX, rAnkleY),
    // Left leg present but no left arm (to simulate occlusion).
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, hipX, hipY),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, kneeX, kneeY),
    PoseLandmarkType.leftAnkle:
        _lm(PoseLandmarkType.leftAnkle, ankleX, ankleY),
  });
}

SetLifecycleController _noDelayLifecycle() => SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: Duration.zero,
    );

void main() {
  // ── Prepare pose gate tests ─────────────────────────────────────────────

  group('prepare pose', () {
    test('accepts full plank alignment', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // elbow=170°, knee=165°, torso=10° → all gates pass.
      final r = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r.setStage, ExerciseSetStage.countdown);
    });

    test('rejects when arms bent (elbow < 160°)', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      final r = calc.update(
        pose: _plankLeft(elbowDeg: 140, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r.setStage, ExerciseSetStage.rest);
    });

    test('rejects when legs bent (knee < 155°)', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      final r = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 130, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r.setStage, ExerciseSetStage.rest);
    });

    test('rejects when torso not horizontal (incline > 30°)', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      final r = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 50),
        timestamp: t0,
      )!;
      expect(r.setStage, ExerciseSetStage.rest);
    });

    test('aborts countdown when plank is broken', () {
      final lifecycle = SetLifecycleController(
        countdownDuration: const Duration(seconds: 3),
        endSetGraceDuration: Duration.zero,
      );
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Enter countdown.
      final r0 = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r0.setStage, ExerciseSetStage.countdown);

      // Break plank (elbow drops).
      final r1 = calc.update(
        pose: _plankLeft(elbowDeg: 130, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r1.setStage, ExerciseSetStage.rest);
    });
  });

  // ── Rep counting ────────────────────────────────────────────────────────

  group('rep counting', () {
    test('counts 1 rep for top → bottom → top', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Plank → countdown → active.
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      final rActive = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rActive.setStage, ExerciseSetStage.active);
      expect(rActive.repPhase, ExerciseRepPhase.top);
      expect(rActive.reps, 0);

      // Eccentric (lowering).
      final rEcc = calc.update(
        pose: _plankLeft(elbowDeg: 130, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rEcc.repPhase, ExerciseRepPhase.eccentric);
      expect(rEcc.reps, 0);

      // Bottom.
      final rBot = calc.update(
        pose: _plankLeft(elbowDeg: 80, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rBot.repPhase, ExerciseRepPhase.bottom);
      expect(rBot.reps, 0);

      // Concentric (pressing up).
      final rCon = calc.update(
        pose: _plankLeft(elbowDeg: 130, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rCon.repPhase, ExerciseRepPhase.concentric);
      expect(rCon.reps, 0);

      // Top → rep counted.
      final rTop = calc.update(
        pose: _plankLeft(elbowDeg: 165, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rTop.repPhase, ExerciseRepPhase.top);
      expect(rTop.reps, 1);

      // Holding top does not double-count.
      final rStay = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rStay.repPhase, ExerciseRepPhase.top);
      expect(rStay.reps, 1);
    });

    test('does not count without reaching bottom', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Start set.
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Partial descent — never hits ≤ 90°.
      calc.update(
          pose: _plankLeft(elbowDeg: 120, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      final r = calc.update(
        pose: _plankLeft(elbowDeg: 165, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r.reps, 0);
    });

    test('counts multiple reps correctly', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      for (var i = 0; i < 3; i++) {
        calc.update(
            pose: _plankLeft(elbowDeg: 80, kneeDeg: 165, torsoInclineDeg: 10),
            timestamp: t0);
        calc.update(
            pose: _plankLeft(elbowDeg: 165, kneeDeg: 165, torsoInclineDeg: 10),
            timestamp: t0);
      }

      final r = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r.reps, 3);
    });
  });

  // ── Hysteresis ───────────────────────────────────────────────────────────

  group('hysteresis', () {
    test('stays in top phase until elbow drops below 155°', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Just inside hysteresis band → still top.
      final r1 = calc.update(
        pose: _plankLeft(elbowDeg: 157, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r1.repPhase, ExerciseRepPhase.top);

      // Past hysteresis exit → leaves top.
      final r2 = calc.update(
        pose: _plankLeft(elbowDeg: 153, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r2.repPhase, ExerciseRepPhase.eccentric);
    });

    test('stays in bottom phase until elbow rises above 95°', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Reach bottom.
      calc.update(
          pose: _plankLeft(elbowDeg: 80, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Just inside hysteresis band → still bottom.
      final r1 = calc.update(
        pose: _plankLeft(elbowDeg: 93, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r1.repPhase, ExerciseRepPhase.bottom);

      // Past exit → concentric.
      final r2 = calc.update(
        pose: _plankLeft(elbowDeg: 97, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(r2.repPhase, ExerciseRepPhase.concentric);
    });
  });

  // ── Jitter resistance ────────────────────────────────────────────────────

  group('jitter resistance', () {
    test('small jitter below deadband does not flip eccentric phase', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Going down → eccentric.
      calc.update(
          pose: _plankLeft(elbowDeg: 145, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      final rEcc = calc.update(
        pose: _plankLeft(elbowDeg: 135, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rEcc.repPhase, ExerciseRepPhase.eccentric);

      // Tiny jitter up (< 2° deadband) → still eccentric.
      final rJitter = calc.update(
        pose: _plankLeft(elbowDeg: 136, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rJitter.repPhase, ExerciseRepPhase.eccentric);

      // Clear upward movement → switches to concentric.
      final rRev = calc.update(
        pose: _plankLeft(elbowDeg: 141, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;
      expect(rRev.repPhase, ExerciseRepPhase.concentric);
    });
  });

  // ── Break pose ───────────────────────────────────────────────────────────

  group('break pose', () {
    test('fires after knee collapse is held for 500 ms', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Start set.
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      expect(lifecycle.stage, ExerciseSetStage.active);

      // t1: knee first collapses (user drops to knee-rest, kneeDeg = 100°).
      // _kneeCollapseSince = t1; hold has not elapsed → still active.
      final t1 = t0.add(const Duration(milliseconds: 100));
      final rSoon = calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t1,
      )!;
      expect(rSoon.setStage, ExerciseSetStage.active);

      // t2: 300 ms after collapse start — still below the 500 ms hold.
      final t2 = t0.add(const Duration(milliseconds: 400));
      final rStill = calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t2,
      )!;
      expect(rStill.setStage, ExerciseSetStage.active);

      // t3: 600 ms after collapse start — hold elapsed → set ends.
      final t3 = t0.add(const Duration(milliseconds: 700));
      final rBreak = calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t3,
      )!;
      expect(rBreak.setStage, ExerciseSetStage.rest);
      expect(rBreak.didEndSetByBreakPose, isTrue);
    });

    test('does NOT fire at push-up bottom when knees stay straight', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Start set.
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Push-up bottom: elbow collapses to 75°, but knees are still straight
      // at 165°.
      final tBottom = t0.add(const Duration(milliseconds: 800));
      final rBot = calc.update(
        pose: _plankLeft(elbowDeg: 75, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: tBottom,
      )!;
      expect(rBot.setStage, ExerciseSetStage.active);
      expect(rBot.repPhase, ExerciseRepPhase.bottom);
    });

    test('hold timer resets if knee recovers before 500 ms', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Start set.
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);

      // Knee drops briefly.
      calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t0.add(const Duration(milliseconds: 200)),
      );

      // Knee recovers (resets hold timer).
      calc.update(
        pose: _plankLeft(elbowDeg: 165, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0.add(const Duration(milliseconds: 300)),
      );

      // Knee drops again: hold timer restarts from this point.
      calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t0.add(const Duration(milliseconds: 400)),
      );

      // Only 200 ms since the new collapse start → still active.
      final r = calc.update(
        pose: _plankLeft(elbowDeg: 100, kneeDeg: 100, torsoInclineDeg: 10),
        timestamp: t0.add(const Duration(milliseconds: 600)),
      )!;
      // 600 - 400 = 200 ms elapsed since new collapse start (< 500 ms).
      expect(r.setStage, ExerciseSetStage.active);
    });
  });

  // ── Arm locking ──────────────────────────────────────────────────────────

  group('arm locking', () {
    test('locks best arm at set start; ignores flipped best arm', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Left arm is best (larger scale) and extended (top phase).
      // Right arm is bent (bottom-like). If selection flips, phase would change.
      final startPose = _poseBothArms(
        leftElbowDeg: 170,
        leftScale: 2.0,
        rightElbowDeg: 75,
        rightScale: 1.0,
      );

      calc.update(pose: startPose, timestamp: t0);
      final rActive = calc.update(pose: startPose, timestamp: t0)!;
      expect(rActive.setStage, ExerciseSetStage.active);
      expect(rActive.repPhase, ExerciseRepPhase.top);

      // Swap scores so right would now be the "best" arm if not locked.
      final flippedPose = _poseBothArms(
        leftElbowDeg: 170,
        leftScale: 1.0,
        rightElbowDeg: 75,
        rightScale: 2.0,
      );

      final r1 = calc.update(pose: flippedPose, timestamp: t0)!;
      // Still top → locked to left arm.
      expect(r1.repPhase, ExerciseRepPhase.top);
    });

    test('falls back to best arm if locked arm disappears', () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      // Start with left arm locked (extended/top), right arm bent (bottom-like).
      final startPose = _poseBothArms(
        leftElbowDeg: 170,
        leftScale: 2.0,
        rightElbowDeg: 75,
        rightScale: 1.0,
      );
      calc.update(pose: startPose, timestamp: t0);
      calc.update(pose: startPose, timestamp: t0);

      // Left arm disappears → only right arm (bent, bottom-like) remains.
      final rightOnly = _poseRightArmOnly(elbowDeg: 75, kneeDeg: 165);
      final r1 = calc.update(pose: rightOnly, timestamp: t0)!;
      expect(r1.setStage, ExerciseSetStage.active);
      // Phase should no longer be top (right arm is at bottom-like angle).
      expect(r1.repPhase, isNot(ExerciseRepPhase.top));
    });
  });

  // ── Metrics ──────────────────────────────────────────────────────────────

  group('metrics', () {
    test('emits elbow, knee, and torso incline metrics when landmarks present',
        () {
      final lifecycle = _noDelayLifecycle();
      final calc = PushUpCalculator(lifecycle: lifecycle);
      final t0 = DateTime(2026, 1, 1);

      calc.update(
          pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
          timestamp: t0);
      final r = calc.update(
        pose: _plankLeft(elbowDeg: 170, kneeDeg: 165, torsoInclineDeg: 10),
        timestamp: t0,
      )!;

      expect(r.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.leftKneeDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.torsoInclineDeg], isNotNull);
    });
  });
}
