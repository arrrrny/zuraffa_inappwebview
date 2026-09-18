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

## Notes

- The store `read` is synchronous by design: not-found is a decision, not
  an I/O race (spec FR-4 — check before applying anything).
- Per-instance isolated stores (zikzak #253) remain nice-to-have.
