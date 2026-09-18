# Feature Inventory — zikzak_inappwebview → zuraffa_inappwebview

Complete inventory of the `zikzak_inappwebview` feature surface (from its
`specs/`, `SPLIT_MAP.md` two-tier analysis, and `zikzak_inappwebview_module`
ports/services), and how each item lands in this repo. The MVP (spec 001)
already delivered: headless lifecycle, loadUrl/currentUrl/getHtml,
evaluateJavascript, cookie store, typed settings, zuraffa module wiring.

## A. Value-add features → ported as specs (one branch + PR each)

| # | Feature | zikzak source | Zuraffa spec | Status |
|---|---|---|---|---|
| 1 | Dialogue dismissal (clean captures) | spec 002, `DialogueDismisser` | `002-dismiss-dialogues` | PR |
| 2 | Screenshot & PDF export | spec 001, `takeScreenshot`/`PdfConfiguration` | `003-screenshot-pdf-export` | PR |
| 3 | Navigation tracking (in-webview navigation guards defer to the attachable-widget spec, FEATURES tier C) | `NavigationTracker`, `UrlCycleEntry` | `004-navigation-tracking` | PR |
| 4 | Network capture / mission-grade intercept (+ distillation, budgets, redaction) | spec 010, `NetworkCaptureManager` → `CaptureSource` port | `005-network-capture` | PR |
| 5 | Webview pool — mission-scoped sessions, domain affinity, memory-pressure disposal | spec 007, `WebViewPool` service | `006-webview-pool` | PR |
| 6 | Session recipes — record/replay user flows | `RecipeRecorder`/`RecipeReplayer` → `RecipePort` | `007-session-recipes` | PR |
| 7 | VCR — deterministic record/replay cassettes | spec 008, `CassetteEngine` | `008-vcr-record-replay` | PR |
| 8 | Portable sessions (save/restore via zuraffa session port) | spec 014, `WebViewSessions` | `009-portable-sessions` | PR |
| 9 | Agent tool suite (`webview.*` MCP provider) | spec 009, generated tools | `010-webview-agent-tools` | PR |

## B. Internal rewrite specs (superseded — not ported)

zikzak specs 003–006 and 011–013 restructured the fork itself (umbrella
split, module extraction, wiring, generated tools plumbing, controller
domain split, lifecycle integration tests, dispose patterns). This repo's
clean federated architecture (spec 001) already embodies their target
state, so they have no port work of their own; their behavioral asks are
absorbed by the specs above where relevant.

## C. Upstream (flutter_inappwebview-derived) surface — deliberately deferred

Explicitly out of the MVP per the README; each lands behind its own spec
when a zuraffa need pulls it: render widgets (`InAppWebView` widget),
find-interaction, web messaging (channels/listeners), pull-to-refresh,
`InAppBrowser`/`ChromeSafariBrowser`, print jobs, proxy/tracing/service
worker controllers, HTTP auth credential database, web authentication
sessions, localhost server + asset loader, web storage managers,
`WebViewEnvironment` (Windows). The zikzak feature set this repo commits
to porting is tier A — the module-tier intelligence the zuraffa ecosystem
actually uses.
