# Tasks: Webview Pool

**Input**: Design documents from `/specs/006-webview-pool/`

- [x] T001 `[TDD]` (US1, P1) session-scoped acquire — same id, one create+run
- [x] T002 `[TDD]` (US1, P2/P12) release keeps warm idle; sessions() updates; releasing an unknown session is a no-op
- [x] T003 `[TDD]` (US2, P3) domain affinity reuse (eTLD+1) — the reused instance is navigated to `about:blank` so no document/JS state crosses missions
- [x] T004 `[TDD]` (US2, P4) cross-domain isolation
- [x] T005 `[TDD]` (US3, P5a/P5b) maxLive LRU-idle eviction + pool_exhausted
- [x] T006 `[TDD]` (US3, P6) idleTtl lazy sweep with injected clock
- [x] T007 `[TDD]` (US4, P7) disposeAll zero-state
- [x] T008 barrel export; repo-wide analyze + tests green
- [x] T009 `[TDD]` (US3, P8a–P8d) `maxPerDomain` cap (FR-6): an idle same-domain instance is reused, a third live instance on a domain → typed `pool_exhausted`, releasing one session frees a slot, other domains unaffected
- [x] T010 `[TDD]` (US5, P9–P13) acquire is serialised (overlapping acquires create one instance and cannot overshoot `maxLive`); a `runHeadless` failure disposes the created webview; `hasSession`
