# Tasks: Navigation Tracking

**Input**: Design documents from `/specs/004-navigation-tracking/`

## Phase 1: Event seam (app + platform)

- [x] T001 `[TDD]` (US1, N1) `WebviewNavigationEvent` codec: decode started/completed/failed, isMainFrame default, errorCode passthrough, unrecognized phase → null, wrong-typed fields → typed `malformed_response` — `navigation_tracking.dart`
- [x] T002 `[TDD]` (US1, N2) port `navigationEvents` + service passthrough with `not_created` + unwired `port_not_wired`
- [x] T003 platform: `ChannelEventSource` typedef exported (wiring, compile-checked)

## Phase 2: Tracker

- [x] T004 `[TDD]` (US2, N3) ordered entries + lastUrl via handleEvent
- [x] T005 `[TDD]` (US2, N4) dedup window collapse (injected clock)
- [x] T006 `[TDD]` (US2, N5) mainFrameOnly drops sub-frame events
- [x] T007 `[TDD]` (US2, N6) hasCycle A→B→A true / A→B→C false; attach/detach stops recording; `clear(id)`/`dispose()` cleanup (N8)

## Phase 3: Adapters

- [x] T008 `[TDD]` (US3, N7a) android: decode+filter by id, malformed_response, channel_not_wired, register forwards eventSource
- [x] T009 `[TDD]` (US3, N7b) ios: same
- [x] T010 `[TDD]` (US3, N7c) macos: same

## Phase 4: Wiring (non-behavior)

- [x] T011 barrel exports + FEATURES.md 004 row notes guard deferral
- [x] T012 repo-wide analyze + tests green
