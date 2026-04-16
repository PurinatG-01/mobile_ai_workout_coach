import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/squat_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_metric.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_rep_phase.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

// ── Pose builders ─────────────────────────────────────────────────────────────

PoseLandmark _lm(PoseLandmarkType type, double x, double y) =>
    PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: 1);

/// Left leg only. Knee at origin, hip at (scale, 0), ankle at the angle.
/// Gives knee angle = deg. Scale controls the segment-length visibility score.
Pose _poseLeft(double deg, {double scale = 1.0}) {
  final rad = deg * math.pi / 180;
  return Pose(landmarks: {
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, scale, 0),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, 0, 0),
    PoseLandmarkType.leftAnkle: _lm(
        PoseLandmarkType.leftAnkle, scale * math.cos(rad), scale * math.sin(rad)),
  });
}

/// Both legs. Scale controls which leg is selected as "best visible".
Pose _poseBothLegs(
    double leftDeg, double leftScale, double rightDeg, double rightScale) {
  final lRad = leftDeg * math.pi / 180;
  final rRad = rightDeg * math.pi / 180;
  const rOff = 10.0;
  return Pose(landmarks: {
    PoseLandmarkType.leftHip: _lm(PoseLandmarkType.leftHip, leftScale, 0),
    PoseLandmarkType.leftKnee: _lm(PoseLandmarkType.leftKnee, 0, 0),
    PoseLandmarkType.leftAnkle: _lm(PoseLandmarkType.leftAnkle,
        leftScale * math.cos(lRad), leftScale * math.sin(lRad)),
    PoseLandmarkType.rightHip:
        _lm(PoseLandmarkType.rightHip, rOff + rightScale, 0),
    PoseLandmarkType.rightKnee: _lm(PoseLandmarkType.rightKnee, rOff, 0),
    PoseLandmarkType.rightAnkle: _lm(PoseLandmarkType.rightAnkle,
        rOff + rightScale * math.cos(rRad), rightScale * math.sin(rRad)),
  });
}

