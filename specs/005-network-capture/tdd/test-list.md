# Test List — 005 network-capture

| ID | Behavior | Task | Status |
|---|---|---|---|
| C1a | codec decodes the full channel shape — url, method, request headers/body, status, response body, `at` | T001 | DONE |
| C1b | filter serializes `{urlPattern, maxBodyBytes}` | T002 | DONE |
| C2a | `setCaptureEnabled` reaches the port (id + enabled + filter); unknown id → typed `not_created` | T003 | DONE |
| C2b | `captureEvents` guards unknown ids before subscribing; unwired port → `port_not_wired` (both ops) | T003 | DONE |
| C3a | per-webview buffer keeps ingestion order; `clear` empties it; `detach` stops recording | T004 | DONE |
| C3b | stream errors are captured on the manager, not unhandled | T005 | DONE |
| C4a | auth-shaped headers (`Authorization`/`Cookie`, any casing) + url query params (`token=`) → `<redacted>` at ingest; other headers survive | T009 | DONE |
| C4b | `redactAuth: false` keeps values verbatim | T009 | DONE |
| C4c | a malformed query key does not throw; redaction still applies | T010 | DONE |
| C5a | `maxEntries: 2` keeps the latest 2; `maxBodyBytes: 10` truncates the stored body to 10 | T006/T007 | DONE |
| C5b | a negative budget clamps to 0, not a `RangeError` | T008 | DONE |
| C5c | truncation never splits a surrogate pair | T007 | DONE |
| C6 | `filter.matches` is a case-insensitive substring test | T002 | DONE |
| C7a | android adapter: `setCaptureEnabled` args, `captureEvents` decode + id filter, non-map → `malformed_response`, missing source → `channel_not_wired` | T011 | DONE |
| C7b | ios adapter: same contract | T012 | DONE |
| C7c | macos adapter: same contract | T013 | DONE |

Counts: 16 behaviors (C7×3 counted per platform), 16 DONE, 0 remaining.

ID convention: where `packages/zuraffa_inappwebview/test/network_capture_test.dart`
repeats a label the row carries a per-test suffix, so every ID resolves to
exactly one test — `C1a`/`C1b` are its two `C1:` tests, `C2a`/`C2b` its two
`C2:` tests, `C3a`/`C3b` its two `C3:` tests, `C4a`–`C4c` its three `C4:`
tests, `C5a`–`C5c` its three `C5:` tests (`C6:` is unique), and the
Behavior text is the test's own descriptive name. `C7a`/`C7b`/`C7c` are the
identical four-test `C7:` group in the `network capture (spec 005)` group of
`android_webview_adapter_test.dart`, `ios_webview_adapter_test.dart` and
`macos_webview_adapter_test.dart`.

The 005 cycle drove C1a–C6 red → green (9 core tests; `cycle-log.md` records
108/108 repo-wide). C3b, C4c, C5b and C5c are hardening cases appended in
the fixes round; the core file re-runs 13/13 green on this tree.
