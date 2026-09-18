import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'macos_webview_channel.dart';
import 'macos_webview_exception.dart';
import 'macos_webview_port.dart';

/// Registers the macOS adapter on [GetIt.instance]: the
/// [WebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerMacosWebviewDependencies(
  GetIt getIt, {
  MacosWebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? MacosWebviewChannel(
          invoke: (_, __) => throw const MacosWebviewException(
            'channel_not_wired',
            'No macOS channel was injected — pass one to '
            'registerMacosWebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : MacosWebviewChannel(
              invoke: channel.invoke,
              eventSource: channel.eventSource,
              timeout: timeout,
            );
  getIt.registerLazySingleton<WebviewPort>(
    () => MacosWebviewPort(channel: wired),
  );
}
