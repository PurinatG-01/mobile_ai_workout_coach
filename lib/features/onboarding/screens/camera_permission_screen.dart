import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/app_colors.dart';
import '../services/permission_service.dart';

class CameraPermissionScreen extends StatefulWidget {
  const CameraPermissionScreen({
    this.service = const PermissionHandlerService(),
    this.onPermissionGranted,
    this.onSkipped,
    super.key,
  });

  final PermissionService service;

  /// Called after permission is granted. Defaults to replacing with '/live'.
  final VoidCallback? onPermissionGranted;

  /// Called when user taps skip/continue without camera.
  final VoidCallback? onSkipped;

  @override
  State<CameraPermissionScreen> createState() => _CameraPermissionScreenState();
}

class _CameraPermissionScreenState extends State<CameraPermissionScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await widget.service.cameraStatus();
    if (!mounted) return;
    setState(() => _status = status);

    if (status.isGranted) _handleGranted();
  }

  Future<void> _requestPermission() async {
    final status = await widget.service.requestCamera();
    if (!mounted) return;
    setState(() => _status = status);

    if (status.isGranted) _handleGranted();
  }

  void _handleGranted() {
    widget.onPermissionGranted?.call();
  }

  void _handleSkip() {
    widget.onSkipped?.call();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    if (status == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // On iOS, `denied` also prevents re-prompting — treat it like permanentlyDenied.
    final isDenied = status.isPermanentlyDenied || status.isDenied;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero banner
          Container(
            height: 220,
            color: isDenied ? AppColors.bgElevated : AppColors.bgSurface,
            child: const Center(
              child: Icon(
                Icons.camera_alt,
                size: 72,
                color: AppColors.textSecondary,
              ),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Before you begin',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (isDenied) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        border: Border.all(color: AppColors.borderStrong),
                      ),
                      child: Text(
                        "Camera access is denied. Live workout tracking won't be available without it.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Text(
                      'This app uses your camera to track workouts in real time.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _FeatureList(dimmed: isDenied),
                  const Spacer(),
                  if (isDenied) ...[
                    FilledButton(
                      onPressed: () => widget.service.openSettings(),
                      child: const Text('Open Settings'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _handleSkip,
                      child: const Text('Continue without camera'),
                    ),
                  ] else ...[
                    FilledButton(
                      onPressed: _requestPermission,
                      child: const Text('Allow Camera Access'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _handleSkip,
                      child: const Text('Skip for now'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.dimmed});

  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FeatureRow(label: 'Real-time rep counting', dimmed: dimmed),
        const SizedBox(height: 8),
        _FeatureRow(label: 'Pose detection', dimmed: dimmed),
        const SizedBox(height: 8),
        _FeatureRow(label: 'Live form feedback', dimmed: dimmed),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.dimmed});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(
            dimmed ? Icons.close : Icons.check,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dimmed ? AppColors.textDisabled : AppColors.textPrimary,
                decoration: dimmed ? TextDecoration.lineThrough : null,
                decorationColor: AppColors.textDisabled,
              ),
        ),
      ],
    );
  }
}
