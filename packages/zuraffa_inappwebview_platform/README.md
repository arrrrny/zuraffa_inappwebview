# zuraffa_inappwebview_platform

Shared channel-envelope core for the zuraffa_inappwebview platform adapters: decode,
typed-error plumbing, and timeout policy over an injected platform
channel. Adapters bring their own typed exception and taxonomy; the core
never invents one.

Part of the [zuraffa_inappwebview](https://github.com/arrrrny/zuraffa_inappwebview) federated monorepo.

## Develop

```bash
dart pub get
dart test
```
