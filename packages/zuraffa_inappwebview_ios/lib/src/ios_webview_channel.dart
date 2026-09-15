import 'package:zuraffa_inappwebview_platform/zuraffa_inappwebview_platform.dart';

import 'ios_webview_exception.dart';

/// The iOS channel: the shared
/// [PlatformWebviewEnvelope] machinery with the iOS
/// taxonomy as a pure data set.
class IosWebviewChannel {
  /// Native codes that map recoverable; everything else (including
  /// unknown codes) is non-recoverable, preserved verbatim.
  static const Set<String> recoverableCodes = {
    'user_cancelled',
    'api_unavailable',
    'not_supported',
    'timeout',
  };

  final ChannelInvoke invoke;
  final Duration timeout;

  const IosWebviewChannel({
    required this.invoke,
    this.timeout = const Duration(seconds: 30),
  });

  Future<Map<String, Object?>?> call(
    String method,
    Map<String, Object?> args,
  ) =>
      PlatformWebviewEnvelope(
        invoke: invoke,
        timeout: timeout,
        onTyped: IosWebviewException.new,
        mapNativeError: _mapNativeError,
        isTypedError: (error) => error is IosWebviewException,
      ).call(method, args);

  static Exception _mapNativeError(String code, String message) =>
      IosWebviewException(
        code,
        message,
        recoverable: recoverableCodes.contains(code),
      );
}
