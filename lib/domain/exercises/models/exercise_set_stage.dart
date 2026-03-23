/// High-level lifecycle for a set.
///
/// This is intentionally separate from rep movement phases.
enum ExerciseSetStage {
  /// Between sets (default state).
  rest,

  /// User is in the prepare pose and we're counting down before starting.
  countdown,

  /// Set is active; rep counting/phase detection is enabled.
  active,
}
