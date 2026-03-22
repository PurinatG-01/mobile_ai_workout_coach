import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraSwitcher extends StatelessWidget {
  const CameraSwitcher({
    required this.cameras,
    required this.selectedIndex,
    required this.isBusy,
    required this.onToggleNext,
    required this.onSelectIndex,
    super.key,
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
      final safeSelectedIndex = selectedIndex.clamp(0, cameras.length - 1);
      final currentLabel =
          _labelFor(cameras[safeSelectedIndex], safeSelectedIndex);
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
                  if (i == safeSelectedIndex)
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
