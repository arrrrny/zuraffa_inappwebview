# Implementation Plan: Webview Pool

**Branch**: `006-webview-pool` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

Pure-Dart `WebviewPool` over `WebviewService`: session-keyed acquire with
pool-generated ids, warm-idle release, eTLD+1 domain affinity, `maxLive` +
`maxPerDomain` caps with LRU-idle eviction, `pool_exhausted` typed
failure, lazy `idleTtl` sweep (injectable clock), `disposeAll`.

## Project Structure

```text
app: lib/src/webview_pool.dart     # NEW (no port widening — rides the service)
     test/webview_pool_test.dart   # counting fake port
```

## Model

| Piece | Shape |
|---|---|
| `_PooledInstance` | webviewId, domain (registrable), session? (null = idle), idleSince |
| acquire | active reuse → warm same-domain reuse → evict to fit caps → create+run |
| registrableDomain | last two host labels (`shop.x.dev` → `x.dev`) |

## MVP

US1+US2 (sessions + affinity), then US3/US4 (caps, TTL, disposeAll).

## Risks

- None to the port surface; no adapter or fake churn this cycle.
