import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// import 'package:permission_handler/permission_handler.dart'; // used by onboarding redirect when re-enabled

import '../common/models/exercise_type.dart';
import '../features/live_record_exercise/screens/workout_live_camera_screen.dart';
import '../features/live_record_exercise/screens/workout_screen.dart';
import '../features/live_record_exercise/services/camera_config.dart';
// Onboarding camera screen — disabled while flow is under development / fixing.
// import '../features/onboarding/screens/camera_permission_screen.dart';
// import '../features/onboarding/services/permission_service.dart';
import '../features/workout_log/screens/workout_log_screen.dart';
import 'shell/app_shell.dart';

class AppRoutes {
  static const live = '/live';
  static const log = '/log';
  static const liveCamera = '/live/camera';
  static const cameraPermission = '/onboarding/permissions';
}

/// Drives the camera-permission gate.
///
/// Calling [resolve] marks the gate as passed (permission granted or skipped)
/// and notifies GoRouter to re-run the redirect, which then moves the user
/// from the onboarding screen to [AppRoutes.live] automatically.
class _PermissionGate extends ChangeNotifier {
  bool _resolved = false;

  bool get resolved => _resolved;

  void resolve() {
    if (_resolved) return;
    _resolved = true;
    notifyListeners();
  }
}

final _permissionGate = _PermissionGate();

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.live,
  // GoRouter re-runs the redirect whenever _permissionGate notifies.
  refreshListenable: _permissionGate,
  redirect: (context, state) async {
    // Camera permission onboarding is commented out (see routes below): the
    // screen and redirect are under development / fixing. Bypass the gate so
    // users land on the main app without `/onboarding/permissions`.
    _permissionGate.resolve();
    return null;

    // --- Previous implementation (restore when re-enabling onboarding) ---
    // final onOnboarding = state.matchedLocation.startsWith('/onboarding');
    // if (_permissionGate.resolved) {
    //   return onOnboarding ? AppRoutes.live : null;
    // }
    // if (onOnboarding) return null;
    // final status = await const PermissionHandlerService().cameraStatus();
    // if (status.isGranted) {
    //   _permissionGate.resolve();
    //   return null;
    // }
    // return AppRoutes.cameraPermission;
  },
  routes: [
    // Onboarding — sits above the AppShell, no bottom nav.
    // Disabled while `CameraPermissionScreen` flow is under development / fixing.
    // GoRoute(
    //   path: AppRoutes.cameraPermission,
    //   builder: (context, state) => CameraPermissionScreen(
    //     onPermissionGranted: _permissionGate.resolve,
    //     onSkipped: _permissionGate.resolve,
    //   ),
    // ),

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
