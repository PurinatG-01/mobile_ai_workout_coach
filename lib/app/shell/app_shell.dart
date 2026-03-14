import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  int get _currentIndex {
    if (location.startsWith(AppRoutes.log)) return 1;
    return 0;
  }

  String get _title {
    switch (_currentIndex) {
      case 1:
        return 'Workout Log';
      case 0:
      default:
        return 'Workout';
    }
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 1:
        context.go(AppRoutes.log);
        return;
      case 0:
      default:
        context.go(AppRoutes.live);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
      ),
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => _onTap(context, index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center),
            label: 'Workout',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Log',
          ),
        ],
      ),
    );
  }
}
