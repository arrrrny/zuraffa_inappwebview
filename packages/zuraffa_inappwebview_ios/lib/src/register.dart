import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'ios_inappwebview_channel.dart';
import 'ios_inappwebview_exception.dart';
import 'ios_inappwebview_port.dart';

/// Registers the iOS adapter on [GetIt.instance]: the
/// [InappwebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerIosInappwebviewDependencies(
  GetIt getIt, {
  IosInappwebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? IosInappwebviewChannel(
          invoke: (_, __) => throw const IosInappwebviewException(
            'channel_not_wired',
            'No iOS channel was injected — pass one to '
            'registerIosInappwebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : IosInappwebviewChannel(
              invoke: channel.invoke,
              timeout: timeout,
            );
  getIt.registerLazySingleton<InappwebviewPort>(
    () => IosInappwebviewPort(channel: wired),
  );
}
