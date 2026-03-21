import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/camera_config.dart';
import '../services/camera_service.dart';
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
    this.placeholder,
    this.errorBuilder,
    super.key,
  });

  final bool isActive;
  final LiveCameraConfig config;

  final Widget? placeholder;

  final Widget Function(BuildContext context, Object error)? errorBuilder;

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveCameraPreview(
            controller: controller,
          ),
          if (showSwitcher)
            Positioned(
              top: 8,
              right: 8,
              child: _CameraSwitcher(
                cameras: cameras,
                selectedIndex: selectedIndex >= 0 ? selectedIndex : 0,
                isBusy: _isSwitching,
                onToggleNext: _switchToNextCamera,
                onSelectIndex: _selectCameraByIndex,
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraSwitcher extends StatelessWidget {
  const _CameraSwitcher({
    required this.cameras,
    required this.selectedIndex,
    required this.isBusy,
    required this.onToggleNext,
    required this.onSelectIndex,
  });

  final List<CameraDescription> cameras;
  final int selectedIndex;
  final bool isBusy;

  final VoidCallback onToggleNext;
  final ValueChanged<int> onSelectIndex;

  String _labelFor(CameraDescription camera, int index) {
    final direction = switch (camera.lensDirection) {
      CameraLensDirection.front => 'Front',
      CameraLensDirection.back => 'Back',
      CameraLensDirection.external => 'External',
    };
    return '$direction ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget child;
    if (cameras.length <= 2) {
      child = IconButton(
        tooltip: 'Switch camera',
        onPressed: isBusy ? null : onToggleNext,
        icon: const Icon(Icons.cameraswitch),
      );
    } else {
      final currentLabel = _labelFor(cameras[selectedIndex], selectedIndex);
      child = PopupMenuButton<int>(
        tooltip: 'Select camera',
        enabled: !isBusy,
        onSelected: onSelectIndex,
        itemBuilder: (context) => [
          for (var i = 0; i < cameras.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i == selectedIndex)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18, height: 18),
                  const SizedBox(width: 8),
                  Text(_labelFor(cameras[i], i)),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cameraswitch),
              const SizedBox(width: 8),
              Text(currentLabel),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );
    }

    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: child,
    );
  }
}
