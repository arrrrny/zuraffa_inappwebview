# Test List — 008 vcr-record-replay

| ID | Behavior | Task | Status |
|---|---|---|---|
| V1 | recorder produces ordered entries (url/html/cookies); captures attach to their navigation | T001 | DONE |
| V2 | cassette JSON round-trip; defensive redaction | T002 | DONE |
| V3 | exact-match serving via loadHtml (html + baseUrl) | T003 | DONE |
| V4 | path-prefix best-match fallback (query-insensitive) | T004 | DONE |
| V5 | strict vcr_unmatched naming url; soft mode no-op | T005 | DONE |
| V6 | synthesized captures on the broadcast stream, in order | T006 | DONE |
| V7 | loadHtml adapter contract (method + 3 args) ×3 | T007 | DONE |

Counts: 7 behaviors, 7 driven red → green, 0 remaining.
