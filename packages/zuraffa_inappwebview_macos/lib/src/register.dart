import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'macos_inappwebview_channel.dart';
import 'macos_inappwebview_exception.dart';
import 'macos_inappwebview_port.dart';

/// Registers the macOS adapter on [GetIt.instance]: the
/// [InappwebviewPort] over an injected channel. An injected [timeout] is
/// applied to the wired channel. Without a channel every call surfaces
/// the typed `channel_not_wired` failure.
void registerMacosInappwebviewDependencies(
  GetIt getIt, {
  MacosInappwebviewChannel? channel,
  Duration? timeout,
}) {
  final wired = (channel == null)
      ? MacosInappwebviewChannel(
          invoke: (_, __) => throw const MacosInappwebviewException(
            'channel_not_wired',
            'No macOS channel was injected — pass one to '
            'registerMacosInappwebviewDependencies.',
            recoverable: false,
          ),
        )
      : (timeout == null)
          ? channel
          : MacosInappwebviewChannel(
              invoke: channel.invoke,
              timeout: timeout,
            );
  getIt.registerLazySingleton<InappwebviewPort>(
    () => MacosInappwebviewPort(channel: wired),
  );
}
