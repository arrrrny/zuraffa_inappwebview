# TDD Verification — 006 webview-pool

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED run (`Method not found: 'WebviewPool'`)
before implementation and the GREEN totals (116/116 repo-wide).

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 fresh acquire creates+runs, counts | P1 |
| US1-2 same session same id | P1 |
| US1-3 release → warm idle | P2 |
| US2-1 same eTLD+1 reuse | P3 |
| US2-2 cross-domain isolation | P4 |
| US3-1 maxLive evicts idlest | P5a (one idle), P5a-two-idles (older of two) |
| US3-2 pool_exhausted | P5b |
| US3-3 TTL sweep | P6 |
| FR-6 domain cap | P5c (evicts the domain's idle), P5d (all active) |
| US4-1 disposeAll zero-state | P7 |

## Mutants (reasoned)

- Remove affinity match → P3 fails (creates 2). Killed. ✓
- Evict newest instead of idlest → P5a (two idles of different ages)
  disposes the wrong id; the identity assertion breaks. Killed. ✓
- Throw pool_exhausted when idles exist → P5a fails. Killed. ✓
- Skip the TTL sweep → P6 fails (same id reused). Killed. ✓
- release() disposes instead of warming → P2 fails. Killed. ✓

## Gaps (non-blocking)

- Memory-pressure lifecycle listeners defer to the app shell (spec
  Assumptions).
- `registrableDomain` still approximates eTLD+1 as the last two labels
  (co.uk and friends); IP literals skip the reduction entirely.

## Review-fix round (PR #5 findings, 2026-09-18)

Each failure-path defect the review reproduced at `4db1117` was fixed with
the regression test that pins it:

| Finding | Fix | Pinned by |
|---|---|---|
| `acquire` not re-entrancy safe | one in-flight future per session | P1b |
| failed `runHeadless` orphans the webview | dispose the created id, then rethrow | P1c |
| `maxPerDomain` branch unreachable | cap decided before the affinity scan | P5c, P5d |
| `_dispose` deregisters too early | deregister after `disposeHeadless` succeeds | P7b |
| `disposeAll` aborts on first failure | attempt all, then `pool_teardown_incomplete` | P7c |
| `registrableDomain` collides hosts | normalize scheme/port/path/case, keep IP literals | P3b, P3c, P3d |
