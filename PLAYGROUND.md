# Mobile AI Workout Coach — Claude Code Playground

This file is the **entry point** for exploring this codebase interactively using `/playground` in Claude Code on your laptop.

Load this file as context, then use the suggested prompts below to explore, extend, or debug any part of the system.

---

## How to Use

1. Open Claude Code on your laptop inside this repo directory.
2. Run `/playground` (or paste a prompt from the **Exploration Prompts** section below).
3. Reference paths from the **Project Map** section to navigate directly to any layer.

---

## Project Summary

A real-time, on-device AI workout coach built with **Flutter + Dart**.

- Camera stream → ML Kit pose detection → angle calculation → phase state machine → rep counter → UI overlay
- No backend video streaming. All inference runs locally on the device.
- Primary supported exercises: squats, push-ups, bicep curls, pull-ups.

---

## Project Map

### Entry Points

| File | Purpose |
|------|---------|
| `lib/main.dart` | App bootstrap |
| `lib/app/app.dart` | `MaterialApp.router` root |
| `lib/app/router.dart` | GoRouter config + async permission redirect |
| `lib/app/shell/app_shell.dart` | Bottom nav scaffold (Workout / Log tabs) |

### Routes

| Path | Screen |
|------|--------|
| `/onboarding/permissions` | Camera permission gate |
| `/live` | Workout selection screen |
| `/live/camera` | Full-screen live camera + overlays |
| `/log` | Workout history log |

---

### Feature: Onboarding

> Gate the app behind camera permission before any content is shown.

| File | Purpose |
|------|---------|
| `lib/features/onboarding/screens/camera_permission_screen.dart` | UI for notDetermined + permanentlyDenied states |
| `lib/features/onboarding/services/permission_service.dart` | Abstract `PermissionService` + `PermissionHandlerService` impl |

---

### Feature: Live Record Exercise

> Real-time camera + pose detection + rep counting experience.

#### Screens

| File | Purpose |
|------|---------|
| `lib/features/live_record_exercise/screens/workout_screen.dart` | Exercise selector (entry to live session) |
| `lib/features/live_record_exercise/screens/workout_live_camera_screen.dart` | Full-screen camera with stats overlay |

#### Widgets

| File | Purpose |
|------|---------|
| `lib/features/live_record_exercise/widgets/live_camera_connection.dart` | Camera lifecycle owner; exposes controls builder hook |
| `lib/features/live_record_exercise/widgets/live_camera_preview.dart` | Reusable camera preview widget |
| `lib/features/live_record_exercise/widgets/camera_switcher.dart` | Front/back camera toggle control |
| `lib/features/live_record_exercise/widgets/workout_stats.dart` | Overlay scaffold showing reps / phase / stage |
| `lib/features/live_record_exercise/widgets/pose_landmarks_overlay.dart` | Debug skeleton overlay (landmarks) |

#### Services

| File | Purpose |
|------|---------|
| `lib/features/live_record_exercise/services/camera_service.dart` | Camera initialisation + stream |
| `lib/features/live_record_exercise/services/camera_config.dart` | Camera resolution/format config |
| `lib/features/live_record_exercise/services/pose_detection_service.dart` | ML Kit wrapper + frame throttle/lock |

---

### Domain: Exercise Engine

> Stateful calculators that process a stream of ML Kit `Pose` frames and emit `ExerciseFrameResult`.

#### Contracts & Factory

| File | Purpose |
|------|---------|
| `lib/domain/exercises/exercise_calculator.dart` | `ExerciseCalculator` abstract interface |
| `lib/domain/exercises/exercise_calculator_factory.dart` | Maps `ExerciseType` → concrete calculator |
| `lib/domain/exercises/set_lifecycle_controller.dart` | `rest → countdown → active → rest` state machine |

#### Calculators

| File | Exercise |
|------|---------|
| `lib/domain/exercises/calculators/squat_calculator.dart` | Squat |
| `lib/domain/exercises/calculators/push_up_calculator.dart` | Push-up |
| `lib/domain/exercises/calculators/bicep_curl_calculator.dart` | Bicep curl |
| `lib/domain/exercises/calculators/pull_up_calculator.dart` | Pull-up |

#### Models

| File | Purpose |
|------|---------|
| `lib/domain/exercises/models/exercise_frame_result.dart` | Per-frame output (reps, stage, phase, metrics, lifecycle flags) |
| `lib/domain/exercises/models/exercise_frame_metrics.dart` | Numeric metrics bag |
| `lib/domain/exercises/models/exercise_metric.dart` | Single named metric |
| `lib/domain/exercises/models/exercise_rep_phase.dart` | Enum: top / eccentric / bottom / concentric |
| `lib/domain/exercises/models/exercise_set_stage.dart` | Enum: rest / countdown / active |

---

### Common / Shared

