import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/pull_up_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_metric.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_rep_phase.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

// ── Pose builders ─────────────────────────────────────────────────────────────

PoseLandmark _lm(PoseLandmarkType type, double x, double y) =>
    PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: 1);

/// Builds a bilateral arm pose.
/// Elbow at vertex: shoulder at (1, 0), wrist at (cos θ, sin θ) gives angle = deg.
/// Right arm is offset by 10 units to avoid landmark overlap.
Pose _poseBothArms(double leftDeg, double rightDeg) {
  final lRad = leftDeg * math.pi / 180;
  final rRad = rightDeg * math.pi / 180;
  const rOff = 10.0;
  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 1, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 0),
    PoseLandmarkType.leftWrist:
        _lm(PoseLandmarkType.leftWrist, math.cos(lRad), math.sin(lRad)),
    PoseLandmarkType.rightShoulder:
        _lm(PoseLandmarkType.rightShoulder, rOff + 1, 0),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, rOff, 0),
    PoseLandmarkType.rightWrist: _lm(
        PoseLandmarkType.rightWrist, rOff + math.cos(rRad), math.sin(rRad)),
  });
}

/// Left arm only — right arm landmarks absent.
Pose _poseLeftOnly(double deg) {
  final rad = deg * math.pi / 180;
  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 1, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 0),
    PoseLandmarkType.leftWrist:
        _lm(PoseLandmarkType.leftWrist, math.cos(rad), math.sin(rad)),
  });
}

