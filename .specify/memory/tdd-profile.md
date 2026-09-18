# TDD Profile — zuraffa_inappwebview

Detected stack: **pure Dart federated plugin monorepo** (no Flutter runtime
needed — every package is Dart-only with injected transports, so tests run on
the VM).

- `detected_at`: commit 18b5d73 (webview MVP), verified 2026-09-17.
- `verified`: every command below was executed and passed before recording.

## Commands (run from the touched package directory)

| Step | Command | Notes |
|---|---|---|
| deps | `dart pub get` | once per package after editing pubspec |
| analyze | `dart analyze` | must print `No issues found!` |
| test (red/green loop) | `dart test` | per package; failing output is the red proof |
| test (whole repo) | `for p in packages/*/; do (cd "$p" && dart test); done` | all five packages |

## Packages

- `packages/zuraffa_inappwebview` — app-facing (port, service, usecases,
  module). Primary target for feature behavior tests.
- `packages/zuraffa_inappwebview_platform` — channel envelope core.
- `packages/zuraffa_inappwebview_android` / `_ios` / `_macos` — adapters;
  tested with scripted fake invoke maps.

## Baseline at detection

android 6 · ios 6 · macos 6 · platform 6 · app 17 = **41 tests**, analyze
clean everywhere.

## Conventions

- Red proof = the new test file fails to compile or fails its assertions
  before the behavior exists; green = `dart test` passes with it.
- Behavior tests live in `test/<feature>_test.dart` per package; specs record
  the per-behavior evidence in `specs/<NNN>-<slug>/tdd/cycle-log.md`.
- No `flutter test` anywhere — nothing depends on a Flutter runtime.
