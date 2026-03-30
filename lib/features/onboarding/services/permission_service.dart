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
