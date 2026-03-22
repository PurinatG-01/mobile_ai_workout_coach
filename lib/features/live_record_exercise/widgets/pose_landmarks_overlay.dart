import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseLandmarksOverlay extends StatelessWidget {
  const PoseLandmarksOverlay({
    required this.pose,
    required this.sourceSize,
    required this.mirrorHorizontally,
    super.key,
  });

  /// The pose to draw. If null, nothing is painted.
  final Pose? pose;

  /// The coordinate space the pose landmarks are reported in.
  ///
  /// For live streams this should match the oriented preview size.
  final Size sourceSize;

  /// Whether to mirror the x-axis (front camera behavior).
  final bool mirrorHorizontally;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PoseLandmarksPainter(
          pose: pose,
          sourceSize: sourceSize,
          mirrorHorizontally: mirrorHorizontally,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _PoseLandmarksPainter extends CustomPainter {
  _PoseLandmarksPainter({
    required this.pose,
    required this.sourceSize,
    required this.mirrorHorizontally,
    required this.color,
  });

  final Pose? pose;
  final Size sourceSize;
  final bool mirrorHorizontally;
  final Color color;

  static const _faceLandmarkTypes = <PoseLandmarkType>{
    PoseLandmarkType.nose,
    PoseLandmarkType.leftEyeInner,
    PoseLandmarkType.leftEye,
    PoseLandmarkType.leftEyeOuter,
    PoseLandmarkType.rightEyeInner,
    PoseLandmarkType.rightEye,
    PoseLandmarkType.rightEyeOuter,
    PoseLandmarkType.leftEar,
    PoseLandmarkType.rightEar,
    PoseLandmarkType.leftMouth,
    PoseLandmarkType.rightMouth,
  };

  Offset? _landmarkOffset({
    required Pose pose,
    required PoseLandmarkType type,
    required Size canvasSize,
    required double sx,
    required double sy,
  }) {
    final landmark = pose.landmarks[type];
    if (landmark == null) return null;

    final dx = landmark.x * sx;
    final dy = landmark.y * sy;
    final x = mirrorHorizontally ? (canvasSize.width - dx) : dx;
    final y = dy;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pose = this.pose;
    if (pose == null) return;

    if (sourceSize.width <= 0 || sourceSize.height <= 0) return;

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.95);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.35);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = color.withOpacity(0.55);

    final sx = size.width / sourceSize.width;
    final sy = size.height / sourceSize.height;

    const connections = <List<PoseLandmarkType>>[
      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],

      // Left arm
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],

      // Right arm
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],

      // Left leg
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],

      // Right leg
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    // Draw lines first so dots sit on top.
    for (final c in connections) {
      final p1 = _landmarkOffset(
        pose: pose,
        type: c[0],
        canvasSize: size,
        sx: sx,
        sy: sy,
      );
      final p2 = _landmarkOffset(
        pose: pose,
        type: c[1],
        canvasSize: size,
        sx: sx,
        sy: sy,
      );
      if (p1 == null || p2 == null) continue;
      canvas.drawLine(p1, p2, linePaint);
    }

    for (final landmark in pose.landmarks.values) {
      if (_faceLandmarkTypes.contains(landmark.type)) {
        continue;
      }

      final dx = landmark.x * sx;
      final dy = landmark.y * sy;
      final x = mirrorHorizontally ? (size.width - dx) : dx;
      final y = dy;

      final p = Offset(x, y);

      // Outer ring for contrast
      canvas.drawCircle(p, 4.5, outlinePaint);
      canvas.drawCircle(p, 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoseLandmarksPainter oldDelegate) {
    // Repaint when pose instance or sizing changes.
    return oldDelegate.pose != pose ||
        oldDelegate.sourceSize != sourceSize ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.color != color;
  }
}
