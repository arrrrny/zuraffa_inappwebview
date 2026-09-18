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
| FR-6 maxPerDomain | P8a–P8d |

## Mutants (reasoned)

- Remove affinity match → P3 fails (creates 2). Killed. ✓
- Evict newest instead of idlest → P5a dispose count/identity breaks. Killed. ✓
- Throw pool_exhausted when idles exist → P5a fails. Killed. ✓
- Skip the TTL sweep → P6 fails (same id reused). Killed. ✓
- release() disposes instead of warming → P2 fails. Killed. ✓

## Gaps (non-blocking)

- maxPerDomain's dedicated path (FR-6) is pinned by P8a–P8d: idle
  same-domain reuse, cap overflow → `pool_exhausted`, release frees a
  slot, and another domain is unaffected.
- Memory-pressure lifecycle listeners defer to the app shell (spec
  Assumptions).
