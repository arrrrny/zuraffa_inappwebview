import 'package:zuraffa_inappwebview_platform/zuraffa_inappwebview_platform.dart';

import 'ios_inappwebview_exception.dart';

/// The iOS channel: the shared
/// [PlatformInappwebviewEnvelope] machinery with the iOS
/// taxonomy as a pure data set.
class IosInappwebviewChannel {
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

  const IosInappwebviewChannel({
    required this.invoke,
    this.timeout = const Duration(seconds: 30),
  });

  Future<Map<String, Object?>?> call(
    String method,
    Map<String, Object?> args,
  ) =>
      PlatformInappwebviewEnvelope(
        invoke: invoke,
        timeout: timeout,
        onTyped: IosInappwebviewException.new,
        mapNativeError: _mapNativeError,
        isTypedError: (error) => error is IosInappwebviewException,
      ).call(method, args);

  static Exception _mapNativeError(String code, String message) =>
      IosInappwebviewException(
        code,
        message,
        recoverable: recoverableCodes.contains(code),
      );
}
