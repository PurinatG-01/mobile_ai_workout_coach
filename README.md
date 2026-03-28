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

Notes:

- Live Camera defaults to the front camera when available (switchable in-app).

### Test

- `flutter test`

## Exercise Engine (Domain)

The real-time “exercise logic” is implemented as domain-layer calculators that consume ML Kit pose frames.

- Contract: `ExerciseCalculator` (`reset()` + `update(...)` per pose frame)
- Output: `ExerciseFrameResult` (reps, set stage, rep phase, metrics)
- Set lifecycle state machine: `SetLifecycleController` (rest → countdown → active → rest)
- Factory: `ExerciseCalculatorFactory` (select calculator per `ExerciseType`)

UI integration notes:

- `ExerciseFrameResult` also includes one-frame lifecycle event flags: `didStartSet`, `didEndSet`, and `didEndSetByBreakPose`.
  - The live camera UI uses `didEndSetByBreakPose` to display a small “break detected → set ended” message.

Bicep curl end-of-set (break pose):

- The bicep curl calculator ends sets when it detects a user “bend down” posture relative to the set’s starting pose.
- Detection uses a waist/hip angle delta (shoulder-hip-knee) from baseline so it works for both standing and sitting curls.

Design notes:

- `SetLifecycleController` is intentionally **not** exposed on the `ExerciseCalculator` interface.
  - Implementations own lifecycle internally.
  - For testing/modularity, calculators accept an optional injected lifecycle controller via their constructor.
  - Callers interact only with input signals to `update(...)` and the returned `ExerciseFrameResult`.

## Navigation

The app has two epic-aligned screens, switched via bottom navigation:

- Workout (Live Record Exercise) at `/live`
- Log (Workout Log) at `/log`

In addition, the live camera experience is a full-screen route (no app bar / no bottom tab bar):

- Live Camera at `/live/camera`

Flutter docs: https://docs.flutter.dev/
