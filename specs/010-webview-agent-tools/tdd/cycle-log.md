# Cycle Log — 010 webview-agent-tools

## Baseline

Branch `010-webview-agent-tools` stacked on `009-portable-sessions`.
Baseline: 138/138 green.

## Cycle 1 — RED → GREEN

**RED**: `test/webview_agent_tools_test.dart` (A1–A8) →
`Method not found: 'WebviewAgentTools'` (designed red).

**GREEN**: NEW `webview_agent_tools.dart` — `WebviewAgentTools` builds six
zuraffa-core `McpTool`s (the public runtime tier from
`package:zuraffa/zuraffa.dart`):
- `browse` (validated `WebviewUri`, pool acquire with host hint, load,
  webviewId) + `execute_js` (same-session acquire → same instance) →
  A2, A3
- `_guard` wrapper: untrusted-arg validation and `WebviewException`
  degradation to `isError` results — no tool ever throws → A4
- `read_cookies` (cookie maps), `screenshot` (`McpToolResult.artifact` —
  ref + byteLength, never the body), `dismiss_dialogues` (the 002
  canonical script), `release_session` (pool release) → A5–A8

**Mid-loop fixes (test-side, no assertion weakened):**
1. `McpToolResult.artifact` takes the ref positionally (named `text`) —
   implementation corrected to the hosted 6.3.0 signature.
2. The A3 create-count assertion counted a leftover setUp seed create —
   seed removed; A6 read `artifactRef` from `data` instead of the result
   field — fixed to `result.artifactRef`.

`dart test` → 18 · 18 · 18 · 6 · 87 = **147/147 green**, analyze clean.

## Notes

- Search-engine degradation heuristics and mission-cancellation salvage
  (zikzak spec 009) ride the same seams later (spec Assumptions).
