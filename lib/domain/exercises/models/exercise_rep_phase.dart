/// Movement phase inside a rep.
///
/// Only meaningful while the set is [ExerciseSetStage.active].
enum ExerciseRepPhase {
  unknown,
  top,
  bottom,
  concentric,
  eccentric,
}
