# TDD Verification — 004 navigation-tracking

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED compile failures before implementation and
the three genuine mid-loop defects the tests caught (clock authority,
sync-controller error leak, teardown close-hang) — each fixed at the
behavior level, not by weakening assertions.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 codec completed/defaults | N1 |
| US1-2 codec failed + code + sub-frame | N1 |
| US1-3 not_created | N2 |
| US1-4 port_not_wired | N2 |
| US2-1 ordered entries + lastUrl | N3 |
| US2-2 dedup window collapse | N4 |
| US2-3 mainFrameOnly | N5 |
| US2-4 hasCycle + detach | N6 |
| US3-1 id-filtered decode | N7a/b/c |
| US3-2 malformed on non-map | N7a/b/c |
| US3-3 channel_not_wired | N7a/b/c |

## Mutants (reasoned)

- Invert mainFrameOnly default → N5 fails. Killed. ✓
- Remove dedup → N4 fails (1 vs 2 entries). Killed. ✓
- hasCycle as "any duplicate url" (consecutive included) → still true for
  A→A→A… but N6's linear case has no repeats; a consecutive-only change
  (A→A) is out of spec scope — noted as gap below. ✓/gap
- Drop the id filter in adapters → N7 sees the foreign event. Killed. ✓
- Return empty stream instead of Stream.error when unwired → N7
  channel_not_wired times out/fails. Killed. ✓

## Gaps (non-blocking)

- hasCycle is defined over the latest-url-reappears rule; a stricter
  cycle-shape classifier (zikzak's UrlCycleEntry semantics) can extend
  `UrlVisit` later without breaking the record format.
- Native event push is the native milestone; the Dart contract (method +
  payload shape) is pinned by N7.
