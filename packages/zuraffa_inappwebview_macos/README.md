# zuraffa_inappwebview_macos

macOS adapter for the [zuraffa_inappwebview](https://github.com/arrrrny/zuraffa_inappwebview) federated monorepo:
the Inappwebview port over an injected platform channel, with the shared
envelope machinery from `zuraffa_inappwebview_platform` and a typed failure taxonomy
as pure data.

The channel transport is injected — no Flutter plugin boilerplate, no
native code in this repo. The consuming app (or a native shell) supplies
the `ChannelInvoke` seam:

```dart
import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview_macos/zuraffa_inappwebview_macos.dart';

void register() {
  registerMacosInappwebviewDependencies(
    GetIt.instance,
    channel: MacosInappwebviewChannel(
      invoke: (method, args) => nativeBridge.call(method, args),
    ),
  );
}
```

Without an injected channel every call surfaces the typed
`channel_not_wired` failure instead of hanging.

## Develop

```bash
dart pub get
dart test
```
