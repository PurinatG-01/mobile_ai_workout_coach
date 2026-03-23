import 'models/exercise_set_stage.dart';

/// Controls the set lifecycle: rest -> countdown -> active -> rest.
///
/// It intentionally does not know anything about rep mechanics.
class SetLifecycleController {
  SetLifecycleController({
    this.countdownDuration = const Duration(seconds: 3),
    this.endSetGraceDuration = const Duration(seconds: 1),
  });

  final Duration countdownDuration;
  final Duration endSetGraceDuration;

  ExerciseSetStage _stage = ExerciseSetStage.rest;
  DateTime? _countdownStartedAt;
  DateTime? _prepareLostAt;

  ExerciseSetStage get stage => _stage;

  /// Remaining countdown time (milliseconds) at [timestamp].
  ///
  /// Only meaningful in [ExerciseSetStage.countdown]. Returns `null` otherwise.
  int? countdownRemainingMsAt(DateTime timestamp) {
    if (_stage != ExerciseSetStage.countdown) return null;
    final startedAt = _countdownStartedAt;
    if (startedAt == null) return null;
    final elapsed = timestamp.difference(startedAt);
    final remaining = countdownDuration - elapsed;
    final ms = remaining.inMilliseconds;
    return ms > 0 ? ms : 0;
  }

  /// Resets lifecycle back to [ExerciseSetStage.rest].
  void reset() {
    _stage = ExerciseSetStage.rest;
    _countdownStartedAt = null;
    _prepareLostAt = null;
  }

  /// Advances the state machine.
  ///
  /// - [isPreparePose] is a (possibly exercise-specific) predicate.
  /// - [isBreakPose] indicates the user has left the exercise/prepare context
  ///   and is in a "break" posture; set end is gated on this.
  /// - Returns a tuple describing whether the set was started/ended on this tick.
  ({bool didStartSet, bool didEndSet}) tick({
    required bool isPreparePose,
    required bool isBreakPose,
    required DateTime timestamp,
  }) {
    var didStartSet = false;
    var didEndSet = false;

    switch (_stage) {
      case ExerciseSetStage.rest:
        _prepareLostAt = null;
        if (isPreparePose) {
          _stage = ExerciseSetStage.countdown;
          _countdownStartedAt = timestamp;
        }
        break;

      case ExerciseSetStage.countdown:
        if (!isPreparePose) {
          // Abort countdown if user breaks prepare pose.
          reset();
          break;
        }

        final startedAt = _countdownStartedAt ?? timestamp;
        _countdownStartedAt ??= timestamp;
        final elapsed = timestamp.difference(startedAt);
        if (elapsed >= countdownDuration) {
          _stage = ExerciseSetStage.active;
          _prepareLostAt = null;
          didStartSet = true;
        }
        break;

      case ExerciseSetStage.active:
        if (!isBreakPose) {
          _prepareLostAt = null;
          break;
        }

        _prepareLostAt ??= timestamp;
        final lostAt = _prepareLostAt!;
        if (timestamp.difference(lostAt) >= endSetGraceDuration) {
          _stage = ExerciseSetStage.rest;
          _countdownStartedAt = null;
          _prepareLostAt = null;
          didEndSet = true;
        }
        break;
    }

    return (didStartSet: didStartSet, didEndSet: didEndSet);
  }
}
