# Tasks: Network Capture — Mission-Grade Intercept

**Input**: Design documents from `/specs/005-network-capture/`

**Tests**: mandatory — every behavior task (marked `[TDD]`) is driven
red → green via `tdd/test-list.md` before its implementation is counted done.

## Phase 1: Foundational — the typed entry + filter

- [x] T001 `[TDD]` (US1, C1) `WebviewCaptureEntry` + `fromChannelArgs` codec (url, method, request/response headers+bodies, status, `at`) — NEW `packages/zuraffa_inappwebview/lib/src/network_capture.dart`
- [x] T002 `[TDD]` (US1, C1) `WebviewCaptureFilter` (urlPattern, maxBodyBytes) serialized as channel args for the enable call — same file

## Phase 2: The manager — buffer + budgets

- [x] T003 `[TDD]` (US2, C3) `NetworkCaptureManager` attach/detach/ingest/entries/clear over an ordered per-id buffer — same file
- [x] T004 `[TDD]` (US2, C5) `CaptureBudget` enforced at ingestion: `maxEntries` keeps the latest, `maxBodyBytes` truncates bodies on a UTF-8 byte budget, stopping on a rune boundary — same file

## Phase 3: Redaction

- [x] T005 `[TDD]` (US3, C4) `CaptureSecretRedactor` (zikzak A15 key lists, marker `<redacted>`) applied at ingest unless `redactAuth: false`; `redactUrl` preserves non-secret params and any `#fragment` — same file

## Phase 4: The seam

- [x] T006 `[TDD]` (US1, C2) `WebviewPort.setCaptureEnabled` + `captureEvents`; `WebviewService` ops with `_requireCreated` guards (`not_created` on the future, and on the stream for `captureEvents`) and `UnwiredWebviewPort` `port_not_wired` — `lib/src/webview_port.dart`, `lib/src/webview_service.dart`

## Phase 5: Adapters

- [x] T007 `[TDD]` (US4, C7a–C7c) android/ios/macos ports: `setCaptureEnabled` envelope call (id + enabled + filter spread), `captureEvents` decode + id filter, `malformed_response` for a non-map payload, `channel_not_wired` without an event source — `packages/zuraffa_inappwebview_{android,ios,macos}/lib/src/*_webview_port.dart` (+ adapter tests)
- [x] T008 export `network_capture.dart` from the package barrel `lib/zuraffa_inappwebview.dart`
- [x] T009 `dart analyze` + `dart test` green across all five packages

## Review follow-up (2026-09-18)

- C6 (`WebviewCaptureFilter.matches`) dropped: the predicate was dead
  production code and FR-1 only asks the filter to ride the enable call, so
  matching stays the platform's job — `matches` and its test are removed.
- T004/T005 extended: `maxBodyBytes` is a UTF-8 byte budget on a rune
  boundary, and `redactUrl` keeps a trailing `#fragment`.