| File | Purpose |
|------|---------|
| `lib/common/utils/angle_calculator.dart` | Pure math — 3-landmark angle via dot product |
| `lib/common/services/pose_angle_service.dart` | Convenience wrapper around angle calculator |
| `lib/common/models/exercise_type.dart` | `ExerciseType` enum (squat, pushUp, bicepCurl, pullUp) |
| `lib/common/models/workout_session_model.dart` | Session summary model (for workout log) |

---

### Feature: Workout Log

> Local workout history and basic stats.

| File | Purpose |
|------|---------|
| `lib/features/workout_log/screens/workout_log_screen.dart` | History list screen (placeholder today) |

---

## Architecture at a Glance

```
Camera Stream
  → pose_detection_service.dart   (ML Kit, throttle/lock)
  → ExerciseCalculator.update()   (per-exercise stateful calculator)
      → angle_calculator.dart     (pure math)
      → SetLifecycleController    (rest/countdown/active FSM)
  → ExerciseFrameResult           (reps, phase, stage, metrics, flags)
  → workout_live_camera_screen    (UI consumes result each frame)
      → workout_stats.dart        (overlay)
      → pose_landmarks_overlay    (debug skeleton)
```

---

## Key Concepts

### ExerciseCalculator contract

```dart
// lib/domain/exercises/exercise_calculator.dart
ExerciseFrameResult update(Pose pose, DateTime timestamp, {
  bool startCountdown,
  bool startSet,
  bool endSet,
  bool autoSetLifecycle,
  bool autoEndSetLifecycle,
});
```

### ExerciseFrameResult (UI-friendly output per frame)

```dart
// lib/domain/exercises/models/exercise_frame_result.dart
int reps
ExerciseSetStage setStage       // rest | countdown | active
ExerciseRepPhase repPhase       // top | eccentric | bottom | concentric
ExerciseFrameMetrics metrics    // named numeric values (angles, etc.)
Duration? countdownRemaining

// One-frame lifecycle flags
bool didStartSet
bool didEndSet
bool didEndSetByBreakPose
```

### Angle calculation

3 landmarks → vector dot product → degrees.

```
shoulder → elbow → wrist   →   elbow angle
hip → knee → ankle         →   knee angle
```

### Set lifecycle FSM

```
rest → countdown → active → rest
```

Controlled via `update(...)` signal flags or `autoSetLifecycle: true`.

---

## Backlog Snapshot

| # | Area | Status | Task |
|---|------|--------|------|
| 10 | ENGINE | TODO | Landmark model and mapper |
| 12 | ENGINE | TODO | Add smoothing for angles |
| 17 | UI | TODO | Debug landmarks/skeleton overlay |
| 19 | ENGINE | TODO | Tempo tracking per rep |
| 20 | COACH | TODO | Feedback engine minimal cues |
| 21 | UI | TODO | Performance stats display |

Full backlog: `BACKLOG.md`

---

## Exploration Prompts

Use these directly in Claude Code after loading this file.

### Understand a layer

- "Explain how `workout_live_camera_screen.dart` connects the camera service to the exercise calculator."
- "Walk me through what happens from the moment a camera frame arrives to when the rep counter increments."
- "How does `SetLifecycleController` transition between states?"

### Extend the engine

- "Add angle smoothing to `squat_calculator.dart` using an exponential moving average."
- "Implement tempo tracking per rep in the base `ExerciseCalculator` interface."
- "Add a new exercise calculator for lunges following the same pattern as `squat_calculator.dart`."

### Improve the UI

- "Implement the debug landmarks/skeleton overlay in `pose_landmarks_overlay.dart`."
- "Show tempo (seconds per rep) in `workout_stats.dart` once it is available in `ExerciseFrameResult`."

### Debug / inspect

- "Read `push_up_calculator.dart` and tell me what angle thresholds are used for top and bottom positions."
- "Find all places that consume `ExerciseFrameResult` and list what each reads."
- "Check if `pose_detection_service.dart` properly releases the processing lock after an error."

### Add a feature end-to-end

- "Implement backlog item 20: a minimal feedback engine that emits a cue string ('go lower', 'full lockout') based on `ExerciseFrameResult` and displays it in `workout_stats.dart`."
- "Implement backlog item 19: add `Duration lastRepTempo` to `ExerciseFrameResult` and compute it inside each calculator."

---

## Coding Rules (quick ref)

1. Keep logic modular — no algorithm code inside widgets.
2. All math lives in `common/utils/` or domain calculators.
3. Prefer pure functions for math.
4. No backend streaming, no OpenCV, no extra ML models.
5. Run all Flutter commands with `fvm` (e.g. `fvm flutter analyze`, `fvm flutter test`).

---

## Reference Docs

| File | Contents |
|------|---------|
| `AGENT_CONTEXT.md` | Full architecture, key concepts, coding rules |
| `FEATURES.md` | Epic map + code locations |
| `BACKLOG.md` | Prioritised task list |
| `CLAUDE.md` | Claude Code project instructions |
