// lib/features/onboarding/screens/camera_permission_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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
  State<CameraPermissionScreen> createState() =>
      _CameraPermissionScreenState();
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

    final isDenied = status.isPermanentlyDenied;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero banner
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDenied
                    ? [
                        const Color(0xFFFF6347).withValues(alpha: 0.3),
                        Colors.black,
                      ]
                    : [
                        const Color(0xFF6C63FF).withValues(alpha: 0.3),
                        Colors.black,
                      ],
              ),
            ),
            child: const Center(
              child: Icon(Icons.camera_alt, size: 72, color: Colors.white70),
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
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),

                  if (isDenied) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6347).withValues(alpha: 0.1),
                        border: Border.all(
                          color: const Color(0xFFFF6347).withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Camera access is denied. Live workout tracking won't be available without it.",
                        style: TextStyle(color: Color(0xFFFF9580)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    const Text(
                      'This app uses your camera to track workouts in real time.',
                      style: TextStyle(color: Colors.white70),
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
            color: dimmed
                ? const Color(0xFFFF6347).withValues(alpha: 0.15)
                : const Color(0xFF6C63FF).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            dimmed ? Icons.close : Icons.check,
            size: 14,
            color: dimmed ? const Color(0xFFFF6347) : const Color(0xFF6C63FF),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: dimmed ? Colors.white38 : Colors.white70,
            decoration: dimmed ? TextDecoration.lineThrough : null,
            decorationColor: Colors.white38,
          ),
        ),
      ],
    );
  }
}
