import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'ios_webview_channel.dart';
import 'ios_webview_exception.dart';
import 'ios_webview_port.dart';

/// Registers the iOS adapter on [GetIt.instance]: the
/// [WebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerIosWebviewDependencies(
  GetIt getIt, {
  IosWebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? IosWebviewChannel(
          invoke: (_, __) => throw const IosWebviewException(
            'channel_not_wired',
            'No iOS channel was injected — pass one to '
            'registerIosWebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : IosWebviewChannel(
              invoke: channel.invoke,
              eventSource: channel.eventSource,
              timeout: timeout,
            );
  getIt.registerLazySingleton<WebviewPort>(
    () => IosWebviewPort(channel: wired),
  );
}
