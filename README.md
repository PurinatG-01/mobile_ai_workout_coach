# mobile_ai_workout_coach

On-device AI workout coach built with Flutter.

Current MVP focus:

- Live workout session screen (controls + placeholders)
- Workout log screen (WIP)
- App-wide navigation (2 tabs) using `go_router`

## Getting Started

### Run

- `flutter pub get`
- `flutter run`

### Test

- `flutter test`

## Navigation

The app has two epic-aligned screens, switched via bottom navigation:

- Workout (Live Record Exercise) at `/live`
- Log (Workout Log) at `/log`

In addition, the live camera experience is a full-screen route (no app bar / no bottom tab bar):

- Live Camera at `/live/camera`

Flutter docs: https://docs.flutter.dev/
