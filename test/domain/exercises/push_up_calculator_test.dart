import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/calculators/push_up_calculator.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_metric.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_rep_phase.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

// ── Pose builders ─────────────────────────────────────────────────────────────

PoseLandmark _lm(PoseLandmarkType type, double x, double y) =>
    PoseLandmark(type: type, x: x, y: y, z: 0, likelihood: 1);

/// Left arm only. Shoulder at (1, 0), elbow at origin, wrist at (cos θ, sin θ).
/// Gives shoulder→elbow→wrist angle = deg.
Pose _poseLeft(double deg) {
  final rad = deg * math.pi / 180;
  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder: _lm(PoseLandmarkType.leftShoulder, 1, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 0),
    PoseLandmarkType.leftWrist:
        _lm(PoseLandmarkType.leftWrist, math.cos(rad), math.sin(rad)),
  });
}

/// Both arms. Scale controls segment length used for best-arm selection.
/// Larger scale → selected as "best visible" arm by the calculator.
Pose _poseBothArms(
    double leftDeg, double leftScale, double rightDeg, double rightScale) {
  final lRad = leftDeg * math.pi / 180;
  final rRad = rightDeg * math.pi / 180;
  const rOff = 10.0;
  return Pose(landmarks: {
    PoseLandmarkType.leftShoulder:
        _lm(PoseLandmarkType.leftShoulder, leftScale, 0),
    PoseLandmarkType.leftElbow: _lm(PoseLandmarkType.leftElbow, 0, 0),
    PoseLandmarkType.leftWrist: _lm(PoseLandmarkType.leftWrist,
        leftScale * math.cos(lRad), leftScale * math.sin(lRad)),
    PoseLandmarkType.rightShoulder:
        _lm(PoseLandmarkType.rightShoulder, rOff + rightScale, 0),
    PoseLandmarkType.rightElbow: _lm(PoseLandmarkType.rightElbow, rOff, 0),
    PoseLandmarkType.rightWrist: _lm(PoseLandmarkType.rightWrist,
        rOff + rightScale * math.cos(rRad), rightScale * math.sin(rRad)),
  });
}

