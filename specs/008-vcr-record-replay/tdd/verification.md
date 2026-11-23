# TDD Verification — 008 vcr-record-replay

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED run (VcrRecorder/Cassette/loadHtml not
found) and GREEN totals (134/134 repo-wide). One mid-loop race was caught
by the tests (unawaited async ingestNavigation) and fixed test-side
without weakening the recorded behavior.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 ordered entries + snapshots | V1 |
| US1-2 JSON round-trip | V2 |
| US1-3 captures attach to their navigation | V1 |
| US1-4 formatVersion 1 | V1/V2 |
| US2-1 exact match serves via loadHtml | V3 |
| US2-2 synthesized captures in order | V6 |
| US2-3 path-prefix fallback | V4 |
| US3-1 strict vcr_unmatched | V5 |
| US3-2 soft mode | V5 |
| US4-1 loadHtml adapter args | V7 |

## Mutants (reasoned)

- Drop the redactor in ingestCapture → V2 fails. Killed. ✓
- Serve first entry regardless of match → V4 fails. Killed. ✓
- Soft-default (strict=false) → V5 strict test fails. Killed. ✓
- Skip synthesized captures → V6 fails. Killed. ✓
- loadHtml without baseUrl → V3 fails. Killed. ✓

## Gaps (non-blocking)

- Request-normalization matching (method+body keyed) defers behind
  path-prefix matching; the cassette format is versioned for it.
- Gzip container is a serialization detail behind toJson/fromJson.
