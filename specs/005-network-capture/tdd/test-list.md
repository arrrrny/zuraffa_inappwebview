# Test List — 005 network-capture

| ID | Behavior | Task | Status |
|---|---|---|---|
| C1 | entry codec decodes url/method/headers/bodies/status/at | T001 | DONE |
| C2 | service `setCaptureEnabled`/`captureEvents`; `not_created` guards; unwired `port_not_wired` | T002 | DONE |
| C3 | manager ordered per-id buffer, `entries`, `clear`, `attach`/`detach` | T004 | DONE |
| C4 | auth-shaped header values + url params redacted at ingest; `redactAuth: false` keeps values | T006 | DONE |
| C5 | `maxEntries` keeps the latest; `maxBodyBytes` truncates the stored body | T005 | DONE |
| C6 | `WebviewCaptureFilter` serializes `{urlPattern, maxBodyBytes}`; `matches` is a case-insensitive substring test | T003 | DONE |
| C7a | android adapter: enable args, id-filtered decode, typed `malformed_response` on non-map, `channel_not_wired` without a source | T007 | DONE |
| C7b | ios adapter: same contract | T008 | DONE |
| C7c | macos adapter: same contract | T009 | DONE |
| C8 | `redactUrl` falls back to the raw query key on malformed percent-encoding (never throws) | T012 | DONE |
| C9 | `NetworkCaptureManager.attach` contains stream errors; later entries still ingest | T013 | DONE |
| C10 | `maxBodyBytes` is UTF-8 bytes; a multi-byte body is cut on a character boundary (no U+FFFD) | T014 | DONE |
| C11 | widened secret carriers (`x-api-key`, `x-amz-security-token`, `session_id`, `signature`) redacted | T015 | DONE |

Counts: 12 behaviors (C7×3 counted per platform), 12 DONE.
