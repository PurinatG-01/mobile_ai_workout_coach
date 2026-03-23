enum ExerciseType {
  squat('Squat'),
  pushUp('Push-up'),
  bicepCurl('Bicep curl'),
  pullUp('Pull-up');

  const ExerciseType(this.displayName);

  final String displayName;
}
