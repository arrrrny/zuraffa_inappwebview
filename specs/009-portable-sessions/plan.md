# Implementation Plan: Portable Sessions

**Branch**: `009-portable-sessions` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

`PortableSession` (JSON round-trip) + the `WebviewSessionStore` port (the
only persistence path) + `WebViewSessions` controller over
`WebviewService`: save snapshots cookies + canonical localStorage read;
load re-applies cookies + `setItem` writes; typed `session_not_found`.
No port widening.

## Project Structure

```text
app: lib/src/portable_sessions.dart     # NEW
     test/portable_sessions_test.dart   # MemorySessionStore + fake port
```

## Model

| Piece | Shape |
|---|---|
| PortableSession | name, origin, cookies[], localStorage{}, savedAt |
| store port | save/read/delete/list (sync read for not-found semantics) |
| save | getCookies(origin) + `JSON.stringify(window.localStorage)` eval |
| load | setCookie × n + `localStorage.setItem(k, v)` evals |

## MVP

US1+US2 (save/load); US3 (hygiene) same cycle.
