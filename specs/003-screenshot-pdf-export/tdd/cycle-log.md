# Cycle Log — 003 screenshot-pdf-export

## Baseline

Branch `003-screenshot-pdf-export` stacked on `002-dismiss-dialogues`.
Baseline: 5 packages, 51 tests green, analyze clean.

## Cycle 1 — RED → GREEN

**RED** (test-first): `test/screenshot_pdf_test.dart` (S1–S5) + a
`capture ops (spec 003)` group appended to each adapter test
(android/ios/macos, S6a–S6c) written before implementation.
- app: `dart test test/screenshot_pdf_test.dart` → compile failure
  (`Type 'ScreenshotConfiguration' not found`) — designed red.
- adapters: `Undefined name 'ScreenshotFormat'` / `The method
  'takeScreenshot' isn't defined for the type '<Platform>WebviewPort'` —
  designed red in all three.

**GREEN** (smallest change):
- `webview_types.dart`: `ScreenshotFormat` (png/jpeg) +
  `ScreenshotConfiguration` (quality 100 default) with `toChannelArgs` → S1.
- `webview_port.dart`: abstract `takeScreenshot`/`exportPdf`.
- `webview_service.dart`: facade ops with `_requireCreated` guard + null
  passthrough; `UnwiredWebviewPort` raises `port_not_wired` → S2–S5.
- adapters ×3: `takeScreenshot` (id + spread config args) / `exportPdf`
  (id), `_decodeBytes` (null passthrough, non-List → typed
  `malformed_response`) → S6a–S6c.
- Updated the two pre-existing test fakes to implement the widened port
  (mechanical, no behavior change).

`dart test` → android 10 · ios 10 · macos 10 · platform 6 · app 33 =
**69/69 green**; `dart analyze` clean everywhere.

## Refactor while green

None — the shared `_decodeBytes` helper per adapter mirrors the house
`getCookies` decode pattern; no duplication beyond the federated triplet.


## Review follow-up (PR #3 review findings)

Applied after the automated review of PR #3. The added assertion was written
alongside the fix, not driven red-first in the loop above.

- **`quality` is clamped to 1–100.** The doc claimed the range but nothing
  enforced it (`quality: 500` rode the envelope verbatim). The const
  constructor now clamps with the same ternary idiom
  `DialogueDismissPolicy.attempts` uses, and S1 pins `500 → 100` and
  `0 / -3 → 1`.
- Spec/test-list wording aligned (FR-3, S1 row, counts corrected).

Verified after the change: app package 47/47, repo-wide 98/98 green and
`dart analyze` clean in all five packages.
