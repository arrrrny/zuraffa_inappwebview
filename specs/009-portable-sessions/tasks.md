# Tasks: Portable Sessions

**Input**: Design documents from `/specs/009-portable-sessions/`

- [x] T001 `[TDD]` (US1, PS1) save snapshots cookies + localStorage via the canonical read into the store
- [x] T002 `[TDD]` (US2, PS2) load re-applies cookies + setItem writes
- [x] T003 `[TDD]` (US2, PS3) missing name → typed session_not_found, nothing applied
- [x] T004 `[TDD]` (US3, PS4) JSON round-trip + delete + list through the store
- [x] T005 barrel export; repo-wide analyze + tests green
- [x] T006 `[TDD]` (US1/US2, PS5/PS6) review fixes: `jsonEncode`-built setItem script + typed non-JSON read
