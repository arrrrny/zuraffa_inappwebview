# Tasks: Webview Pool

**Input**: Design documents from `/specs/006-webview-pool/`

- [x] T001 `[TDD]` (US1, P1) session-scoped acquire — same id, one create+run
- [x] T002 `[TDD]` (US1, P2) release keeps warm idle; sessions() updates
- [x] T003 `[TDD]` (US2, P3, P8) domain affinity reuse (eTLD+1) — the reused instance is reset to `about:blank` before it is handed over
- [x] T004 `[TDD]` (US2, P4) cross-domain isolation
- [x] T005 `[TDD]` (US3, P5a/P5b) maxLive LRU-idle eviction + pool_exhausted
- [x] T006 `[TDD]` (US3, P6) idleTtl lazy sweep with injected clock
- [x] T007 `[TDD]` (US4, P7) disposeAll zero-state
- [x] T008 barrel export; repo-wide analyze + tests green
