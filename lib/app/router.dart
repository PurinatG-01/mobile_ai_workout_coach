import 'package:go_router/go_router.dart';

import '../features/live_record_exercise/screens/workout_screen.dart';
import '../features/workout_log/screens/workout_log_screen.dart';
import 'shell/app_shell.dart';

class AppRoutes {
  static const live = '/live';
  static const log = '/log';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.live,
  routes: [
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
