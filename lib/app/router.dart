import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../common/models/exercise_type.dart';
import '../features/live_record_exercise/screens/workout_live_camera_screen.dart';
import '../features/live_record_exercise/screens/workout_screen.dart';
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
