## 7.3.2 - 2026-10-31

Mono-version fleet alignment to 7.3.2: outbound send port lands in zuraffa_intents (shareText/shareFiles behind ShareIntentService); the whole family ships at one version.

## 0.1.0

### Changed — webview MVP (specs/001-zuraffa-mvp)

Replaces the scaffold's template semantics with the real webview API:

- `WebviewPort` — headless lifecycle, navigation, JS evaluation, global
  cookie store; pure Dart, injected transport.
- `WebviewService` — headless registry with typed lifecycle failures
  (`already_created`, `not_created`, `already_running`);
  `UnwiredWebviewPort` surfaces `port_not_wired` when no adapter is wired.
- `WebviewUri` (scheme-validated), `WebviewSettings`, `WebviewCookie`
  with pinned channel-arg round-trips.
- `LoadUrlUseCase` / `EvaluateJavascriptUseCase` / `SetCookieUseCase`.
- `WebviewModule` + `registerWebview` — auto-DI; pre-registered ports are
  never overridden.

# Changelog

## 0.1.0

- Initial scaffold as part of the `zuraffa_inappwebview` federated monorepo (EPIC #214).
