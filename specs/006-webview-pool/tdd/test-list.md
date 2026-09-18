# Test List — 006 webview-pool

| ID | Behavior | Task | Status |
|---|---|---|---|
| P1 | same session → same id, one create+run, sessions()/liveCount | T001 | DONE |
| P2 | release → warm idle (no dispose), session list updates | T002 | DONE |
| P3 | idle same-eTLD+1 instance reused across sessions | T003 | DONE |
| P4 | different domain → fresh instance | T004 | DONE |
| P8 | a reused instance is reset to `about:blank` first, so the previous session's page state is not inherited | T003 | DONE |
| P5a | maxLive overflow evicts the idlest (victim identity asserted, not just the count); liveCount respects cap | T005 | DONE |
| P5b | saturated (all active) → typed pool_exhausted | T005 | DONE |
| P6 | idleTtl sweep disposes stale idles (injected clock) | T006 | DONE |
| P7 | disposeAll → zero instances, service registry empty | T007 | DONE |

Counts: 9 behaviors, 9 driven red → green, 0 remaining.

## Revision (2026-09-18, review follow-up)

- P5a asserted only the dispose *count*, which cannot tell the idle instance
  being evicted from the active one being killed; it now asserts the evicted
  id (`disposedIds`) and that the live session keeps its instance.
- P8 added: reuse used to hand the new session the previous session's live
  page state. The pool now navigates a reused instance to `about:blank`
  first; the platform cookie store stays global and is not reset.
