// test/features/onboarding/camera_permission_screen_test.dart
import 'dart:async';

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
          _FakePermissionService(initialStatus: PermissionStatus.denied);

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
      final service = _NeverResolvingPermissionService();

      await tester.pumpWidget(_wrap(CameraPermissionScreen(service: service)));
      // Do NOT pump again — status hasn't resolved yet

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

class _NeverResolvingPermissionService implements PermissionService {
  @override
  Future<PermissionStatus> cameraStatus() =>
      Completer<PermissionStatus>().future;

  @override
  Future<PermissionStatus> requestCamera() async =>
      PermissionStatus.denied;

  @override
  Future<bool> openSettings() async => false;
}
