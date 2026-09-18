# Test List — 009 portable-sessions

| ID | Behavior | Task | Status |
|---|---|---|---|
| PS1 | save snapshots cookies + localStorage (canonical JSON read) into the store | T001 | DONE |
| PS2 | load re-applies cookies + setItem writes | T002 | DONE |
| PS3 | missing name → typed session_not_found, nothing applied | T003 | DONE |
| PS4 | JSON round-trip + delete + list through the store | T004 | DONE |

Counts: 4 behaviors, 4 driven red → green, 0 remaining.
