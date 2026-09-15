import 'package:zuraffa_inappwebview_platform/zuraffa_inappwebview_platform.dart';

import 'macos_webview_exception.dart';

/// The macOS channel: the shared
/// [PlatformWebviewEnvelope] machinery with the macOS
/// taxonomy as a pure data set.
class MacosWebviewChannel {
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

  const MacosWebviewChannel({
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
        onTyped: MacosWebviewException.new,
        mapNativeError: _mapNativeError,
        isTypedError: (error) => error is MacosWebviewException,
      ).call(method, args);

  static Exception _mapNativeError(String code, String message) =>
      MacosWebviewException(
        code,
        message,
        recoverable: recoverableCodes.contains(code),
      );
}
