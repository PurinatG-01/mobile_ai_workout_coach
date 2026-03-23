import 'package:mobile_ai_workout_coach/common/models/exercise_type.dart';

import 'calculators/bicep_curl_calculator.dart';
import 'calculators/pull_up_calculator.dart';
import 'calculators/push_up_calculator.dart';
import 'calculators/squat_calculator.dart';
import 'exercise_calculator.dart';

class ExerciseCalculatorFactory {
  const ExerciseCalculatorFactory();

  ExerciseCalculator create(ExerciseType type) {
    switch (type) {
      case ExerciseType.squat:
        return SquatCalculator();
      case ExerciseType.pushUp:
        return PushUpCalculator();
      case ExerciseType.bicepCurl:
        return BicepCurlCalculator();
      case ExerciseType.pullUp:
        return PullUpCalculator();
    }
  }
}
