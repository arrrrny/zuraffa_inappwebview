# Cycle Log — 006 webview-pool

## Baseline

Branch `006-webview-pool` stacked on `005-network-capture`.
Baseline: 108/108 green.

## Cycle 1 — RED → GREEN

**RED**: `test/webview_pool_test.dart` (P1–P7, counting fake port) →
`Error: Method not found: 'WebviewPool'` (designed red).

**GREEN**: NEW `webview_pool.dart` — `WebviewPool` over `WebviewService`
(`acquire`/`release`/`disposeAll`/`liveCount`/`sessions`):
- session-keyed identity, pool-generated ids (`pool-<n>`), create+run on
  first acquire → P1
- release keeps warm idle → P2
- `registrableDomain` (last two labels) affinity across idles → P3, P4
- `maxLive` eviction of the idlest instance; `pool_exhausted` typed
  failure when all live → P5a, P5b
- lazy `idleTtl` sweep on acquire (clock injectable) → P6
- `disposeAll` → P7

No port widening — rides the existing service surface, so no adapter or
fake churn.

`dart test` → app **59** (+8), repo 17·17·17·6·59 = **116/116 green**,
analyze clean.

## Refactor while green

None needed.
