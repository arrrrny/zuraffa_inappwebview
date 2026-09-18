# Implementation Plan: WebView Agent Tools

**Branch**: `010-webview-agent-tools` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

`WebviewAgentTools(service, pool).buildTools()` → six zuraffa-core
`McpTool`s (`browse`, `execute_js`, `read_cookies`, `screenshot`,
`dismiss_dialogues`, `release_session`). Session continuity via the pool;
defensive validation; typed failures degrade to `isError` results;
screenshots travel by artifactRef.

## Project Structure

```text
app: lib/src/webview_agent_tools.dart    # NEW (imports zuraffa's public McpTool)
     test/webview_agent_tools_test.dart  # fake port + real pool
```

## Model

| Tool | Args | Semantics |
|---|---|---|
| browse | session, url | validate → pool.acquire(session, host) → loadUrl → webviewId |
| execute_js | session, source | pool.acquire(session) → evaluate → result + webviewId |
| read_cookies | url | shared cookie store → cookie maps |
| screenshot | session | acquire → takeScreenshot → artifactRef + byteLength (no body) |
| dismiss_dialogues | session | acquire → 002 canonical script |
| release_session | session | pool.release |

Every `call` is guarded: untrusted args → isError; `WebviewException` →
isError with the typed code.

## MVP

US1+US2 (suite + browse continuity), US3 (read/capture/clean/release) —
one cycle.

## Risks

- Depends on zuraffa core's public `McpTool`/`McpToolResult` (hosted 6.3.0
  exports them from `src/core/module/mcp_tool.dart` via the main barrel).
