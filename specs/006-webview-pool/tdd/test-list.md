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
| P8a | an idle same-domain instance is reused, not capped out | T009 | DONE |
| P8b | a third live instance on one domain → typed `pool_exhausted` with free maxLive slots | T009 | DONE |
| P8c | releasing one session frees a per-domain slot | T009 | DONE |
| P8d | another domain is unaffected by the cap | T009 | DONE |
| P9 | overlapping acquires for one session create exactly one instance | T010 | DONE |
| P10 | overlapping acquires cannot overshoot `maxLive` | T010 | DONE |
| P11 | a `runHeadless` failure disposes the created webview (no leak) | T010 | DONE |
| P12 | `release` on an unknown session is a no-op | T002 | DONE |
| P13 | `hasSession` tracks acquire/release | T010 | DONE |

Counts: 17 behaviors, 17 DONE, 0 remaining. (`P3` now also asserts the
`about:blank` reset on warm reuse; P8a–P8d, P9–P13 were appended in the
fixes round.)
