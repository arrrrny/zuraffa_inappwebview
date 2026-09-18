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
| US3-1 maxLive evicts idlest | P5a |
| US3-2 pool_exhausted | P5b |
| US3-3 TTL sweep | P6 |
| US4-1 disposeAll zero-state | P7 |

## Mutants (reasoned)

- Remove affinity match → P3 fails (creates 2). Killed. ✓
- Evict newest instead of idlest → P5a dispose count/identity breaks. Killed. ✓
- Throw pool_exhausted when idles exist → P5a fails. Killed. ✓
- Skip the TTL sweep → P6 fails (same id reused). Killed. ✓
- release() disposes instead of warming → P2 fails. Killed. ✓

## Gaps (non-blocking)

- `maxPerDomain` (FR-6) is pinned by P5c/P5d. *(Post-review fix: the
  dedicated per-domain eviction limb was unreachable — a same-domain idle
  is always reused by the affinity loop first — so it was removed in
  favour of the typed `pool_exhausted` fallback, and FR-6 was reworded to
  match.)*
- Memory-pressure lifecycle listeners defer to the app shell (spec
  Assumptions).
