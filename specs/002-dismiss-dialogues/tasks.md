# Tasks: Dismiss Dialogues — Clean-Capture Overlay Removal

**Input**: Design documents from `/specs/002-dismiss-dialogues/`

**Tests**: mandatory — every behavior task (marked `[TDD]`) is driven
red → green via `tdd/test-list.md` before its implementation is counted done.

## Phase 1: Foundational

- [x] T001 `[TDD]` (US1, D1–D2) `WebviewSettings.dismissDialogues` — default false, serialized in `toChannelArgs()` — `packages/zuraffa_inappwebview/lib/src/webview_types.dart`
- [x] T002 `[TDD]` (US2, D3–D5) `DialogueDismissScript.source` — canonical script removes fixed/sticky, resets overflow/margin, top-level only — NEW `packages/zuraffa_inappwebview/lib/src/dialogue_dismiss.dart`
- [x] T003 `[TDD]` (US3, D6) `DialogueDismissPolicy` — attempts min 1 default 1, delay default zero — same file

## Phase 2: Service facade

- [x] T004 `[TDD]` (US2, D7–D9) `WebviewService.dismissDialogues({id, policy})` evaluates the script once by default; `not_created` typed failure for unknown ids; port errors swallowed — `packages/zuraffa_inappwebview/lib/src/webview_service.dart`
- [x] T005 `[TDD]` (US3, D10) retry loop: `attempts` evaluations with `delay` between — same op

## Phase 3: Wiring (non-behavior)

- [x] T006 export `dialogue_dismiss.dart` from the package barrel `lib/zuraffa_inappwebview.dart`
- [x] T007 `dart analyze` + `dart test` green across all five packages