/// Right arm only — left arm landmarks absent.
Pose _poseRightOnly(double deg) {
  final rad = deg * math.pi / 180;
  const rOff = 10.0;
  return Pose(landmarks: {
    PoseLandmarkType.rightShoulder:
        _lm(PoseLandmarkType.rightShoulder, rOff + 1, 0),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, rOff, 0),
    PoseLandmarkType.rightWrist: _lm(
        PoseLandmarkType.rightWrist, rOff + math.cos(rad), math.sin(rad)),
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

SetLifecycleController _lifecycle() => SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: Duration.zero,
    );

PullUpCalculator _calc() => PullUpCalculator(lifecycle: _lifecycle());

final _t = DateTime(2026, 1, 1);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Thresholds (from PullUpCalculator):
  //   bottom (hanging/extended) entry=150°  exit=143°
  //   top    (pulled-up/bent)   entry=70°   exit=78°
  //
  // Zone transitions require 2 frames: one exits the current zone → mid,
  // the next enters the new zone. Angle guide:
  //   bottom=160°  mid=110°  top=60°
  //
  // Entry into a zone requires BOTH arms to clear the threshold.
  // Exit is triggered when EITHER arm leaves the hysteresis band.

  group('rep counting', () {
    test('hanging (bottom) → pulled up (top) counts 1 rep', () {
      final calc = _calc();

      // Start hanging — both arms extended (bottom zone).
      final r0 = calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true)!;
      expect(r0.setStage, ExerciseSetStage.active);
      expect(r0.repPhase, ExerciseRepPhase.bottom);
      expect(r0.reps, 0);

      calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t); // bottom → mid
      final r = calc.update(
          pose: _poseBothArms(60, 60), timestamp: _t)!; // mid → top → rep
      expect(r.repPhase, ExerciseRepPhase.top);
      expect(r.reps, 1);

      // Holding top must not double-count.
      expect(
          calc.update(pose: _poseBothArms(60, 60), timestamp: _t)!.reps, 1);
    });

    test('pulled up without first hanging counts 0 reps', () {
      final calc = _calc();
      // Start at mid — bottom zone never confirmed.
      calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t, startSet: true);

      calc.update(pose: _poseBothArms(60, 60), timestamp: _t); // mid → top
      final r =
          calc.update(pose: _poseBothArms(60, 60), timestamp: _t)!; // stays top
      expect(r.reps, 0);
    });

    test('3 reps count correctly', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);

      for (var i = 0; i < 3; i++) {
        calc.update(pose: _poseBothArms(110, 110), timestamp: _t); // bottom → mid
        calc.update(pose: _poseBothArms(60, 60), timestamp: _t);   // mid → top → rep+1
        calc.update(pose: _poseBothArms(110, 110), timestamp: _t); // top → mid
        calc.update(pose: _poseBothArms(160, 160), timestamp: _t); // mid → bottom (re-armed)
      }
      expect(
          calc.update(pose: _poseBothArms(160, 160), timestamp: _t)!.reps, 3);
    });
  });

  group('phase detection', () {
    test('repPhase is unknown when set is not active', () {
      final r = _calc().update(pose: _poseBothArms(160, 160), timestamp: _t)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('repPhase is unknown before any zone extreme is confirmed', () {
      final calc = _calc();
      // Start at mid — no extreme confirmed yet.
      final r = calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t, startSet: true)!;
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('mid zone after hanging (bottom) confirmed is concentric', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      final r = calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t)!; // bottom → mid
      expect(r.repPhase, ExerciseRepPhase.concentric);
    });

    test('mid zone after pulled-up (top) confirmed is eccentric', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      calc.update(pose: _poseBothArms(110, 110), timestamp: _t);
      calc.update(pose: _poseBothArms(60, 60), timestamp: _t); // confirm top
      final r = calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t)!; // top → mid
      expect(r.repPhase, ExerciseRepPhase.eccentric);
    });
  });

  group('both-arms requirement', () {
    test('frame is skipped when left arm landmarks are missing', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      // Confirmed bottom. Left arm disappears.
      final r = calc.update(pose: _poseRightOnly(110), timestamp: _t)!;
      // State preserved: still in bottom zone.
      expect(r.repPhase, ExerciseRepPhase.bottom);
      expect(r.reps, 0);
    });

    test('frame is skipped when right arm landmarks are missing', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      final r = calc.update(pose: _poseLeftOnly(110), timestamp: _t)!;
      expect(r.repPhase, ExerciseRepPhase.bottom);
      expect(r.reps, 0);
    });

    test('zone does not advance when only one arm clears the threshold', () {
      final calc = _calc();
      // Start at mid (no extreme confirmed).
      calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t, startSet: true);

      // Left at 160° (≥ entry 150°), right still at 110° — entry needs BOTH.
      final r = calc.update(
          pose: _poseBothArms(160, 110), timestamp: _t)!;
      expect(r.repPhase, ExerciseRepPhase.unknown); // zone unchanged
    });
  });

  group('hysteresis', () {
    test('stays in bottom zone until either arm rises above exit (143°)', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);

      // Left arm at 148° — above bottomExitDeg=143 → still in bottom.
      expect(
        calc
            .update(pose: _poseBothArms(148, 160), timestamp: _t)!
            .repPhase,
        ExerciseRepPhase.bottom,
      );
      // Left arm drops to 141° — below exit threshold → exits to mid.
      expect(
        calc
            .update(pose: _poseBothArms(141, 160), timestamp: _t)!
            .repPhase,
        ExerciseRepPhase.concentric,
      );
    });

    test('stays in top zone until either arm drops below exit (78°)', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      calc.update(pose: _poseBothArms(110, 110), timestamp: _t);
      calc.update(pose: _poseBothArms(60, 60), timestamp: _t); // confirm top

      // Left arm at 76° — below topExitDeg=78 → still in top.
      expect(
        calc
            .update(pose: _poseBothArms(76, 60), timestamp: _t)!
            .repPhase,
        ExerciseRepPhase.top,
      );
      // Left arm rises to 80° — above exit threshold → exits to mid.
      expect(
        calc
            .update(pose: _poseBothArms(80, 60), timestamp: _t)!
            .repPhase,
        ExerciseRepPhase.eccentric,
      );
    });
  });

  group('metrics', () {
    test('emits leftElbowDeg and rightElbowDeg when both arms present', () {
      final r = _calc().update(
        pose: _poseBothArms(160, 160),
        timestamp: _t,
        startSet: true,
      )!;
      expect(r.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightElbowDeg], isNotNull);
    });

    test('emits only leftElbowDeg when only left arm is visible', () {
      final r = _calc().update(pose: _poseLeftOnly(160), timestamp: _t)!;
      expect(r.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightElbowDeg], isNull);
    });
  });

  group('lifecycle', () {
    test('endSet transitions to rest and clears phase', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      calc.update(pose: _poseBothArms(110, 110), timestamp: _t); // concentric

      final r = calc.update(
          pose: _poseBothArms(110, 110), timestamp: _t, endSet: true)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('reps accumulate across sets; reset() clears everything', () {
      final calc = _calc();

      // Set 1: 1 rep.
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      calc.update(pose: _poseBothArms(110, 110), timestamp: _t);
      calc.update(pose: _poseBothArms(60, 60), timestamp: _t);
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, endSet: true);

      // Set 2: 1 more rep → total 2.
      calc.update(
          pose: _poseBothArms(160, 160), timestamp: _t, startSet: true);
      calc.update(pose: _poseBothArms(110, 110), timestamp: _t);
      final r =
          calc.update(pose: _poseBothArms(60, 60), timestamp: _t)!;
      expect(r.reps, 2);

      calc.reset();
      expect(
        calc.update(pose: _poseBothArms(160, 160), timestamp: _t)!.reps,
        0,
      );
    });
  });
}
