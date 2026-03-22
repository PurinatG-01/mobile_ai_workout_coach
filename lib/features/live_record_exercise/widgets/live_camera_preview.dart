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

    // Avoid stretching: preserve the camera stream aspect ratio and let it
    // “contain” within the available box.
    //
    // Note: `controller.value.aspectRatio` can be reported in the camera
    // sensor/native orientation, which means it may need to be inverted when
    // the UI is in portrait.
    final uiOrientation = MediaQuery.of(context).orientation;
    final previewSize = controller.value.previewSize;

    double effectiveAspectRatio;
    if (previewSize != null &&
        previewSize.width > 0 &&
        previewSize.height > 0) {
      final previewAspect = previewSize.width / previewSize.height;
      effectiveAspectRatio = uiOrientation == Orientation.portrait
          ? (1 / previewAspect)
          : previewAspect;
    } else {
      final reported = controller.value.aspectRatio;
      final needsInversion =
          (uiOrientation == Orientation.portrait && reported > 1) ||
              (uiOrientation == Orientation.landscape && reported < 1);
      effectiveAspectRatio = needsInversion ? (1 / reported) : reported;
    }

    // Fill the available space while preserving the camera aspect ratio.
    // Any overflow is cropped, matching a typical "full-screen camera" UX.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        // Fall back to a simple AspectRatio if we can't determine constraints.
        if (maxWidth <= 0 || maxHeight <= 0) {
          return Center(
            child: AspectRatio(
              aspectRatio: effectiveAspectRatio,
              child: CameraPreview(controller),
            ),
          );
        }

        final containerAspectRatio = maxWidth / maxHeight;
        final rawScale = effectiveAspectRatio / containerAspectRatio;
        final scale = rawScale < 1 ? (1 / rawScale) : rawScale;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(
              child: AspectRatio(
                aspectRatio: effectiveAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}
