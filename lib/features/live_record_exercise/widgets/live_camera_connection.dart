import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_config.dart';
import '../services/camera_service.dart';
import 'camera_switcher.dart';
import 'live_camera_preview.dart';

typedef LiveCameraFrameCallback = void Function(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
);

/// A reusable camera “connection” widget.
///
/// This widget owns the lifecycle of [LiveCameraService] based on [isActive].
///
/// - When [isActive] becomes `true`, it initializes the native camera.
/// - When [isActive] becomes `false`, it disposes the controller.
///
/// This widget does NOT request permissions. If permissions are denied, camera
/// initialization will error and the [errorBuilder] will be shown.
///
/// Usage example:
/// ```dart
/// LiveCameraConnection(
///   isActive: isRunning,
///   config: const LiveCameraConfig(),
/// )
/// ```
class LiveCameraConnection extends StatefulWidget {
  const LiveCameraConnection({
    required this.isActive,
    required this.config,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.placeholder,
    this.errorBuilder,
    this.cameraControlsBuilder,
    this.previewOverlayBuilder,
    this.onCameraImage,
    super.key,
  });

  final bool isActive;
  final LiveCameraConfig config;

  /// How the preview should be clipped.
  ///
  /// Use [BorderRadius.zero] for full-screen.
  final BorderRadius borderRadius;

  final Widget? placeholder;

  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Optional builder for camera controls (e.g., camera switcher).
  ///
  /// This is intentionally owned by the parent so it can be placed anywhere
  /// (and wrapped in [SafeArea] to avoid colliding with status bars/notches).
  final Widget Function(
    BuildContext context,
    List<CameraDescription> cameras,
    int selectedIndex,
    bool isBusy,
    VoidCallback onToggleNext,
    ValueChanged<int> onSelectIndex,
  )? cameraControlsBuilder;

  /// Optional overlay rendered above the camera preview.
  ///
  /// This overlay is rendered within the same transform/crop as the preview,
  /// which allows drawing aligned landmarks, guides, etc.
  final Widget? Function(BuildContext context, CameraController controller)?
      previewOverlayBuilder;

  /// Optional live image-stream callback.
  ///
  /// When provided, this widget will start the camera image stream and forward
  /// frames. This is used for real-time ML (pose detection, etc.).
  final LiveCameraFrameCallback? onCameraImage;

  @override
  State<LiveCameraConnection> createState() => _LiveCameraConnectionState();
}

class _LiveCameraConnectionState extends State<LiveCameraConnection> {
  final LiveCameraService _service = LiveCameraService();

  Object? _error;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _isSwitching = false;
  int _imageStreamSession = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant LiveCameraConnection oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _start();
      } else {
        _stop();
      }
    }

    // If a frame listener was added/removed, restart the stream accordingly.
    if (oldWidget.onCameraImage != widget.onCameraImage) {
      if (widget.onCameraImage == null) {
        _stopImageStream();
      } else {
        _startImageStreamIfNeeded();
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _controller = null;
      _cameras = const [];
      _isSwitching = false;
    });

    try {
      await _service.initialize(widget.config);
      if (!mounted) return;
      setState(() {
        _controller = _service.controller;
        _cameras = _service.cameras;
      });

      _startImageStreamIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
      });
    }
  }

  Future<void> _switchToNextCamera() async {
    if (_isSwitching) return;

    setState(() {
      _isSwitching = true;
      _error = null;
      // Important: clear the current controller immediately.
      // LiveCameraService will dispose the old controller during the switch,
      // and we must not render CameraPreview with a disposed controller.
      _controller = null;
    });

    await _stopImageStream();

    try {
      await _service.switchCamera(widget.config);
      if (!mounted) return;
      setState(() {
        _controller = _service.controller;
        _cameras = _service.cameras;
        _isSwitching = false;
      });

      _startImageStreamIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isSwitching = false;
      });
    }
  }

  Future<void> _selectCameraByIndex(int index) async {
    if (_isSwitching) return;

    final cameras = _cameras;
    if (index < 0 || index >= cameras.length) return;

    setState(() {
      _isSwitching = true;
      _error = null;
      // Avoid a frame rendering with a controller that is about to be disposed.
      _controller = null;
    });

    await _stopImageStream();

    try {
      await _service.selectCamera(cameras[index], widget.config);
      if (!mounted) return;
      setState(() {
        _controller = _service.controller;
        _cameras = _service.cameras;
        _isSwitching = false;
      });

      _startImageStreamIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isSwitching = false;
      });
    }
  }

  Future<void> _stop() async {
    await _stopImageStream();
    await _service.dispose();
    if (!mounted) return;
    setState(() {
      _controller = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _stopImageStream();
    _service.dispose();
    super.dispose();
  }

  void _startImageStreamIfNeeded() {
    final callback = widget.onCameraImage;
    final controller = _controller;
    if (callback == null || controller == null) return;
    if (!controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    // Run after the current frame to avoid starting a stream mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final currentController = _controller;
      final currentCallback = widget.onCameraImage;
      if (currentController == null || currentCallback == null) return;
      if (currentController.value.isStreamingImages) return;

      final session = ++_imageStreamSession;
      try {
        await currentController.startImageStream((image) {
          if (!mounted) return;
          if (session != _imageStreamSession) return;
          if (currentController != _controller) return;

          currentCallback(
            image,
            currentController.description,
            currentController.value.deviceOrientation,
          );
        });
      } catch (_) {
        // If the stream can't be started (e.g., quickly switching cameras),
        // just ignore; the next controller assignment will retry.
      }
    });
  }

  Future<void> _stopImageStream() async {
    _imageStreamSession++;
    final controller = _controller;
    if (controller == null) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Ignore failures during disposal/switch.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Center(
        child: widget.placeholder ?? const Text('Ready. Tap Start to begin.'),
      );
    }

    final error = _error;
    if (error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, error);
      }

      return Center(
        child: Text(
          'Camera unavailable\n${error is CameraException ? error.description : error}',
          textAlign: TextAlign.center,
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Center(
        child: widget.placeholder ?? const CircularProgressIndicator(),
      );
    }

    final cameras = _cameras;
    final selected = controller.description;
    final selectedIndex = cameras.indexWhere((c) => c.name == selected.name);
    final showSwitcher = cameras.length > 1;

    final effectiveSelectedIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveCameraPreview(
            controller: controller,
            overlay: widget.previewOverlayBuilder?.call(context, controller),
          ),
          if (showSwitcher)
            Positioned.fill(
              child: (widget.cameraControlsBuilder ??
                  _defaultCameraControlsBuilder)(
                context,
                cameras,
                effectiveSelectedIndex,
                _isSwitching,
                _switchToNextCamera,
                _selectCameraByIndex,
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultCameraControlsBuilder(
    BuildContext context,
    List<CameraDescription> cameras,
    int selectedIndex,
    bool isBusy,
    VoidCallback onToggleNext,
    ValueChanged<int> onSelectIndex,
  ) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CameraSwitcher(
            cameras: cameras,
            selectedIndex: selectedIndex,
            isBusy: isBusy,
            onToggleNext: onToggleNext,
            onSelectIndex: onSelectIndex,
          ),
        ),
      ),
    );
  }
}
