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

## Cycle 2 — review fix (PR #9 review)

- The store `read` became **async** (`Future<PortableSession?> read`): a
  synchronous read forces every real backend (file, keychain, secure
  storage, remote) to block the isolate or keep the whole store resident.
  Not-found is still checked before anything is applied (FR-4).
- `localStorage` keys/values are now spliced into JS with `jsonEncode`
  instead of a `'`-only escaper: a value containing a newline (pasted
  text, pretty-printed JSON — routine in `localStorage`) used to produce a
  `SyntaxError` mid-restore, after cookies and earlier keys were applied.
- `PortableSession.fromJson` now fails typed (`malformed_response`) on a
  foreign payload instead of throwing a raw `TypeError`.

## Notes

- Per-instance isolated stores (zikzak #253) remain nice-to-have.
