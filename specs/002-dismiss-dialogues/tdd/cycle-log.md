# Cycle Log — 002 dismiss-dialogues

## Baseline

Branch `002-dismiss-dialogues` cut from `master` @ 18b5d73. Repo baseline:
5 packages, 41 tests green, analyze clean (tdd-profile.md).

## Cycle 1 — RED → GREEN (single drive, 10 behaviors)

**RED** (test-first): `test/dialogue_dismiss_test.dart` written covering
D1–D10 before any implementation existed.
`dart test test/dialogue_dismiss_test.dart` → compile failure:
`Error: The method 'dismissDialogues' isn't defined for the class
'WebviewService'` (+ missing `DialogueDismissScript` / `DialogueDismissPolicy`
/ setting) — designed red, the behaviors fail for the right reason (the API
does not exist yet).

**GREEN** (smallest change):
- `webview_types.dart`: `WebviewSettings.dismissDialogues` (default `false`)
  serialized as `dismissDialogues` in `toChannelArgs()` → D1, D2.
- NEW `dialogue_dismiss.dart`: `DialogueDismissScript.source` (computed
  fixed/sticky removal + `documentElement`/`body` overflow/margin reset,
  try/catch guarded, top-level document only) → D3–D5;
  `DialogueDismissPolicy` (attempts clamped ≥ 1, zero default delay) → D6.
- `webview_service.dart`: `dismissDialogues({id, policy})` — `_requireCreated`
  guard → D8; per-attempt evaluation with inter-attempt delay → D7, D10;
  `on Exception` swallow → D9.
- Barrel export of the two new types (T006).

`dart test` → app package `+27: All tests passed!` (17 baseline + 10 new);
repo-wide `for p in packages/*/; dart test` → 51/51 green, `dart analyze`
clean everywhere (T007).

## Refactor while green

None needed — the implementation is three small pieces behind the existing
facade; no duplication introduced.
