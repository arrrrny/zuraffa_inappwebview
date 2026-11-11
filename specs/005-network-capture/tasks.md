# Tasks: Network Capture — Mission-Grade Intercept

**Input**: Design documents from `/specs/005-network-capture/`

## Phase 1: Entry seam (app + platform)

- [x] T001 `[TDD]` (US1, C1) `WebviewCaptureEntry` codec: url/method/request+response headers/bodies/status/at — `network_capture.dart`
- [x] T002 `[TDD]` (US1, C2) port `setCaptureEnabled` + `captureEvents`; service `not_created` guards; unwired `port_not_wired` — `webview_port.dart`, `webview_service.dart`
- [x] T003 `[TDD]` (US1, C6) `WebviewCaptureFilter` serialization + `matches` (case-insensitive substring)

## Phase 2: Manager — buffer, budgets, redaction

- [x] T004 `[TDD]` (US2, C3) ordered per-id buffer; `entries`; `clear`; `attach`/`detach`
- [x] T005 `[TDD]` (US2, C5) `CaptureBudget`: `maxEntries` keeps latest, `maxBodyBytes` truncates at ingest
- [x] T006 `[TDD]` (US3, C4) `CaptureSecretRedactor`: header + query-param keys → `<redacted>` before any consumer observes the entry; `redactAuth: false` escape hatch

## Phase 3: Adapters

- [x] T007 `[TDD]` (US4, C7a) android: `setCaptureEnabled` args, `captureEvents` decode + id filter, typed `malformed_response`, `channel_not_wired`, `register` forwards `eventSource`
- [x] T008 `[TDD]` (US4, C7b) ios: same
- [x] T009 `[TDD]` (US4, C7c) macos: same

## Phase 4: Wiring (non-behavior)

- [x] T010 barrel exports (`kRedactionMarker`, capture types) + `FEATURES.md` 005 row
- [x] T011 repo-wide analyze + tests green (108/108)

## Phase 5: Review-fix round (PR #4 findings)

- [x] T012 `[TDD]` (US3, C8) `redactUrl` tolerates malformed percent-encoding — `FormatException`/`ArgumentError` fall back to the raw key
- [x] T013 `[TDD]` (US2/US3, C9 + N9) `attach` subscribes with `onError`, so adapter stream errors are contained instead of leaking an unhandled async error into the consumer's zone
- [x] T014 `[TDD]` (US2, C10) `maxBodyBytes` counts UTF-8 bytes and cuts on a character boundary (`_truncateUtf8`)
- [x] T015 `[TDD]` (US3, C11) widened secret carriers: `x-api-key`/`x-csrf-token`/`x-auth-token`/`x-amz-security-token` headers; `key`/`signature`/`sig`/`hmac`/`session_id`/`auth` params
- [x] T016 `[TDD]` (US4, C7 + N8) adapters filter raw payloads by `id` **before** decoding (per-subscriber error scoping) ×3
- [x] T017 `[TDD]` (US3, S6) adapter `_decodeBytes` returns a `List<int>` as-is and raises the typed `malformed_response` for non-int elements ×3
- [x] T018 `[TDD]` (US2, S7) `ScreenshotConfiguration.quality` clamps to the documented 1–100
- [x] T019 `[TDD]` (US1, N8) unknown navigation `type` → `WebviewNavigationPhase.unknown`; `NavigationTracker.clear(id)`
- [x] T020 artifact hygiene: this file + `tdd/test-list.md` (both were committed empty); D3–D5 marked contract-pinning
- [x] T021 analyze + tests green (128/128)
