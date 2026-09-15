import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'android_inappwebview_channel.dart';
import 'android_inappwebview_exception.dart';
import 'android_inappwebview_port.dart';

/// Registers the Android adapter on [GetIt.instance]: the
/// [InappwebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerAndroidInappwebviewDependencies(
  GetIt getIt, {
  AndroidInappwebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? AndroidInappwebviewChannel(
          invoke: (_, __) => throw const AndroidInappwebviewException(
            'channel_not_wired',
            'No Android channel was injected — pass one to '
            'registerAndroidInappwebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : AndroidInappwebviewChannel(
              invoke: channel.invoke,
              timeout: timeout,
            );
  getIt.registerLazySingleton<InappwebviewPort>(
    () => AndroidInappwebviewPort(channel: wired),
  );
}
