# Camera Permission Onboarding — Design Spec

**Date:** 2026-03-30
**Backlog item:** #4 — CAM: Camera permission handling

---

## Goal

Show a camera permission onboarding screen before the user reaches any app content. If permission is denied, show a soft-block state with an info message and options to open Settings or continue without camera. Treat onboarding as a proper feature with its own route, extensible for future onboarding steps.

---

## Approach

Hybrid of Route-based (Approach 2) + GoRouter redirect gate (Approach 1 spirit):

- Onboarding lives in `lib/features/onboarding/` as a first-class feature
- GoRouter `redirect` callback reads permission state and routes to `/onboarding/permissions` when needed
- After grant or skip, redirect clears and user lands on `/live`
- Adding future onboarding steps (terms, profile) is additive — new routes + updated redirect, no structural change

---

## App Launch Flow

```
App Launch
    └── GoRouter redirect checks PermissionService.cameraStatus
            ├── granted       → /live  (normal app)
            ├── notDetermined → /onboarding/permissions  (request screen)
            └── denied        → /onboarding/permissions  (denied state)
```

After the user acts on `/onboarding/permissions`:
- **Allow** → system dialog appears → on grant → `context.go('/live')`
- **Skip / Continue without camera** → `context.go('/live')`
- **Open Settings** → `openAppSettings()` → user returns → screen re-checks status

---

## Screens

### `/onboarding/permissions` — `CameraPermissionScreen`

**State A — Not yet determined**
- Hero banner with camera icon (purple gradient)
- Title: "Before you begin"
- Body: "This app uses your camera to track workouts in real time."
- Feature list (checkmarks): Real-time rep counting, Pose detection, Live form feedback
- Primary CTA: `FilledButton` — "Allow Camera Access"
- Secondary action: `TextButton` — "Skip for now"

**State B — Permission denied**
- Hero banner with camera icon (red/warning gradient)
- Title: "Before you begin" (same, consistent)
- Warning info box: "Camera access is denied. Live workout tracking won't be available without it."
- Feature list (strikethrough, dimmed): same three features
- Primary CTA: `FilledButton` — "Open Settings" → calls `openAppSettings()`
- Secondary action: `TextButton` — "Continue without camera"

The screen derives its state from `PermissionService` on `initState` and after returning from Settings (via `AppLifecycleListener` or `WidgetsBindingObserver`).

---

## New Files

### `lib/features/onboarding/services/permission_service.dart`

Thin wrapper around `permission_handler`. Exposes:
```dart
Future<PermissionStatus> cameraStatus();
Future<PermissionStatus> requestCamera();
Future<bool> openSettings();
```

No state. Stateless service, injected or directly instantiated.

### `lib/features/onboarding/screens/camera_permission_screen.dart`

`StatefulWidget`. Uses `WidgetsBindingObserver` to re-check permission when app resumes (user returning from Settings).

Internal state:
- `PermissionStatus _status` — drives which UI state to show
- `bool _isLoading` — while `requestCamera()` is in flight

---

## Modified Files

### `pubspec.yaml`
Add dependency:
```yaml
permission_handler: ^12.0.1
```

### `ios/Runner/Info.plist`
Add camera usage description:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to detect your movements and count reps during workouts.</string>
```

### `lib/app/router.dart`
- Add `/onboarding/permissions` route pointing to `CameraPermissionScreen`
- Add `redirect` callback:
  ```dart
  redirect: (context, state) async {
    final status = await PermissionService().cameraStatus();
    final onOnboarding = state.matchedLocation.startsWith('/onboarding');
    if (status != PermissionStatus.granted && !onOnboarding) {
      return '/onboarding/permissions';
    }
    return null;
  }
  ```

---

## Behaviour Details

| Scenario | Behaviour |
|---|---|
| First launch, permission not asked | Show State A screen |
| User taps "Allow Camera Access" | Trigger system dialog; on grant → `/live`; on deny → stay, show State B |
| User taps "Skip for now" | Navigate to `/live`; permission remains notDetermined |
| User taps "Open Settings" | Open app Settings; on resume re-check status |
| User returns from Settings having granted | Auto-navigate to `/live` |
| User returns from Settings still denied | Stay on State B |
| Permission already granted on launch | Redirect skips onboarding entirely |

---

## Out of Scope

- Android-specific rationale dialog (permission_handler handles this natively)
- Persisting "skipped" state across launches (re-shows onboarding each launch if not granted — acceptable for prototype)
- Microphone or other permissions

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `permission_handler` | ^12.0.1 | Camera permission request + status check + openAppSettings |
