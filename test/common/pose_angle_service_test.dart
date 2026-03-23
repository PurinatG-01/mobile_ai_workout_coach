import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ai_workout_coach/common/services/pose_angle_service.dart';
import 'package:mobile_ai_workout_coach/common/utils/angle_calculator.dart';

void main() {
  group('AngleCalculator', () {
    test('angleDegrees returns 90 degrees for a right angle', () {
      const calc = AngleCalculator();
      final angle = calc.angleDegrees(
        a: (x: 1, y: 0),
        b: (x: 0, y: 0),
        c: (x: 0, y: 1),
      );
      expect(angle, closeTo(90.0, 1e-9));
    });

    test('angleDegreesOrNull returns null when undefined', () {
      const calc = AngleCalculator();
      final angle = calc.angleDegreesOrNull(
        a: (x: 0, y: 0),
        b: (x: 0, y: 0),
        c: (x: 1, y: 1),
      );
      expect(angle, isNull);
    });
  });

  group('PoseAngleService', () {
    test('angleDegreesFromPoints returns 180 degrees for a straight line', () {
      const service = PoseAngleService();
      final angle = service.angleDegreesFromPoints(
        a: (x: -1, y: 0),
        b: (x: 0, y: 0),
        c: (x: 1, y: 0),
      );
      expect(angle, closeTo(180.0, 1e-9));
    });
  });
}
