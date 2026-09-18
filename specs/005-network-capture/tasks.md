# Tasks: Network Capture

**Input**: Design documents from `/specs/005-network-capture/`

- [x] T001 `[TDD]` (US1, C1a) `WebviewCaptureEntry` + `fromChannelArgs` codec — url, method, request/response headers, request/response bodies, status, `at`
- [x] T002 `[TDD]` (US1, C1b/C6) `WebviewCaptureFilter` — `urlPattern` + `maxBodyBytes` serialization; case-insensitive substring `matches`
- [x] T003 `[TDD]` (US1, C2a/C2b) port ops `setCaptureEnabled` + `captureEvents` on the spec-004 event seam; service `not_created` guard; unwired `port_not_wired`
- [x] T004 `[TDD]` (US2, C3a) `NetworkCaptureManager` — attach/detach/ingest/entries/clear; per-webview ordered buffer
- [x] T005 `[TDD]` (US2, C3b) stream failures land on the manager (`error(id)`, `dispose`) instead of escaping the zone
- [x] T006 `[TDD]` (US2, C5a) `CaptureBudget.maxEntries` — overflow keeps the latest entries
- [x] T007 `[TDD]` (US2, C5c) `maxBodyBytes` truncates string bodies at ingest without splitting a surrogate pair
- [x] T008 `[TDD]` (US2, C5b) negative budget values clamp to 0 (no `RangeError`)
- [x] T009 `[TDD]` (US3, C4a/C4b) `CaptureSecretRedactor` at ingest — auth header keys + url query params → `<redacted>`; on by default, `redactAuth: false` opts out
- [x] T010 `[TDD]` (US3, C4c) malformed url query keys never throw and never block redaction of the rest
- [x] T011 `[TDD]` (US4, C7a) android adapter: `setCaptureEnabled` call args, `captureEvents` on the event-source shape (decode + id filter), `malformed_response`, `channel_not_wired`
- [x] T012 `[TDD]` (US4, C7b) ios adapter — same contract
- [x] T013 `[TDD]` (US4, C7c) macos adapter — same contract
- [x] T014 barrel export (`network_capture.dart`); the four existing port test fakes widened mechanically; repo-wide analyze + tests green
