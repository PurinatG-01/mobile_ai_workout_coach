import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'camera_config.dart';

/// Connects to the native device camera (iOS/Android) and exposes a
/// [CameraController] that UI widgets can render.
///
/// This service is intentionally UI-agnostic: it does not render widgets and
/// it does not own app navigation/state.
///
/// Usage example:
/// ```dart
/// final service = LiveCameraService();
/// await service.initialize(const LiveCameraConfig());
/// final controller = service.controller;
/// // Pass controller to a preview widget.
///
/// // Later:
/// await service.dispose();
/// ```
class LiveCameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  CameraController? get controller => _controller;

  List<CameraDescription> get cameras =>
      List.unmodifiable(_cameras ?? const []);

  CameraDescription? get selectedCamera => _controller?.description;

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Initializes the camera controller.
  ///
  /// Notes:
  /// - Supported targets: iOS and Android.
  /// - This does not request permissions. Callers should handle permissions
  ///   (story #4) before invoking this.
  Future<void> initialize(LiveCameraConfig config) async {
    _ensureSupportedPlatform();

    final cameras = await loadCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }

    final selected = _selectDefaultCamera(cameras);
    await _initializeControllerFor(selected, config);
  }

  /// Loads and caches available cameras.
  ///
  /// Safe to call multiple times.
  Future<List<CameraDescription>> loadCameras() async {
    _ensureSupportedPlatform();

    final cameras = _cameras ?? await availableCameras();
    _cameras = cameras;
    return cameras;
  }

  /// Switches between front and back camera when available.
  Future<void> switchCamera(LiveCameraConfig config) async {
    _ensureSupportedPlatform();

    final cameras = await loadCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }

    final current = _controller?.description;
    final next = _selectNextCamera(cameras, current);
    await _initializeControllerFor(next, config);
  }

  /// Selects a specific camera.
  Future<void> selectCamera(
    CameraDescription description,
    LiveCameraConfig config,
  ) async {
    _ensureSupportedPlatform();

    final cameras = await loadCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }

    final isKnown = cameras.any((c) => c.name == description.name);
    if (!isKnown) {
      throw ArgumentError('Selected camera is not available on this device.');
    }

    await _initializeControllerFor(description, config);
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  CameraDescription _selectDefaultCamera(List<CameraDescription> cameras) {
    final back =
        cameras.where((c) => c.lensDirection == CameraLensDirection.back);
    if (back.isNotEmpty) return back.first;
    return cameras.first;
  }

  CameraDescription _selectNextCamera(
    List<CameraDescription> cameras,
    CameraDescription? current,
  ) {
    if (cameras.length == 1) return cameras.first;

    if (current == null) return _selectDefaultCamera(cameras);

    final other = cameras.firstWhere(
      (c) => c.lensDirection != current.lensDirection,
      orElse: () {
        final idx = cameras.indexWhere((c) => c.name == current.name);
        return cameras[(idx + 1) % cameras.length];
      },
    );

    return other;
  }

  Future<void> _initializeControllerFor(
    CameraDescription description,
    LiveCameraConfig config,
  ) async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      await old.dispose();
    }

    final ImageFormatGroup? effectiveFormatGroup =
        config.imageFormatGroup ?? _defaultImageFormatGroup();

    final controller = CameraController(
      description,
      config.resolutionPreset,
      enableAudio: config.enableAudio,
      imageFormatGroup: effectiveFormatGroup,
    );

    _controller = controller;
    await controller.initialize();
  }

  ImageFormatGroup? _defaultImageFormatGroup() {
    // ML Kit camera-frame conversion supports:
    // - Android: NV21
    // - iOS: BGRA8888
    //
    // Using these defaults makes it possible to run ML Kit directly on the live
    // camera stream without additional per-platform configuration.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return ImageFormatGroup.nv21;
      case TargetPlatform.iOS:
        return ImageFormatGroup.bgra8888;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return null;
    }
  }

  void _ensureSupportedPlatform() {
    if (kIsWeb) {
      throw UnsupportedError('Camera service is not supported on web.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        throw UnsupportedError(
          'Camera service is intended for iOS/Android only.',
        );
    }
  }
}
