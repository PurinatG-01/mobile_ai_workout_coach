# Camera Permission Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a camera permission onboarding screen that gates the app on launch, with a soft-block denied state and a "Continue without camera" escape hatch.

**Architecture:** GoRouter redirect checks camera permission on every navigation and redirects to `/onboarding/permissions` when not granted. `CameraPermissionScreen` owns both UI states (not-determined and denied) and re-checks permission when the app resumes from Settings. `PermissionService` is an abstract interface so the screen can be tested with a fake.

**Tech Stack:** Flutter, `permission_handler ^12.0.1`, GoRouter 16, `flutter_test` widget tests.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Create | `lib/features/onboarding/services/permission_service.dart` | Abstract interface + concrete `PermissionHandlerService` impl |
| Create | `lib/features/onboarding/screens/camera_permission_screen.dart` | Onboarding screen — both UI states, resume re-check |
| Create | `test/features/onboarding/camera_permission_screen_test.dart` | Widget tests for both screen states |
| Modify | `pubspec.yaml` | Add `permission_handler ^12.0.1` |
| Modify | `lib/app/router.dart` | Add `/onboarding/permissions` route + async redirect |

> **Note:** `ios/Runner/Info.plist` already has `NSCameraUsageDescription` — no change needed.

---

### Task 1: Add `permission_handler` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add under `dependencies:` after the `camera:` line:

```yaml
  permission_handler: ^12.0.1
```

- [ ] **Step 2: Fetch packages**

```bash
fvm flutter pub get
```

Expected output ends with: `Got dependencies.`

- [ ] **Step 3: Verify it resolves**

```bash
fvm flutter pub deps | grep permission_handler
```

Expected: a line containing `permission_handler 12.x.x`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add permission_handler dependency"
```

---

### Task 2: Create `PermissionService` abstract interface + concrete implementation

**Files:**
- Create: `lib/features/onboarding/services/permission_service.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/features/onboarding/services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';

/// Abstract interface for camera permission operations.
///
/// Decoupled from [permission_handler] so the screen can be tested with a fake.
abstract class PermissionService {
  Future<PermissionStatus> cameraStatus();
  Future<PermissionStatus> requestCamera();
  Future<bool> openSettings();
}

/// Production implementation backed by [permission_handler].
class PermissionHandlerService implements PermissionService {
  const PermissionHandlerService();

  @override
  Future<PermissionStatus> cameraStatus() => Permission.camera.status;

  @override
  Future<PermissionStatus> requestCamera() => Permission.camera.request();

  @override
  Future<bool> openSettings() => openAppSettings();
}
```

- [ ] **Step 2: Analyze to verify no errors**

```bash
fvm flutter analyze lib/features/onboarding/services/permission_service.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/onboarding/services/permission_service.dart
git commit -m "feat: add PermissionService interface and PermissionHandlerService impl"
```

---

### Task 3: Write failing widget tests for `CameraPermissionScreen`

**Files:**
- Create: `test/features/onboarding/camera_permission_screen_test.dart`

- [ ] **Step 1: Create the test file**

```dart
// test/features/onboarding/camera_permission_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobile_ai_workout_coach/features/onboarding/screens/camera_permission_screen.dart';
import 'package:mobile_ai_workout_coach/features/onboarding/services/permission_service.dart';

class _FakePermissionService implements PermissionService {
  _FakePermissionService({required this.initialStatus});
  PermissionStatus initialStatus;

  @override
  Future<PermissionStatus> cameraStatus() async => initialStatus;

  @override
  Future<PermissionStatus> requestCamera() async => initialStatus;

