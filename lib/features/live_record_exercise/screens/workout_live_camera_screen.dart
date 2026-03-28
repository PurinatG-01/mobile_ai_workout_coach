import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../common/models/exercise_type.dart';
import '../../../domain/exercises/exercise_calculator.dart';
import '../../../domain/exercises/exercise_calculator_factory.dart';
import '../../../domain/exercises/models/exercise_frame_result.dart';
import '../../../domain/exercises/models/exercise_rep_phase.dart';
import '../../../domain/exercises/models/exercise_set_stage.dart';
import '../services/camera_config.dart';
import '../services/pose_detection_service.dart';
import '../widgets/camera_switcher.dart';
import '../widgets/live_camera_connection.dart';
import '../widgets/pose_landmarks_overlay.dart';
import '../widgets/workout_stats.dart';

class WorkoutLiveCameraScreen extends StatefulWidget {
  const WorkoutLiveCameraScreen({
    required this.config,
    required this.exerciseType,
    super.key,
  });

  final LiveCameraConfig config;
  final ExerciseType exerciseType;

  @override
  State<WorkoutLiveCameraScreen> createState() =>
      _WorkoutLiveCameraScreenState();
}

class _WorkoutLiveCameraScreenState extends State<WorkoutLiveCameraScreen> {
  late final PoseDetectionService _poseService;
  late final ExerciseCalculator _calculator;

  bool _startCountdownPending = false;

  int _poseCount = 0;
  int _landmarkCount = 0;
  DateTime? _lastPoseAt;
  Pose? _latestPose;
  ExerciseFrameResult? _latestResult;

  @override
  void initState() {
    super.initState();
    _poseService = PoseDetectionService(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );

    _calculator = const ExerciseCalculatorFactory().create(widget.exerciseType);
  }

  @override
  void dispose() {
    _poseService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latestResult = _latestResult;
    final countdownMs = latestResult?.countdownRemainingMs;
    final countdownSeconds = countdownMs == null
        ? null
        : (countdownMs / 1000.0).ceil().clamp(0, 999);

    final repsText = latestResult?.reps.toString() ?? '0';
    final exerciseStageText =
        latestResult == null ? '—' : _formatRepPhase(latestResult.repPhase);
    final setStageText =
        latestResult == null ? '—' : _formatSetStage(latestResult.setStage);

    final setStage = latestResult?.setStage;
    final canStartCountdown = !_startCountdownPending &&
        (setStage == null || setStage == ExerciseSetStage.rest);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera should be truly full screen (edge-to-edge).
          LiveCameraConnection(
            isActive: true,
            config: widget.config,
            borderRadius: BorderRadius.zero,
            previewOverlayBuilder: (context, controller) {
              final pose = _latestPose;
              final previewSize = controller.value.previewSize;
              if (pose == null || previewSize == null) {
                return null;
              }

              // Landmarks are reported in the camera image coordinate space.
              // Align the overlay with the oriented preview size used in UI.
              final uiOrientation = MediaQuery.of(context).orientation;
              final orientedSourceSize = uiOrientation == Orientation.portrait
                  ? Size(previewSize.height, previewSize.width)
                  : Size(previewSize.width, previewSize.height);

              final isFrontCamera = controller.description.lensDirection ==
                  CameraLensDirection.front;

              // Avoid double-mirroring: on iOS the preview is typically already
              // mirrored for the front camera, while on Android it often isn't.
              final mirror = isFrontCamera &&
                  (defaultTargetPlatform == TargetPlatform.android);

              return PoseLandmarksOverlay(
                pose: pose,
                sourceSize: orientedSourceSize,
                mirrorHorizontally: mirror,
              );
            },
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
            onCameraImage: onCameraImage,
            placeholder: const Center(
              child: CircularProgressIndicator(),
            ),
          ),

          if (latestResult?.setStage == ExerciseSetStage.countdown &&
              countdownSeconds != null &&
              countdownSeconds > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _CountdownOverlay(seconds: countdownSeconds),
                ),
              ),
            ),

          // Overlay controls live within SafeArea only.
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  child: _MlKitDebugBadge(
                    poseCount: _poseCount,
                    landmarkCount: _landmarkCount,
                    lastPoseAt: _lastPoseAt,
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    width: MediaQuery.of(context).size.width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WorkoutStats(
                          reps: repsText,
                          exerciseStage: exerciseStageText,
                          setStage: setStageText,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: canStartCountdown
                              ? () {
                                  setState(() {
                                    _startCountdownPending = true;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start countdown'),
                        ),
                        const SizedBox(height: 12),
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

  void onCameraImage(image, camera, deviceOrientation) async {
    final poses = await _poseService.processCameraImage(
      image: image,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    if (!mounted || poses == null) return;

    final poseCount = poses.length;
    final landmarkCount = poses.isNotEmpty ? poses.first.landmarks.length : 0;

    final pose = poses.isNotEmpty ? poses.first : null;
    final startCountdown = _startCountdownPending;
    final result = pose == null
        ? null
        : _calculator.update(
            pose: pose,
            timestamp: DateTime.now(),
            startCountdown: startCountdown,
            autoSetLifecycle: false,
            autoEndSetLifecycle: true,
          );

    final didEndByBreakPose = result?.didEndSetByBreakPose ?? false;

    // Update only when we actually processed a frame.
    setState(() {
      _poseCount = poseCount;
      _landmarkCount = landmarkCount;
      _lastPoseAt = DateTime.now();
      _latestPose = pose;
      _latestResult = result;

      // Consume the pending signal on the next processed pose frame.
      if (startCountdown) {
        _startCountdownPending = false;
      }
    });

    if (didEndByBreakPose && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Break pose detected — set ended'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatSetStage(ExerciseSetStage stage) {
    switch (stage) {
      case ExerciseSetStage.rest:
        return 'Rest';
      case ExerciseSetStage.countdown:
        return 'Countdown';
      case ExerciseSetStage.active:
        return 'Active';
    }
  }

  String _formatRepPhase(ExerciseRepPhase phase) {
    switch (phase) {
      case ExerciseRepPhase.unknown:
        return 'Unknown';
      case ExerciseRepPhase.top:
        return 'Top';
      case ExerciseRepPhase.bottom:
        return 'Bottom';
      case ExerciseRepPhase.concentric:
        return 'Concentric';
      case ExerciseRepPhase.eccentric:
        return 'Eccentric';
    }
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({
    required this.seconds,
  });

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$seconds',
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MlKitDebugBadge extends StatelessWidget {
  const _MlKitDebugBadge({
    required this.poseCount,
    required this.landmarkCount,
    required this.lastPoseAt,
  });

  final int poseCount;
  final int landmarkCount;
  final DateTime? lastPoseAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final lastText = lastPoseAt == null
        ? '—'
        : '${lastPoseAt!.hour.toString().padLeft(2, '0')}:${lastPoseAt!.minute.toString().padLeft(2, '0')}:${lastPoseAt!.second.toString().padLeft(2, '0')}';

    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.70),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          'Pose: $poseCount | Landmarks: $landmarkCount | Last: $lastText',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}
