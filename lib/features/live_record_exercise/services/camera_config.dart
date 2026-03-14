import 'package:camera/camera.dart';

/// Camera settings for Live Record Exercise.
///
/// Keep this minimal and platform-agnostic.
///
/// Example:
/// ```dart
/// final config = LiveCameraConfig(
///   resolutionPreset: ResolutionPreset.high,
///   enableAudio: false,
/// );
/// ```
class LiveCameraConfig {
  const LiveCameraConfig({
    this.resolutionPreset = ResolutionPreset.high,
    this.enableAudio = false,
    this.imageFormatGroup,
  });

  final ResolutionPreset resolutionPreset;
  final bool enableAudio;

  /// Optional format hint.
  ///
  /// If `null`, the platform default is used.
  final ImageFormatGroup? imageFormatGroup;
}
