# Test List — 007 session-recipes

| ID | Behavior | Task | Status |
|---|---|---|---|
| R1 | completed main-frame visits → ordered url steps | T001 | DONE |
| R2 | taps interleave in recording order | T002 | DONE |
| R3 | empty recorder → empty named recipe | T003 | DONE |
| R4 | started/sub-frame events ignored | T004 | DONE |
| R5 | ordered drive + progress (0..n-1 of total) + completed result | T005 | DONE |
| R6 | driver failure → failedStep + error, partial drive, no throw | T006 | DONE |
| R7 | service driver: validated loadUrl + canonical click script | T007 | DONE |
| R8 | tap selector is JSON-escaped into a parsable JS literal (quotes, backslashes) | T007 | DONE |
| R9 | tap on a selector matching nothing is a no-op (`?.click()`, not a throw) | T007 | DONE |

Counts: 9 behaviors, 9 driven red → green, 0 remaining.
