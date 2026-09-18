# Test List — 005 network-capture

Behaviors derived from spec.md acceptance scenarios + plan.md. C1–C5 live in
`packages/zuraffa_inappwebview/test/network_capture_test.dart` (fake-port
pattern, no platform needed); C7a–C7c in the three adapter test files
(`packages/zuraffa_inappwebview_{android,ios,macos}/test/`).

| ID | Behavior | Task | Status |
|---|---|---|---|
| C1 | entry codec decodes the full channel shape (url, method, headers, bodies, status, `at`); the filter serializes `urlPattern` + `maxBodyBytes` | T001, T002 | DONE |
| C2 | `setCaptureEnabled` reaches the port with id + enabled + filter; unknown id → typed `not_created` (future rejection, stream error for `captureEvents`); unwired port → `port_not_wired` | T006 | DONE |
| C3 | ordered per-id buffer, `clear`, `attach`/`detach` | T003 | DONE |
| C4 | auth-shaped header values and url params redacted at ingest; `redactUrl` is whole-string stable — secret last, non-secret params and `#fragment` kept; `redactAuth: false` keeps values verbatim | T005 | DONE |
| C5 | budgets: `maxEntries` keeps the latest; `maxBodyBytes` truncates on a UTF-8 byte budget, so a 4-byte rune is never cut and no lone surrogate is emitted | T004 | DONE |
| C7a | adapter `setCaptureEnabled` ships id + enabled + filter args | T007 | DONE |
| C7b | adapter `captureEvents` decodes entries and filters by id | T007 | DONE |
| C7c | non-map capture event → `malformed_response`; missing event source → `channel_not_wired` | T007 | DONE |

Counts: 8 behaviors — 8 driven red → green, 0 remaining.

## Revision (2026-09-18, review follow-up)

- C6 (`WebviewCaptureFilter.matches` is a case-insensitive substring test)
  removed together with the method: it was dead production code — nothing in
  `lib/` called it, and FR-1 only requires the filter to ride the enable
  call, so matching is the platform's responsibility.
- C4 extended with the fragment/whole-string cases (the redactor used to drop
  a `#fragment` that trailed a redacted param).
- C5 extended with the byte-budget case (the cap used to count UTF-16 code
  units and could emit a lone surrogate).
