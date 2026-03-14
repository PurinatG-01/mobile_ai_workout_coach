# Epics

1. Live Record Exercise
2. Workout Log

## Code Map

- Live Record Exercise code lives under `lib/features/live_record_exercise/`
- Workout Log code lives under `lib/features/workout_log/`
- Shared cross-epic code lives under `lib/shared/`
- App entrypoints: `lib/main.dart` (bootstrap) and `lib/app/app.dart` (MaterialApp.router)
- Router: `lib/app/router.dart`
- Navigation shell: `lib/app/shell/app_shell.dart`

## Navigation

The current app navigation is epic-based and uses two routes:

- Live Record Exercise: `/live`
- Workout Log: `/log`

---

## 1) Live Record Exercise

Goal: Let a user start a live session using the camera, run on-device pose detection, and show real-time rep counting + phase/tempo + basic cues.

Key features (rough):

- Session controls: exercise select, start/stop, reset session
- Camera + permissions: request permission, show preview, handle denied state
- Real-time inference loop: frame throttle/lock, run pose detection, map landmarks
- Engine outputs: joint angles, movement phase state machine, rep counting
- Live UI overlays: reps, phase, tempo (later), optional debug skeleton overlay
- Basic feedback: simple cues (e.g., “go lower”, “full lockout”) with debouncing
- Performance guardrails: avoid processing every frame; keep UI smooth

Out of scope (for now):

- Backend video upload/streaming
- Heavy CV (OpenCV) or extra ML models beyond ML Kit

## 2) Workout Log

Goal: Persist completed workout sessions locally so the user can review history and basic stats.

Key features (rough):

- Session summary model: date/time, exercise type, reps, duration, tempo summary (later)
- Local persistence: store/retrieve workout sessions (local-only; no backend required)
- History UI: list of past sessions + simple details view (or expandable row)
- Basic analytics: totals per day/week, per-exercise counts (simple aggregates)
- Data lifecycle: delete session, clear all data

Out of scope (for now):

- Cloud sync, accounts, multi-device history
- Model training/analytics upload
