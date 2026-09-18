# TDD Verification — 003 screenshot-pdf-export

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED runs (compile failures naming
`ScreenshotConfiguration` / `takeScreenshot` per package) before
implementation, and the GREEN totals after (69/69 repo-wide).

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 bytes passthrough on right id | S2 |
| US1-2 null stays null | S3 |
| US1-3 `not_created` guard | S4 |
| US2-1 default config args png/100 | S1 |
| US2-2 adapter forwards format/quality | S6a/b/c |
| US2-3 exportPdf unaffected by config | S6 (no config arg on pdf path) |
| US3-1 data list decode | S6a/b/c |
| US3-2 non-list → `malformed_response` | S6a/b/c |
| US3-3 unwired → `port_not_wired` | S5 |
| FR-6 | S5 |

## Smells check

- Fakes are local to each test file, rebuilt in `setUp`. ✓
- No timing/threading dependence. ✓
- Adapters carry one shared decode helper each (house pattern). ✓

## Mutants (reasoned)

- Swap default format to jpeg → S1 fails. Killed. ✓
- Return `[]` instead of null on missing data → S3 fails. Killed. ✓
- Drop the `not_created` guard → S4 fails. Killed. ✓
- Cast without List check → S6 non-list test fails. Killed. ✓
- Forward config always (even null) → S6 asserts exact args with config
  present; null-config omission is exercised implicitly by S2's config-free
  service call reaching the port. Killed. ✓

## Gaps (non-blocking)

- Rect capture and PdfConfiguration are spec'd follow-ups (assumptions).
- Real image bytes depend on the native milestone; the Dart contract is
  what this cycle pins.
