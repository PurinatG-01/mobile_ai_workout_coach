# AI Workout Coach – Agent Context

## Project Overview

This project aims to build a **real-time AI workout coach** that runs directly on a mobile device using **Flutter**.

The system detects human body pose from the camera and analyzes movement to:

- count exercise repetitions
- detect movement phases (eccentric/concentric)
- estimate tempo
- provide basic form feedback

The goal is **real-time on-device inference**, avoiding backend video processing.

This project evolves from an experimental Python prototype:
https://github.com/PurinatG-01/ai-workout-coach

The Python project validated:

- pose detection pipeline
- angle calculations
- rep counting logic

The Flutter project is the **production prototype**.

---

# Core Technology

### Framework

Flutter (Dart)

### Pose Detection

Google ML Kit Pose Detection via `google_mlkit_pose_detection`.

### Processing Strategy

All pose detection and movement analysis run **on device**.

The backend is optional and may later store:

- workout history
- analytics
- model improvements

---

# High Level Architecture

Camera Stream
→ Pose Detection
→ Landmark Extraction
→ Angle Calculation
→ Movement Phase Detection
→ Rep Counter
→ Set Lifecycle (rest/countdown/active)
→ Feedback Engine
→ UI

No video streaming to backend.

---

# Camera (Current)

Native camera access is planned via the Flutter `camera` plugin.

Default behavior:

- The live camera experience prefers the front camera when available (users can switch cameras in-app).

Implementation building blocks live under:

- `lib/features/live_record_exercise/services/camera_service.dart`
- `lib/features/live_record_exercise/services/camera_config.dart`
- `lib/features/live_record_exercise/services/pose_detection_service.dart` (ML Kit wrapper + throttle/lock)
- `lib/features/live_record_exercise/widgets/live_camera_connection.dart` (owns camera lifecycle + exposes external camera-controls builder)
- `lib/features/live_record_exercise/widgets/live_camera_preview.dart`
- `lib/features/live_record_exercise/widgets/camera_switcher.dart` (camera selection control)
- `lib/features/live_record_exercise/screens/workout_live_camera_screen.dart` (full-screen camera + overlays)
- `lib/features/live_record_exercise/widgets/workout_stats.dart` (overlay scaffold; placeholder values)

---

# Folder Structure (Epic-based)

lib/

app/

- app.dart
  App entry (MaterialApp.router).

- router.dart
  Central `go_router` configuration.

- shell/
  AppShell scaffold (AppBar + bottom navigation).

features/

- live_record_exercise/
  The real-time camera + pose + rep counting experience.
  - screens/ (screens)
  - widgets/ (shared UI widgets)
  - services/ (camera + pose wrappers)
  - (later) state/ (feature state management)

- workout_log/
  Local workout history and simple stats.
  - screens/
  - widgets/
  - (later) data/ (storage)
  - (later) domain/

shared/

- engine/ (math helpers like angle calculation)
- models/ (shared models like exercise types)

domain/

- exercises/
  Exercise “engine” implementations.
  - Calculator contract + per-exercise calculators
  - Set lifecycle controller for set state transitions
  - Frame output model for UI consumption

---

# Navigation (Current)

The app uses a 2-tab shell aligned to the 2 epics:

- Live Record Exercise: `/live`
- Workout Log: `/log`

The live camera experience is a dedicated full-screen route rendered above the shell scaffold:

- Live Camera: `/live/camera`

---

# Key Concepts

## Exercise Calculators (Domain)

Exercise logic is implemented as stateful calculators that process a stream of ML Kit `Pose` frames.

- `ExerciseCalculator.update(...)` consumes a single frame (pose + timestamp) and returns an `ExerciseFrameResult`.
- The output is intentionally UI-friendly: reps, set stage, rep phase, metrics, and optional countdown remaining.

### Set Lifecycle

Set start/end is modeled as a small state machine:

rest → countdown → active → rest

This behavior is encapsulated in `SetLifecycleController`.

Coupling rule:

- `SetLifecycleController` is intentionally not exposed via the `ExerciseCalculator` interface.
  - Calculators own lifecycle internally.
  - For testing/modularity, calculators may accept an optional injected lifecycle controller in their constructor.
  - Callers control behavior via `update(...)` signals/flags (`startCountdown`, `startSet`, `endSet`, `autoSetLifecycle`, `autoEndSetLifecycle`).

## Landmarks

Pose detection returns body landmarks:

Example:

- shoulder
- elbow
- wrist
- hip
- knee
- ankle

Each landmark has:

- x
- y
- z
- confidence

Only x,y are required for most calculations.

---

## Angle Calculation

Angles are computed from 3 landmarks.

Example: elbow angle

shoulder → elbow → wrist

Angle calculation uses vector dot product.

---

## Movement Phase Detection

Each exercise is modeled as a **state machine**.

Example (Push-Up):

TOP
↓
ECCENTRIC
↓
BOTTOM
↓
CONCENTRIC
↓
REP COMPLETE

Transitions depend on angle thresholds.

---

## Rep Counting

A repetition is counted when a full movement cycle occurs.

Example Push-Up:

Elbow Angle

Top Position: >160°
Bottom Position: <90°

Rep counted when:
bottom → top transition completes.

---

# Performance Requirements

Target camera FPS: 30

Pose detection processing:
10–15 FPS

Avoid processing every frame.

Use a processing lock:

if (isProcessing) return;

---

# First Supported Exercises

1. Squats
2. Push-ups
3. Pull-ups

These exercises validate the system.

Additional exercises can be added later.

---

# Coding Rules for Agents

Agents must follow these rules:

1. Keep logic modular.
2. Do not mix UI and algorithm code.
3. Avoid heavy computation inside UI widgets.
4. All calculations should live inside domain/common/shared helpers (not inside widgets).
5. Prefer pure functions for math logic.
6. Avoid introducing backend dependencies.

---

# What Agents Should NOT Do

Agents must NOT:

- introduce backend streaming
- process full video frames manually
- add OpenCV to Flutter
- add unnecessary machine learning models

Pose detection is already handled by ML Kit.

---

# Current Development Goals

Milestone 1:

Implement real-time squat counter.

Requirements:

- detect knee angle
- detect bottom position
- detect standing position
- count repetitions

Accuracy target:

> 90% correct reps.

---

Milestone 2:

Add push-up detection.

---

Milestone 3:

Add tempo detection.

Example output:

Rep 4
Tempo: 2.1 seconds
Form: Good

---

# Long-Term Vision

Transform the system into a **real-time AI workout coach** capable of:

- rep counting
- tempo tracking
- form scoring
- stability analysis
- personalized coaching

All running locally on mobile devices.

---

# Agent Behavior Guidelines

Agents assisting this project should:

- prioritize readability
- prioritize performance
- avoid overengineering
- produce minimal but correct implementations
- explain complex math when adding algorithms

Agents should prefer incremental improvements rather than large rewrites.

---

# Definition of Success

A user opens the app, points the camera at themselves, performs an exercise, and the app:

- counts reps correctly
- identifies movement phase
- runs smoothly on a phone