  @override
  Future<bool> openSettings() async => true;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('CameraPermissionScreen', () {
    testWidgets('State A: shows Allow button and Skip when notDetermined',
        (tester) async {
      final service =
          _FakePermissionService(status: PermissionStatus.denied);

      // notDetermined is not available on all platforms in tests;
      // use denied to simulate the "request" flow via the same screen.
      // For State A we pass a service whose requestCamera returns granted.
      final serviceA = _FakePermissionService(
          initialStatus: PermissionStatus.denied)
        ..initialStatus = PermissionStatus.denied;

      // Use a service that starts as notDetermined-equivalent (denied but not permanentlyDenied).
      await tester.pumpWidget(_wrap(CameraPermissionScreen(service: service)));
      await tester.pump(); // let initState async complete

      expect(find.text('Before you begin'), findsOneWidget);
      expect(find.text('Allow Camera Access'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('State B: shows Open Settings and Continue when permanentlyDenied',
        (tester) async {
      final service = _FakePermissionService(
          initialStatus: PermissionStatus.permanentlyDenied);

      await tester.pumpWidget(_wrap(CameraPermissionScreen(service: service)));
      await tester.pump(); // let initState async complete

      expect(find.text('Before you begin'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Continue without camera'), findsOneWidget);
      expect(find.text('Allow Camera Access'), findsNothing);
    });

    testWidgets('shows loading indicator before status resolves', (tester) async {
      // Completer-backed service that never resolves during this test
      final service = _NeverResolvingPermissionService();

      await tester.pumpWidget(_wrap(CameraPermissionScreen(service: service)));
      // Do NOT pump again — status hasn't resolved yet

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

class _NeverResolvingPermissionService implements PermissionService {
  @override
  Future<PermissionStatus> cameraStatus() => Future<PermissionStatus>.delayed(
        const Duration(days: 999),
      );

  @override
  Future<PermissionStatus> requestCamera() async =>
      PermissionStatus.denied;

  @override
  Future<bool> openSettings() async => false;
}
```

- [ ] **Step 2: Run tests — expect FAIL (screen doesn't exist yet)**

```bash
fvm flutter test test/features/onboarding/camera_permission_screen_test.dart
```

Expected: compile error — `CameraPermissionScreen` not found.

---

### Task 4: Implement `CameraPermissionScreen`

**Files:**
- Create: `lib/features/onboarding/screens/camera_permission_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
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
    if (widget.onPermissionGranted != null) {
      widget.onPermissionGranted!();
    }
  }

  void _handleSkip() {
    if (widget.onSkipped != null) {
      widget.onSkipped!();
    }
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
                        'Camera access is denied. Live workout tracking won\'t be available without it.',
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
```

- [ ] **Step 2: Run the tests — expect PASS**

```bash
fvm flutter test test/features/onboarding/camera_permission_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 3: Analyze**

```bash
fvm flutter analyze lib/features/onboarding/
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/onboarding/ test/features/onboarding/
git commit -m "feat: add CameraPermissionScreen with notDetermined and denied states"
```

---

### Task 5: Wire route and redirect in `router.dart`

**Files:**
- Modify: `lib/app/router.dart`

- [ ] **Step 1: Update `router.dart`**

Replace the full contents of `lib/app/router.dart` with:

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../common/models/exercise_type.dart';
import '../features/live_record_exercise/screens/workout_screen.dart';
import '../features/live_record_exercise/screens/workout_live_camera_screen.dart';
import '../features/live_record_exercise/services/camera_config.dart';
import '../features/onboarding/screens/camera_permission_screen.dart';
import '../features/onboarding/services/permission_service.dart';
import '../features/workout_log/screens/workout_log_screen.dart';
import 'shell/app_shell.dart';

class AppRoutes {
  static const live = '/live';
  static const log = '/log';
  static const liveCamera = '/live/camera';
  static const cameraPermission = '/onboarding/permissions';
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.live,
  redirect: (context, state) async {
    final onOnboarding =
        state.matchedLocation.startsWith('/onboarding');
    if (onOnboarding) return null;

    final status = await const PermissionHandlerService().cameraStatus();
    if (status.isGranted) return null;

    return AppRoutes.cameraPermission;
  },
  routes: [
    // Onboarding — sits above the AppShell, no bottom nav.
    GoRoute(
      path: AppRoutes.cameraPermission,
      builder: (context, state) => CameraPermissionScreen(
        onPermissionGranted: () => context.go(AppRoutes.live),
        onSkipped: () => context.go(AppRoutes.live),
      ),
    ),

    // Full-screen live camera — also above the AppShell.
    GoRoute(
      path: AppRoutes.liveCamera,
      builder: (context, state) {
        final exercise = (state.extra is ExerciseType)
            ? state.extra! as ExerciseType
            : ExerciseType.squat;
        return WorkoutLiveCameraScreen(
          config: const LiveCameraConfig(),
          exerciseType: exercise,
        );
      },
    ),

    ShellRoute(
      builder: (context, state, child) => AppShell(
        location: state.uri.toString(),
        child: child,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.live,
          builder: (context, state) => const WorkoutScreen(),
        ),
        GoRoute(
          path: AppRoutes.log,
          builder: (context, state) => const WorkoutLogScreen(),
        ),
      ],
    ),
  ],
);
```

- [ ] **Step 2: Analyze**

```bash
fvm flutter analyze lib/app/router.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Full project analyze**

```bash
fvm flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Run all tests**

```bash
fvm flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/router.dart
git commit -m "feat: add /onboarding/permissions route and camera permission redirect"
```

---

### Task 6: Smoke test on simulator

- [ ] **Step 1: Boot a simulator and run**

```bash
fvm flutter run
```

- [ ] **Step 2: Verify the flow**

On first launch (or after resetting permissions via `Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy`):

1. App opens → should land on `/onboarding/permissions` (State A)
2. Tap **Allow Camera Access** → iOS system dialog appears
3. Tap **Don't Allow** → screen transitions to State B (red gradient, "Open Settings")
4. Tap **Continue without camera** → lands on `/live` (Workout screen)
5. Kill and relaunch → State B shown again (permission still denied)
6. Tap **Open Settings** → iOS Settings opens to app permissions
7. Enable camera → return to app → screen auto-navigates to `/live`

- [ ] **Step 3: Final commit**

```bash
git add .
git commit -m "feat: camera permission onboarding — backlog #4 complete"
```
