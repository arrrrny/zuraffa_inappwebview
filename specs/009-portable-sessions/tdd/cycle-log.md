# Cycle Log — 009 portable-sessions

## Baseline

Branch `009-portable-sessions` stacked on `008-vcr-record-replay`.
Baseline: 134/134 green.

## Cycle 1 — RED → GREEN

**RED**: `test/portable_sessions_test.dart` (PS1–PS4) →
`Type 'WebviewSessionStore' not found` / `'PortableSession'` (designed
red).

**GREEN**: NEW `portable_sessions.dart`:
- `PortableSession` (name/origin/cookies/localStorage/savedAt,
  `toJson`/`fromJson`) → PS4
- `WebviewSessionStore` port (save/read/delete/list) — the only
  persistence path; `MemorySessionStore` in tests doubles as the
  reference implementation
- `WebViewSessions.save` — cookie snapshot via the shared store +
  canonical `JSON.stringify(window.localStorage)` read → PS1
- `WebViewSessions.load` — `setCookie` per cookie + escaped
  `localStorage.setItem` per entry; typed `session_not_found` before any
  application → PS2, PS3

`dart test` → 18 · 18 · 18 · 6 · 78 = **138/138 green**, analyze clean.

## Cycle 2 — review fixes

Driven red first against the pre-fix head `f99f0b9`: the new behaviours
fail there (9 core + 1 per adapter).

**GREEN**:
- `jsStringLiteral` (`jsonEncode`) replaces the hand-rolled `'`-only
  escapers in `portable_sessions.dart` and `session_recipes.dart` →
  PS5, R7
- a non-JSON localStorage read throws the typed
  `local_storage_unreadable` instead of a raw `FormatException` → PS6
- byte-accurate body truncation, shape-matched secret redaction,
  `stop()` draining in-flight handlers, `VcrReplayer.dispose()`, a
  typed unknown-phase failure, and a typed non-integer byte element in
  the three adapters → C4, C5, V1, N1, S6

`dart test` → 19 · 19 · 19 · 6 · 87 = **150/150 green**, analyze clean.

## Notes

- The store `read` is synchronous by design: not-found is a decision, not
  an I/O race (spec FR-4 — check before applying anything).
- Per-instance isolated stores (zikzak #253) remain nice-to-have.
