import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// A reusable camera preview widget for the Live Record Exercise epic.
///
/// This widget is intentionally “dumb”: it renders the [CameraController]
/// state, but does not initialize/dispose the controller.
///
/// Usage example:
/// ```dart
/// final controller = service.controller;
/// if (controller == null) return const Text('Not initialized');
///
/// return LiveCameraPreview(
///   controller: controller,
///   placeholder: const Text('Initializing camera...'),
/// );
/// ```
class LiveCameraPreview extends StatelessWidget {
  const LiveCameraPreview({
    required this.controller,
    this.placeholder,
    this.errorBuilder,
    super.key,
  });

  final CameraController controller;

  /// Shown while the controller is initializing.
  final Widget? placeholder;

  /// Optional custom error UI.
  ///
  /// If not provided, a basic error message is rendered.
  final Widget Function(BuildContext context, CameraException error)?
      errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (controller.value.hasError) {
      final errorDescription = controller.value.errorDescription;
      final error = CameraException(
        'camera_error',
        errorDescription ?? 'Unknown camera error.',
      );
      if (errorBuilder != null) {
        return errorBuilder!(context, error);
      }

      return Center(
        child: Text(
          error.description ?? 'Camera error',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!controller.value.isInitialized) {
      return Center(
        child: placeholder ?? const CircularProgressIndicator(),
      );
    }

    return CameraPreview(controller);
  }
}
