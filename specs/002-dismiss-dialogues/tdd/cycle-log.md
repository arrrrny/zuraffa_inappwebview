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

## Cycle 2 — review fixes (PR #1)

Not new behaviors: changes requested by the automated review of PR #1, so no
RED phase — the existing D1–D10 suite carried the contract.

- `dialogue_dismiss.dart`: the sweep now skips `documentElement`/`body`
  (a `body { position: fixed }` scroll-lock page would otherwise lose its
  entire content while still reporting `removed > 0`), and collects matches
  before removing so `getComputedStyle` is not interleaved with DOM
  mutations. Mirrored in spec.md FR-2 / US2 and plan.md.
- `dialogue_dismiss_test.dart`: D3/D4 no longer assert bare marker words
  (`contains('fixed')` and friends, which passed for any script that merely
  mentioned them). D3 now pins the shipped source against a
  whitespace-normalized golden copy, D4 pins the reset block; D5 keeps its
  frame-recursion negatives.
- `tasks.md`: T001–T005 behavior refs now match `tdd/test-list.md`
  (D1–D2 / D3–D5 / D6 / D7–D9 / D10).

`dart analyze` clean and `dart test` green in all five packages (51/51) after
the change. The golden pin was mutation-checked: dropping the `sticky` branch
fails D3; restoring it returns the suite to green.
