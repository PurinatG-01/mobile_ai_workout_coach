/// Typed metric keys produced by an [ExerciseCalculator].
///
/// Add new values as new exercises/metrics are introduced.
enum ExerciseMetric {
  // Common joint angles (degrees)
  leftElbowDeg,
  rightElbowDeg,
  leftShoulderDeg,
  rightShoulderDeg,
  leftKneeDeg,
  rightKneeDeg,
  leftHipDeg,
  rightHipDeg,

  // Pose-level misc
  torsoInclineDeg,
}
