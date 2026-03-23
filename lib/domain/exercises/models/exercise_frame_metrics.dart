import 'exercise_metric.dart';

/// Strongly-typed container for per-frame metrics.
class ExerciseFrameMetrics {
  ExerciseFrameMetrics([Map<ExerciseMetric, double>? values])
      : values = values ?? <ExerciseMetric, double>{};

  final Map<ExerciseMetric, double> values;

  double? operator [](ExerciseMetric metric) => values[metric];

  void operator []=(ExerciseMetric metric, double value) {
    values[metric] = value;
  }

  bool get isEmpty => values.isEmpty;
  bool get isNotEmpty => values.isNotEmpty;
}
