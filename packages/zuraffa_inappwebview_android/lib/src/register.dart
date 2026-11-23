import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'android_webview_channel.dart';
import 'android_webview_exception.dart';
import 'android_webview_port.dart';

/// Registers the Android adapter on [GetIt.instance]: the
/// [WebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerAndroidWebviewDependencies(
  GetIt getIt, {
  AndroidWebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? AndroidWebviewChannel(
          invoke: (_, __) => throw const AndroidWebviewException(
            'channel_not_wired',
            'No Android channel was injected — pass one to '
            'registerAndroidWebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : AndroidWebviewChannel(
              invoke: channel.invoke,
              eventSource: channel.eventSource,
              timeout: timeout,
            );
  getIt.registerLazySingleton<WebviewPort>(
    () => AndroidWebviewPort(channel: wired),
  );
}