/// Right leg only, offset so it doesn't overlap the left leg origin.
Pose _poseRight(double deg, {double scale = 1.0}) {
  final rad = deg * math.pi / 180;
  const rOff = 10.0;
  return Pose(landmarks: {
    PoseLandmarkType.rightHip:
        _lm(PoseLandmarkType.rightHip, rOff + scale, 0),
    PoseLandmarkType.rightKnee: _lm(PoseLandmarkType.rightKnee, rOff, 0),
    PoseLandmarkType.rightAnkle: _lm(PoseLandmarkType.rightAnkle,
        rOff + scale * math.cos(rad), scale * math.sin(rad)),
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

SetLifecycleController _lifecycle() => SetLifecycleController(
      countdownDuration: Duration.zero,
      endSetGraceDuration: Duration.zero,
    );

SquatCalculator _calc() => SquatCalculator(lifecycle: _lifecycle());

final _t = DateTime(2026, 1, 1);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Thresholds (from SquatCalculator):
  //   top    entry=160°  exit=150°
  //   bottom entry=125°  exit=133°
  //
  // Zone transitions require 2 frames: one exits the current zone → mid,
  // the next enters the new zone. Angle guide:
  //   top=170°  mid=145°  bottom=118°

  group('rep counting', () {
    test('top → bottom → top counts 1 rep', () {
      final calc = _calc();

      final r0 =
          calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true)!;
      expect(r0.setStage, ExerciseSetStage.active);
      expect(r0.repPhase, ExerciseRepPhase.top);
      expect(r0.reps, 0);

      calc.update(pose: _poseLeft(145), timestamp: _t); // top → mid (eccentric)
      calc.update(pose: _poseLeft(118), timestamp: _t); // mid → bottom
      calc.update(pose: _poseLeft(145), timestamp: _t); // bottom → mid (concentric)
      final r = calc.update(pose: _poseLeft(170), timestamp: _t)!; // mid → top
      expect(r.repPhase, ExerciseRepPhase.top);
      expect(r.reps, 1);

      // Holding top must not double-count.
      expect(calc.update(pose: _poseLeft(175), timestamp: _t)!.reps, 1);
    });

    test('partial descent without reaching bottom counts 0 reps', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);

      // Mid zone (145°) but never hits ≤ 125° (bottom entry threshold).
      calc.update(pose: _poseLeft(145), timestamp: _t);
      final r = calc.update(pose: _poseLeft(170), timestamp: _t)!;
      expect(r.reps, 0);
    });

    test('3 reps count correctly', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);

      for (var i = 0; i < 3; i++) {
        calc.update(pose: _poseLeft(145), timestamp: _t); // top → mid
        calc.update(pose: _poseLeft(118), timestamp: _t); // mid → bottom
        calc.update(pose: _poseLeft(145), timestamp: _t); // bottom → mid
        calc.update(pose: _poseLeft(170), timestamp: _t); // mid → top → rep+1
      }
      expect(calc.update(pose: _poseLeft(175), timestamp: _t)!.reps, 3);
    });
  });

  group('phase detection', () {
    test('repPhase is unknown when set is not active', () {
      final r = _calc().update(pose: _poseLeft(170), timestamp: _t)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('repPhase is unknown before any zone extreme is confirmed', () {
      final calc = _calc();
      // Start at mid angle — neither top nor bottom zone entered yet.
      final r =
          calc.update(pose: _poseLeft(145), timestamp: _t, startSet: true)!;
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('mid zone after bottom confirmed is concentric', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(145), timestamp: _t); // top → mid
      calc.update(pose: _poseLeft(118), timestamp: _t); // mid → bottom
      final r = calc.update(pose: _poseLeft(145), timestamp: _t)!; // bottom → mid
      expect(r.repPhase, ExerciseRepPhase.concentric);
    });

    test('mid zone after top confirmed is eccentric', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true); // top
      final r = calc.update(pose: _poseLeft(145), timestamp: _t)!; // top → mid
      expect(r.repPhase, ExerciseRepPhase.eccentric);
    });
  });

  group('hysteresis', () {
    test('stays in top zone until knee drops below exit threshold (150°)', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);

      // 155° is above topExitDeg=150 → still in top.
      expect(
        calc.update(pose: _poseLeft(155), timestamp: _t)!.repPhase,
        ExerciseRepPhase.top,
      );
      // 148° drops below topExitDeg=150 → exits to mid.
      expect(
        calc.update(pose: _poseLeft(148), timestamp: _t)!.repPhase,
        ExerciseRepPhase.eccentric,
      );
    });

    test('stays in bottom zone until knee rises above exit threshold (133°)',
        () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      calc.update(pose: _poseLeft(118), timestamp: _t); // in bottom

      // 130° is below bottomExitDeg=133 → still in bottom.
      expect(
        calc.update(pose: _poseLeft(130), timestamp: _t)!.repPhase,
        ExerciseRepPhase.bottom,
      );
      // 135° rises above bottomExitDeg=133 → exits to mid.
      expect(
        calc.update(pose: _poseLeft(135), timestamp: _t)!.repPhase,
        ExerciseRepPhase.concentric,
      );
    });
  });

  group('missing landmarks', () {
    test('frame with no leg landmarks is skipped; state is preserved', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);

      // Empty pose — no landmarks at all.
      final r = calc.update(pose: Pose(landmarks: {}), timestamp: _t)!;
      expect(r.setStage, ExerciseSetStage.active);
      expect(r.repPhase, ExerciseRepPhase.top); // state unchanged
      expect(r.reps, 0);
    });
  });

  group('leg locking', () {
    test('locks best leg at set start and ignores score flip mid-set', () {
      final calc = _calc();
      // Left leg (scale=2) is best and at top; right leg (scale=1) is at bottom.
      final start = _poseBothLegs(170, 2.0, 118, 1.0);
      final r0 = calc.update(pose: start, timestamp: _t, startSet: true)!;
      expect(r0.repPhase, ExerciseRepPhase.top); // left leg used

      // Flip scores: right now has scale=2 but is at bottom angle.
      // Without locking, phase would switch to bottom.
      final flipped = _poseBothLegs(170, 1.0, 118, 2.0);
      expect(
        calc.update(pose: flipped, timestamp: _t)!.repPhase,
        ExerciseRepPhase.top, // still locked to left
      );
    });

    test('falls back to visible leg when locked leg disappears', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothLegs(170, 2.0, 118, 1.0),
          timestamp: _t,
          startSet: true);

      // Left leg disappears; only right leg (118° = bottom angle) remains.
      calc.update(pose: _poseRight(118), timestamp: _t); // exits top → mid
      final r = calc.update(pose: _poseRight(118), timestamp: _t)!; // mid → bottom
      expect(r.repPhase, ExerciseRepPhase.bottom);
    });
  });

  group('metrics', () {
    test('emits leftKneeDeg and rightKneeDeg when both legs present', () {
      final r = _calc().update(
        pose: _poseBothLegs(170, 1.0, 165, 1.0),
        timestamp: _t,
        startSet: true,
      )!;
      expect(r.metrics[ExerciseMetric.leftKneeDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightKneeDeg], isNotNull);
    });

    test('emits only leftKneeDeg when only left leg is visible', () {
      final r = _calc()
          .update(pose: _poseLeft(170), timestamp: _t, startSet: true)!;
      expect(r.metrics[ExerciseMetric.leftKneeDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightKneeDeg], isNull);
    });
  });

  group('lifecycle', () {
    test('endSet transitions to rest and clears phase', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      calc.update(pose: _poseLeft(118), timestamp: _t); // in bottom

      final r =
          calc.update(pose: _poseLeft(118), timestamp: _t, endSet: true)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('reps accumulate across sets; reset() clears everything', () {
      final calc = _calc();

      // Set 1: 1 rep.
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      calc.update(pose: _poseLeft(118), timestamp: _t);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      calc.update(pose: _poseLeft(170), timestamp: _t);
      calc.update(pose: _poseLeft(170), timestamp: _t, endSet: true);

      // Set 2: 1 more rep → total 2.
      calc.update(pose: _poseLeft(170), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      calc.update(pose: _poseLeft(118), timestamp: _t);
      calc.update(pose: _poseLeft(145), timestamp: _t);
      final r = calc.update(pose: _poseLeft(170), timestamp: _t)!;
      expect(r.reps, 2);

      calc.reset();
      expect(
        calc.update(pose: _poseLeft(170), timestamp: _t)!.reps,
        0,
      );
    });
  });
}
