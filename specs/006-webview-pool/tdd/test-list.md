# Test List — 006 webview-pool

| ID | Behavior | Task | Status |
|---|---|---|---|
| P1 | same session → same id, one create+run, sessions()/liveCount | T001 | DONE |
| P2 | release → warm idle (no dispose), session list updates | T002 | DONE |
| P3 | idle same-eTLD+1 instance reused across sessions | T003 | DONE |
| P4 | different domain → fresh instance | T004 | DONE |
| P4b | IP literals are their own domain (no cross-host reuse) | T004 | DONE |
| P5a | maxLive overflow evicts the idlest; liveCount respects cap | T005 | DONE |
| P5b | saturated (all active) → typed pool_exhausted | T005 | DONE |
| P5c | per-domain cap with every instance live → typed pool_exhausted | T005 | DONE |
| P5d | warm same-domain instance is reused, not evicted, at cap | T005 | DONE |
| P6 | idleTtl sweep disposes stale idles (injected clock) | T006 | DONE |
| P7 | disposeAll → zero instances, service registry empty | T007 | DONE |
| P8 | failed runHeadless disposes the created webview (no leak) | T007 | DONE |
| P9 | failed dispose keeps the instance retryable | T007 | DONE |
| P9b | disposeAll attempts every instance before surfacing the error | T007 | DONE |

Counts: 14 behaviors, 14 driven red → green, 0 remaining.
