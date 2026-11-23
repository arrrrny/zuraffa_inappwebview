# Tasks: VCR Record/Replay

**Input**: Design documents from `/specs/008-vcr-record-replay/`

- [x] T001 `[TDD]` (US1, V1) recorder: ordered entries with html/cookie snapshots; captures attach to their navigation
- [x] T002 `[TDD]` (US1, V2) cassette JSON round-trip; defensive redaction of recorded captures
- [x] T003 `[TDD]` (US2, V3) exact-match offline serving via loadHtml
- [x] T004 `[TDD]` (US2, V4) path-prefix best-match fallback
- [x] T005 `[TDD]` (US2/US3, V5) vcr_unmatched strict failure naming url; soft mode no-op
- [x] T006 `[TDD]` (US2, V6) synthesized capture events on the broadcast stream
- [x] T007 `[TDD]` (US4, V7) loadHtml adapter contract ×3
- [x] T008 barrel export; repo-wide analyze + tests green
