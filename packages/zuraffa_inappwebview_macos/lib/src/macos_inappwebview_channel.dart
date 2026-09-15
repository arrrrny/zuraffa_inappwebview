import 'package:zuraffa_inappwebview_platform/zuraffa_inappwebview_platform.dart';

import 'macos_inappwebview_exception.dart';

/// The macOS channel: the shared
/// [PlatformInappwebviewEnvelope] machinery with the macOS
/// taxonomy as a pure data set.
class MacosInappwebviewChannel {
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

  const MacosInappwebviewChannel({
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
        onTyped: MacosInappwebviewException.new,
        mapNativeError: _mapNativeError,
        isTypedError: (error) => error is MacosInappwebviewException,
      ).call(method, args);

  static Exception _mapNativeError(String code, String message) =>
      MacosInappwebviewException(
        code,
        message,
        recoverable: recoverableCodes.contains(code),
      );
}
