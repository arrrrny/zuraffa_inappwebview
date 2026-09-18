# Test List — 010 webview-agent-tools

| ID | Behavior | Task | Status |
|---|---|---|---|
| A1 | six tools with names/descriptions/object schemas; idempotent | T001 | DONE |
| A2 | browse: validated url, pooled acquire, load, webviewId | T002 | DONE |
| A3 | session continuity: execute_js same webviewId, one create | T003 | DONE |
| A4 | typed failure → isError (no throw); missing arg → isError | T004 | DONE |
| A5 | read_cookies returns cookie maps | T005 | DONE |
| A6 | screenshot: bytes to the caller without a sink (never a byte array in `data`); sink ref + byteLength with one | T005 | DONE |
| A7 | dismiss_dialogues applies the canonical 002 script | T005 | DONE |
| A8 | release_session empties the session list | T005 | DONE |
| A9 | unknown/released session → typed `session_not_started`, no instance created | T007 | DONE |

Counts: 9 behaviors, 9 driven red → green, 0 remaining.
