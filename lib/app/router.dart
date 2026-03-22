import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../features/live_record_exercise/screens/workout_screen.dart';
import '../features/live_record_exercise/screens/workout_live_camera_screen.dart';
import '../features/live_record_exercise/services/camera_config.dart';
import '../features/workout_log/screens/workout_log_screen.dart';
import 'shell/app_shell.dart';

class AppRoutes {
  static const live = '/live';
  static const log = '/log';
  static const liveCamera = '/live/camera';
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.live,
  routes: [
    // Full-screen route that sits above the AppShell scaffold.
    GoRoute(
      path: AppRoutes.liveCamera,
      builder: (context, state) => const WorkoutLiveCameraScreen(
        config: LiveCameraConfig(),
      ),
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
