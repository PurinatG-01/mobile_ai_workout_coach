import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../utils/angle_calculator.dart';

/// Utilities for computing joint angles from ML Kit pose landmarks.
///
/// Angles are returned in degrees in the range [0, 180].
class PoseAngleService {
  const PoseAngleService({
    this.angleCalculator = const AngleCalculator(),
  });

  final AngleCalculator angleCalculator;

  /// Computes the angle (in degrees) for three 2D points with the vertex at [b].
  ///
  /// Returns `null` if the angle is undefined (e.g. any segment length is zero).
  double? angleDegreesFromPoints({
    required ({double x, double y}) a,
    required ({double x, double y}) b,
    required ({double x, double y}) c,
  }) {
    return angleCalculator.angleDegreesOrNull(a: a, b: b, c: c);
  }

  /// Computes the joint angle (in degrees) for a pose using three landmark types.
  ///
  /// Example (left elbow):
  /// - [a] = [PoseLandmarkType.leftShoulder]
  /// - [b] = [PoseLandmarkType.leftElbow]
  /// - [c] = [PoseLandmarkType.leftWrist]
  ///
  /// Returns `null` when any of the landmarks are missing.
  double? angleDegreesFromPose({
    required Pose pose,
    required PoseLandmarkType a,
    required PoseLandmarkType b,
    required PoseLandmarkType c,
  }) {
    final la = pose.landmarks[a];
    final lb = pose.landmarks[b];
    final lc = pose.landmarks[c];

    if (la == null || lb == null || lc == null) {
      return null;
    }

    return angleDegreesFromPoints(
      a: (x: la.x, y: la.y),
      b: (x: lb.x, y: lb.y),
      c: (x: lc.x, y: lc.y),
    );
  }
}
