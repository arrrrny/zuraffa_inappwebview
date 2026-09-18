# TDD Verification — 008 vcr-record-replay

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED run (VcrRecorder/Cassette/loadHtml not
found) and GREEN totals (134/134 repo-wide).

Correction (2026-09-18, review follow-up): the cycle log's mid-loop note
that the `ingestNavigation` race was "fixed test-side" is not what the
shipped code did — the test-side `Future.delayed(Duration.zero)` hid the
race while production kept misattributing and dropping captures. The race
is now fixed in `VcrRecorder` (synchronous snapshot + single-flight freeze)
and pinned by a regression test that gates `getHtml` on a `Completer`.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 ordered entries + snapshots | V1 |
| US1-2 JSON round-trip (incl. capture `at`) | V2 |
| US1-3 captures attach to their navigation | V1 |
| US1-4 formatVersion 1 (and an unsupported version is refused) | V1/V2 |
| US2-1 exact match serves via loadHtml | V3 |
| US2-2 synthesized captures in order (+ `dispose`) | V6 |
| US2-3 path-prefix fallback on a segment boundary | V4 |
| US3-1 strict vcr_unmatched | V5 |
| US3-2 soft mode | V5 |
| US4-1 loadHtml adapter args | V7a/b/c |

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
- Cookie restore is *not* implemented and is documented as a limitation on
  `VcrReplayer`: `CassetteEntry.cookies` is recorded and JSON round-tripped,
  but replay serves content through the platform's shared cookie store and
  issues no `setCookie` restore, so a replay is deterministic in served
  content, not in cookie state.
