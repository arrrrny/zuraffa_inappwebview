# Tasks: WebView Agent Tools

**Input**: Design documents from `/specs/010-webview-agent-tools/`

- [x] T001 `[TDD]` (US1, A1) six tools, named/described/object-schemas, idempotent build
- [x] T002 `[TDD]` (US2, A2) browse: validated url + pooled acquire + load
- [x] T003 `[TDD]` (US2, A3) session continuity: execute_js reuses the browse instance (one create)
- [x] T004 `[TDD]` (US2, A4) defensive validation: typed failure degrades to isError; missing args → isError
- [x] T005 `[TDD]` (US3, A5–A8) read_cookies list; screenshot artifactRef+byteLength (no body); dismiss canonical script; release_session
- [x] T006 barrel export; repo-wide analyze + tests green
