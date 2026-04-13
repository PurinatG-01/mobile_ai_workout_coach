import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Workout Coach',
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
