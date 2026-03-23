import 'dart:math' as math;

class AngleCalculator {
  const AngleCalculator();

  double angleDegrees({
    required ({double x, double y}) a,
    required ({double x, double y}) b,
    required ({double x, double y}) c,
  }) {
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;

    final dot = abx * cbx + aby * cby;
    final mag1 = math.sqrt(abx * abx + aby * aby);
    final mag2 = math.sqrt(cbx * cbx + cby * cby);

    if (mag1 == 0 || mag2 == 0) {
      return 0;
    }

    final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    final radians = math.acos(cosTheta);
    return radians * (180.0 / math.pi);
  }

  /// Like [angleDegrees], but returns `null` when the angle is undefined
  /// (e.g. when any segment has zero length).
  double? angleDegreesOrNull({
    required ({double x, double y}) a,
    required ({double x, double y}) b,
    required ({double x, double y}) c,
  }) {
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;

    final dot = abx * cbx + aby * cby;
    final mag1 = math.sqrt(abx * abx + aby * aby);
    final mag2 = math.sqrt(cbx * cbx + cby * cby);

    if (mag1 == 0 || mag2 == 0) {
      return null;
    }

    final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    final radians = math.acos(cosTheta);
    return radians * (180.0 / math.pi);
  }
}
