# Test List — 006 webview-pool

| ID | Behavior | Task | Status |
|---|---|---|---|
| P1 | same session → same id, one create+run, sessions()/liveCount | T001 | DONE |
| P2 | release → warm idle (no dispose), session list updates | T002 | DONE |
| P3 | idle same-eTLD+1 instance reused across sessions | T003 | DONE |
| P4 | different domain → fresh instance | T004 | DONE |
| P5a | maxLive overflow evicts the idlest; liveCount respects cap | T005 | DONE |
| P5b | saturated (all active) → typed pool_exhausted | T005 | DONE |
| P6 | idleTtl sweep disposes stale idles (injected clock) | T006 | DONE |
| P7 | disposeAll → zero instances, service registry empty | T007 | DONE |

Counts: 8 behaviors, 8 driven red → green, 0 remaining.
