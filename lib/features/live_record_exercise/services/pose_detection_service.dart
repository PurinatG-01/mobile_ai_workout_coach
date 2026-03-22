import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Minimal ML Kit pose detection wrapper for live camera streams.
///
/// Responsibilities:
/// - Own a [PoseDetector] instance.
/// - Convert [CameraImage] frames into [InputImage].
/// - Provide a simple throttle/lock to avoid overlapping in-flight inferences.
class PoseDetectionService {
  PoseDetectionService({
    PoseDetectorOptions? options,
    this.minProcessInterval = const Duration(milliseconds: 120),
  }) : _poseDetector = PoseDetector(
          options:
              options ?? PoseDetectorOptions(mode: PoseDetectionMode.stream),
        );

  final PoseDetector _poseDetector;

  /// Minimum time between processed frames.
  final Duration minProcessInterval;

  final Map<DeviceOrientation, int> _orientations = const {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  bool _isClosed = false;
  bool _isProcessing = false;
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _poseDetector.close();
  }

  bool get isBusy => _isProcessing;

  /// Processes a live [CameraImage] and returns a list of detected poses.
  ///
  /// Returns `null` when the frame is skipped (throttled, busy, invalid format).
  Future<List<Pose>?> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    if (_isClosed) return null;

    final now = DateTime.now();
    if (_isProcessing) return null;
    if (now.difference(_lastProcessedAt) < minProcessInterval) return null;

    final inputImage = _inputImageFromCameraImage(
      image: image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    if (inputImage == null) return null;

    _isProcessing = true;
    try {
      final poses = await _poseDetector.processImage(inputImage);
      _lastProcessedAt = now;
      return poses;
    } catch (e) {
      // Keep the service resilient in live mode.
      debugPrint('PoseDetectionService error: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    // Rotation is used on Android to convert input; on iOS it is mainly used
    // for coordinate compensation.
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[deviceOrientation];
      if (rotationCompensation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }

      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) return null;

    // Validate format depending on platform.
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;

    // For NV21/BGRA8888 we expect a single plane.
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
