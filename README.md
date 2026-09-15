# zuraffa_inappwebview — monorepo

**Zuraffa-native in-app webview for Flutter.** Clean typed API, headless
webview, cookie store, JS evaluation — built as a federated plugin whose
platform adapters ride injected channels, so the whole core runs (and is
tested) with zero native code present.

This repo is the **successor to [`zikzak_inappwebview`](https://github.com/arrrrny/zikzak_inappwebview)**
with a **clean git history and a clean API**: nothing is inherited from the
flutter_inappwebview-derived surface. The API is shaped by what the zuraffa
ecosystem actually does with a webview — headless scraping, cookie/session
work, JS evaluation — and grows per need (see `specs/`, roadmap at the
bottom). Built test-first with the `zfa` TDD engine; see
[the migration guide](https://github.com/arrrrny/zuraffa/blob/master/docs/package_migration_guide.md).

## Packages

| Package | Description |
| --- | --- |
| [`packages/zuraffa_inappwebview`](packages/zuraffa_inappwebview/) | App-facing: `WebviewPort`, `WebviewService`, usecases, `WebviewModule` + auto-DI |
| [`packages/zuraffa_inappwebview_platform`](packages/zuraffa_inappwebview_platform/) | Shared channel-envelope core (typed errors, timeouts) over an injected channel |
| [`packages/zuraffa_inappwebview_android`](packages/zuraffa_inappwebview_android/) | Android adapter (typed taxonomy over the injected channel) |
| [`packages/zuraffa_inappwebview_ios`](packages/zuraffa_inappwebview_ios/) | iOS adapter (typed taxonomy over the injected channel) |
| [`packages/zuraffa_inappwebview_macos`](packages/zuraffa_inappwebview_macos/) | macOS adapter (typed taxonomy over the injected channel) |

## Quick start (consuming app)

```dart
import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';
// + the adapter for the running platform (android/ios/macos), which
//   pre-registers its WebviewPort.

final engine = ZuraffaEngine()
  ..registerPackage(WebviewModule());
await engine.bootstrap();

final service = engine.di.get<WebviewService>();
await service.createHeadless(id: 'scraper');
await service.runHeadless(id: 'scraper');
await service.loadUrl(id: 'scraper', url: WebviewUri('https://example.org'));
final html = await service.getHtml(id: 'scraper');
final result = await engine.di.get<EvaluateJavascriptUseCase>()(
  EvaluateJavascriptParams(webviewId: 'scraper', source: 'document.title'),
);

await service.disposeHeadless(id: 'scraper');
await engine.shutdown();
```

Without a wired adapter every call surfaces the typed
`WebviewException('port_not_wired')` instead of crashing at resolve time.

## API surface (MVP, v0.1.0)

- **Headless lifecycle** — `createHeadless` / `runHeadless` / `disposeHeadless` with a service-side registry and typed lifecycle failures (`already_created`, `not_created`, `already_running`).
- **Navigation + content** — `loadUrl` (headers), `currentUrl`, `getHtml`.
- **JS** — `evaluateJavascript`.
- **Cookies** — global shared store: `setCookie`, `getCookies`, `deleteCookie`, `deleteAllCookies`.
- **Types** — `WebviewUri` (http/https/about:blank only), `WebviewSettings` (typed subset: UA, JS, incognito, media gestures, zoom, load timeout), `WebviewCookie`.
- **Zuraffa surface** — `LoadUrlUseCase`, `EvaluateJavascriptUseCase`, `SetCookieUseCase`, `WebviewModule` (auto-DI, version-gated).

## Not (yet) in this API

The raw flutter_inappwebview firehose (render widgets, find-interaction,
web messaging, pull-to-refresh, browsers/custom tabs, capture recipes) is
deliberately out of the MVP. Needs drive additions — see `specs/` and the
upstream two-tier analysis in `zikzak_inappwebview/SPLIT_MAP.md`.

**Native status**: the Dart core + adapters are complete and tested; the
native (Kotlin/Swift) channel handlers are the next milestone — the
injected-channel contract they must implement is documented in each
adapter port's doc comment.

## Development

```bash
cd packages/<name> && dart pub get && dart test && dart analyze
```

All five packages: 41 tests green, analyze clean.

Publish from each package directory (`packages/<name>`); the federated
siblings depend on each other via hosted dependencies — see
[`PUBLISH.md`](PUBLISH.md) and `scripts/` for the publish pipeline.

See [`specs/`](specs/) for the spec-driven development records.

Repository: https://github.com/arrrrny/zuraffa_inappwebview
