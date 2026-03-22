import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/camera_config.dart';
import '../services/camera_service.dart';
import 'camera_switcher.dart';
import 'live_camera_preview.dart';

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

  @override
  State<LiveCameraConnection> createState() => _LiveCameraConnectionState();
}

class _LiveCameraConnectionState extends State<LiveCameraConnection> {
  final LiveCameraService _service = LiveCameraService();

  Object? _error;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _isSwitching = false;

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

    try {
      await _service.switchCamera(widget.config);
      if (!mounted) return;
      setState(() {
        _controller = _service.controller;
        _cameras = _service.cameras;
        _isSwitching = false;
      });
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

    try {
      await _service.selectCamera(cameras[index], widget.config);
      if (!mounted) return;
      setState(() {
        _controller = _service.controller;
        _cameras = _service.cameras;
        _isSwitching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isSwitching = false;
      });
    }
  }

  Future<void> _stop() async {
    await _service.dispose();
    if (!mounted) return;
    setState(() {
      _controller = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
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
