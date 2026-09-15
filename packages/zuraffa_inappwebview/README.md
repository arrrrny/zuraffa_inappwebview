# zuraffa_inappwebview

Zuraffa-native in-app webview for Flutter — clean typed API, headless webview, cookies, sessions.

Part of the [zuraffa_inappwebview](https://github.com/arrrrny/zuraffa_inappwebview) federated monorepo, built on the
[Zuraffa](https://pub.dev/packages/zuraffa) framework.

## Use

```dart
final service = InappwebviewService(port: myPlatformPort);
final module = await service.compile(id: 'demo', bytes: moduleBytes);
final results = await service.call(
    id: 'demo', export: 'run', args: [InappwebviewI32(1)]);
await service.unload(id: 'demo');
```

Wire the platform adapter for the running platform first — e.g.
`registerAndroidInappwebviewDependencies(getIt, channel: ...)` from
the adapter package — then resolve `InappwebviewService`, or call
`registerInappwebviewDependencies(getIt, port: ...)` directly. Without a
wired port every call surfaces the typed `port_not_wired` failure.

## Develop

```bash
dart pub get
dart test
```