/// Right arm only — left arm landmarks absent.
Pose _poseRight(double deg) {
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

PushUpCalculator _calc() => PushUpCalculator(lifecycle: _lifecycle());

final _t = DateTime(2026, 1, 1);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Thresholds (from PushUpCalculator):
  //   top    entry=155°  exit=145°
  //   bottom entry=95°   exit=103°
  //
  // Zone transitions require 2 frames: one exits the current zone → mid,
  // the next enters the new zone. Angle guide:
  //   top=165°  mid=125°  bottom=80°

  group('rep counting', () {
    test('top → bottom → top counts 1 rep', () {
      final calc = _calc();

      final r0 =
          calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true)!;
      expect(r0.setStage, ExerciseSetStage.active);
      expect(r0.repPhase, ExerciseRepPhase.top);
      expect(r0.reps, 0);

      calc.update(pose: _poseLeft(125), timestamp: _t); // top → mid (eccentric)
      calc.update(pose: _poseLeft(80), timestamp: _t);  // mid → bottom
      calc.update(pose: _poseLeft(125), timestamp: _t); // bottom → mid (concentric)
      final r = calc.update(pose: _poseLeft(165), timestamp: _t)!; // mid → top
      expect(r.repPhase, ExerciseRepPhase.top);
      expect(r.reps, 1);

      // Holding top must not double-count.
      expect(calc.update(pose: _poseLeft(170), timestamp: _t)!.reps, 1);
    });

    test('partial descent without reaching bottom counts 0 reps', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);

      // 125° is above bottomEntryDeg=95 → never enters bottom zone.
      calc.update(pose: _poseLeft(125), timestamp: _t);
      final r = calc.update(pose: _poseLeft(165), timestamp: _t)!;
      expect(r.reps, 0);
    });

    test('3 reps count correctly', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);

      for (var i = 0; i < 3; i++) {
        calc.update(pose: _poseLeft(125), timestamp: _t); // top → mid
        calc.update(pose: _poseLeft(80), timestamp: _t);  // mid → bottom
        calc.update(pose: _poseLeft(125), timestamp: _t); // bottom → mid
        calc.update(pose: _poseLeft(165), timestamp: _t); // mid → top → rep+1
      }
      expect(calc.update(pose: _poseLeft(165), timestamp: _t)!.reps, 3);
    });
  });

  group('phase detection', () {
    test('repPhase is unknown when set is not active', () {
      final r = _calc().update(pose: _poseLeft(165), timestamp: _t)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('repPhase is unknown before any zone extreme is confirmed', () {
      final calc = _calc();
      // Start at mid angle — neither top nor bottom zone entered yet.
      final r =
          calc.update(pose: _poseLeft(125), timestamp: _t, startSet: true)!;
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('mid zone after bottom confirmed is concentric', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      calc.update(pose: _poseLeft(80), timestamp: _t); // confirm bottom
      final r = calc.update(pose: _poseLeft(125), timestamp: _t)!; // bottom → mid
      expect(r.repPhase, ExerciseRepPhase.concentric);
    });

    test('mid zone after top confirmed is eccentric', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true); // top
      final r = calc.update(pose: _poseLeft(125), timestamp: _t)!; // top → mid
      expect(r.repPhase, ExerciseRepPhase.eccentric);
    });
  });

  group('hysteresis', () {
    test('stays in top zone until elbow drops below exit threshold (145°)', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);

      // 147° is above topExitDeg=145 → still in top.
      expect(
        calc.update(pose: _poseLeft(147), timestamp: _t)!.repPhase,
        ExerciseRepPhase.top,
      );
      // 143° drops below topExitDeg=145 → exits to mid.
      expect(
        calc.update(pose: _poseLeft(143), timestamp: _t)!.repPhase,
        ExerciseRepPhase.eccentric,
      );
    });

    test('stays in bottom zone until elbow rises above exit threshold (103°)',
        () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      calc.update(pose: _poseLeft(80), timestamp: _t); // in bottom

      // 101° is below bottomExitDeg=103 → still in bottom.
      expect(
        calc.update(pose: _poseLeft(101), timestamp: _t)!.repPhase,
        ExerciseRepPhase.bottom,
      );
      // 105° rises above bottomExitDeg=103 → exits to mid.
      expect(
        calc.update(pose: _poseLeft(105), timestamp: _t)!.repPhase,
        ExerciseRepPhase.concentric,
      );
    });
  });

  group('missing landmarks', () {
    test('frame with no arm landmarks is skipped; state is preserved', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);

      final r = calc.update(pose: Pose(landmarks: {}), timestamp: _t)!;
      expect(r.setStage, ExerciseSetStage.active);
      expect(r.repPhase, ExerciseRepPhase.top); // preserved
      expect(r.reps, 0);
    });
  });

  group('arm locking', () {
    test('locks best arm at set start and ignores score flip mid-set', () {
      final calc = _calc();
      // Left arm (scale=2, top angle) is best; right arm (scale=1, bottom angle).
      final start = _poseBothArms(165, 2.0, 80, 1.0);
      final r0 = calc.update(pose: start, timestamp: _t, startSet: true)!;
      expect(r0.repPhase, ExerciseRepPhase.top); // left arm used

      // Flip scores: right now has scale=2 (would be "best" without locking).
      final flipped = _poseBothArms(165, 1.0, 80, 2.0);
      expect(
        calc.update(pose: flipped, timestamp: _t)!.repPhase,
        ExerciseRepPhase.top, // still locked to left
      );
    });

    test('falls back to visible arm when locked arm disappears', () {
      final calc = _calc();
      calc.update(
          pose: _poseBothArms(165, 2.0, 80, 1.0),
          timestamp: _t,
          startSet: true); // locks left at top

      // Left disappears; only right arm (at 80° = bottom angle) remains.
      calc.update(pose: _poseRight(80), timestamp: _t); // exits top → mid
      final r = calc.update(pose: _poseRight(80), timestamp: _t)!; // mid → bottom
      expect(r.repPhase, ExerciseRepPhase.bottom);
    });
  });

  group('metrics', () {
    test('emits leftElbowDeg and rightElbowDeg when both arms present', () {
      final r = _calc().update(
        pose: _poseBothArms(165, 1.0, 165, 1.0),
        timestamp: _t,
        startSet: true,
      )!;
      expect(r.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightElbowDeg], isNotNull);
    });

    test('emits only leftElbowDeg when only left arm is visible', () {
      final r =
          _calc().update(pose: _poseLeft(165), timestamp: _t, startSet: true)!;
      expect(r.metrics[ExerciseMetric.leftElbowDeg], isNotNull);
      expect(r.metrics[ExerciseMetric.rightElbowDeg], isNull);
    });
  });

  group('lifecycle', () {
    test('endSet transitions to rest and clears phase', () {
      final calc = _calc();
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(125), timestamp: _t); // eccentric

      final r =
          calc.update(pose: _poseLeft(125), timestamp: _t, endSet: true)!;
      expect(r.setStage, ExerciseSetStage.rest);
      expect(r.repPhase, ExerciseRepPhase.unknown);
    });

    test('reps accumulate across sets; reset() clears everything', () {
      final calc = _calc();

      // Set 1: 1 rep.
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      calc.update(pose: _poseLeft(80), timestamp: _t);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      calc.update(pose: _poseLeft(165), timestamp: _t);
      calc.update(pose: _poseLeft(165), timestamp: _t, endSet: true);

      // Set 2: 1 more rep → total 2.
      calc.update(pose: _poseLeft(165), timestamp: _t, startSet: true);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      calc.update(pose: _poseLeft(80), timestamp: _t);
      calc.update(pose: _poseLeft(125), timestamp: _t);
      final r = calc.update(pose: _poseLeft(165), timestamp: _t)!;
      expect(r.reps, 2);

      calc.reset();
      expect(
        calc.update(pose: _poseLeft(165), timestamp: _t)!.reps,
        0,
      );
    });
  });
}
