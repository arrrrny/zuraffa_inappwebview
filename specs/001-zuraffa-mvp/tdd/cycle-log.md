# Cycle Log — zuraffa_inappwebview MVP

## Commit 1 — federated scaffold (zfa package create-plugin)

The generated scaffold passes analysis and tests with zero edits (11 tests
in the app-facing package). Its template semantics (a wasm-style
compile/invoke port) are placeholders by design and are replaced in commit 2.

## Commit 2 — webview MVP semantics (RED → GREEN)

RED: the scaffold's value/service tests reference the wasm surface; the
new webview test list (W1–W17, WA1–WA6) fails to compile against the
template port — designed red.

GREEN:
- `WebviewPort` (pure Dart ops), `WebviewService` (headless registry +
  typed lifecycle failures), `UnwiredWebviewPort` (public `port_not_wired`
  placeholder — made public because the module must construct it).
- `WebviewUri` / `WebviewSettings` / `WebviewCookie` with pinned channel args.
- `LoadUrlUseCase` / `EvaluateJavascriptUseCase` / `SetCookieUseCase`.
- `WebviewModule` + `registerWebview` (never overrides pre-registered ports).
- Platform envelope renamed; the three adapters implement every webview op
  over the envelope with the payload contract documented in the port doc
  comment; adapter tests pin method/args per operation and typed native
  error surfacing.

```
app 17/17 · platform 6/6 · android 6/6 · ios 6/6 · macos 6/6 — 41/41
```

All five packages: `dart analyze` clean.
