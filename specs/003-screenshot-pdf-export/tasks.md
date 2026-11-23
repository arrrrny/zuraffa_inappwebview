# Tasks: Screenshot & PDF Export

**Input**: Design documents from `/specs/003-screenshot-pdf-export/`

## Phase 1: Types + port surface

- [x] T001 `[TDD]` (US2, S1) `ScreenshotConfiguration` defaults + serialization — `webview_types.dart`
- [x] T002 `[TDD]` (US1, S2) port ops `takeScreenshot`/`exportPdf` declared; service passthrough (bytes + null) with `not_created` guard; unwired port raises `port_not_wired` — `webview_port.dart`, `webview_service.dart`

## Phase 2: Adapters (identical ×3)

- [x] T003 `[TDD]` (US3, S6a) android adapter: method/args forwarding, `data` decode, `malformed_response`, null passthrough — `android_webview_port.dart` + test
- [x] T004 `[TDD]` (US3, S6b) ios adapter — `ios_webview_port.dart` + test
- [x] T005 `[TDD]` (US3, S6c) macos adapter — `macos_webview_port.dart` + test

## Phase 3: Wiring (non-behavior)

- [x] T006 barrel exports (`ScreenshotConfiguration`, `ScreenshotFormat`) + adapter doc-comment contract lists
- [x] T007 repo-wide analyze + tests green
