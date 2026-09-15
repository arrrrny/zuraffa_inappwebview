# zuraffa_inappwebview — monorepo

Zuraffa-native in-app webview for Flutter — clean typed API, headless webview, cookies, sessions.

Built on the [Zuraffa](https://pub.dev/packages/zuraffa) framework as part
of the zuraffa-native package family (EPIC #214).

## Packages

| Package | Description |
| --- | --- |
| [`packages/zuraffa_inappwebview`](packages/zuraffa_inappwebview/) | App-facing package: `InappwebviewPort`, `InappwebviewService`, typed failures + DI registration |
| [`packages/zuraffa_inappwebview_platform`](packages/zuraffa_inappwebview_platform/) | Shared channel-envelope core over an injected platform channel |
| [`packages/zuraffa_inappwebview_android`](packages/zuraffa_inappwebview_android/) | Android adapter (typed taxonomy over the injected channel) |
| [`packages/zuraffa_inappwebview_ios`](packages/zuraffa_inappwebview_ios/) | iOS adapter (typed taxonomy over the injected channel) |
| [`packages/zuraffa_inappwebview_macos`](packages/zuraffa_inappwebview_macos/) | macOS adapter (typed taxonomy over the injected channel) |

Publish from each package directory (`packages/<name>`); the federated
siblings depend on each other via hosted dependencies — see
[`PUBLISH.md`](PUBLISH.md) and `scripts/` for the publish pipeline.

See [`specs/`](specs/) for the spec-driven development records.

Repository: https://github.com/arrrrny/zuraffa_inappwebview
