import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/models/exercise_set_stage.dart';
import 'package:mobile_ai_workout_coach/domain/exercises/set_lifecycle_controller.dart';

void main() {
  test('SetLifecycleController: rest -> countdown -> active', () {
    final controller = SetLifecycleController(
      countdownDuration: const Duration(seconds: 3),
      endSetGraceDuration: const Duration(seconds: 1),
    );

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    expect(controller.stage, ExerciseSetStage.rest);

    // Enter prepare pose => countdown.
    controller.tick(isPreparePose: true, isBreakPose: false, timestamp: t0);
    expect(controller.stage, ExerciseSetStage.countdown);
    expect(controller.countdownRemainingMsAt(t0), 3000);

    // Still counting down.
    final t1 = t0.add(const Duration(milliseconds: 1200));
    controller.tick(isPreparePose: true, isBreakPose: false, timestamp: t1);
    expect(controller.stage, ExerciseSetStage.countdown);
    expect(controller.countdownRemainingMsAt(t1), 1800);

    // Countdown completes => active.
    final t2 = t0.add(const Duration(seconds: 3));
    final ev =
        controller.tick(isPreparePose: true, isBreakPose: false, timestamp: t2);
    expect(controller.stage, ExerciseSetStage.active);
    expect(ev.didStartSet, isTrue);
  });

  test('SetLifecycleController: active ends only after grace period', () {
    final controller = SetLifecycleController(
      countdownDuration: const Duration(seconds: 3),
      endSetGraceDuration: const Duration(seconds: 1),
    );

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    // Start active quickly.
    controller.tick(isPreparePose: true, isBreakPose: false, timestamp: t0);
    controller.tick(
      isPreparePose: true,
      isBreakPose: false,
      timestamp: t0.add(const Duration(seconds: 3)),
    );
    expect(controller.stage, ExerciseSetStage.active);

    // Lose prepare pose briefly but NOT in break pose => still active.
    final tLost = t0.add(const Duration(seconds: 4));
    final ev1 = controller.tick(
      isPreparePose: false,
      isBreakPose: false,
      timestamp: tLost,
    );
    expect(controller.stage, ExerciseSetStage.active);
    expect(ev1.didEndSet, isFalse);

    // Before grace elapses, even in break pose => still active.
    final tBeforeGrace = tLost.add(const Duration(milliseconds: 900));
    controller.tick(
      isPreparePose: false,
      isBreakPose: true,
      timestamp: tBeforeGrace,
    );
    expect(controller.stage, ExerciseSetStage.active);

    // After grace elapses => rest.
    final tAfterGrace = tBeforeGrace.add(const Duration(milliseconds: 1000));
    final ev2 = controller.tick(
      isPreparePose: false,
      isBreakPose: true,
      timestamp: tAfterGrace,
    );
    expect(controller.stage, ExerciseSetStage.rest);
    expect(ev2.didEndSet, isTrue);
  });

  test('SetLifecycleController: breaking prepare pose aborts countdown', () {
    final controller = SetLifecycleController(
      countdownDuration: const Duration(seconds: 3),
      endSetGraceDuration: const Duration(seconds: 1),
    );

    final t0 = DateTime(2026, 1, 1, 0, 0, 0);

    controller.tick(isPreparePose: true, isBreakPose: false, timestamp: t0);
    expect(controller.stage, ExerciseSetStage.countdown);

    controller.tick(
      isPreparePose: false,
      isBreakPose: true,
      timestamp: t0.add(const Duration(milliseconds: 200)),
    );
    expect(controller.stage, ExerciseSetStage.rest);
  });
}
