import 'package:flutter/material.dart';

import '../services/camera_config.dart';
import '../widgets/camera_switcher.dart';
import '../widgets/live_camera_connection.dart';
import '../widgets/workout_stats.dart';

class WorkoutLiveCameraScreen extends StatelessWidget {
  const WorkoutLiveCameraScreen({
    required this.config,
    super.key,
  });

  final LiveCameraConfig config;

  @override
  Widget build(BuildContext context) {
    // Reserve space for the camera selector UI in the preview (top-right).
    // This prevents the stats row from overlapping it.
    const cameraSelectorReservedWidth = 180.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera should be truly full screen (edge-to-edge).
          LiveCameraConnection(
            isActive: true,
            config: config,
            borderRadius: BorderRadius.zero,
            cameraControlsBuilder: (
              context,
              cameras,
              selectedIndex,
              isBusy,
              onToggleNext,
              onSelectIndex,
            ) {
              // Keep camera controls within safe bounds (status bar/notch).
              // Note: this renders above the preview but below the overlay
              // SafeArea stack in this screen.
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
            },
            placeholder: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
          // Overlay controls live within SafeArea only.
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    width: MediaQuery.of(context).size.width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const WorkoutStats(),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop recording'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
