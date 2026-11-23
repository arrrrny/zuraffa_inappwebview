# Test List — 003 screenshot-pdf-export

| ID | Behavior | Task | Status |
|---|---|---|---|
| S1 | `ScreenshotConfiguration` defaults png/100, serializes `{format, quality}`; jpeg/80 overrides | T001 | DONE |
| S2 | service `takeScreenshot`/`exportPdf` pass bytes through unchanged | T002 | DONE |
| S3 | null port result → null service result (no throw) | T002 | DONE |
| S4 | unknown id → typed `not_created` (both ops) | T002 | DONE |
| S5 | `UnwiredWebviewPort` → `port_not_wired` (both ops) | T002 | DONE |
| S6a | android adapter: forwards `takeScreenshot` + config args, decodes `data`, null passthrough, `malformed_response` on non-list, `exportPdf` method name | T003 | DONE |
| S6b | ios adapter: same contract | T004 | DONE |
| S6c | macos adapter: same contract | T005 | DONE |

Counts: 9 behaviors (S6×3 counted per platform), 9 driven red → green, 0 remaining.
