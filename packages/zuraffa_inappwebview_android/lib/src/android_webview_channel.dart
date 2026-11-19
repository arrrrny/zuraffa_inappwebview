import 'package:zuraffa_inappwebview_platform/zuraffa_inappwebview_platform.dart';

import 'android_webview_exception.dart';

/// The Android channel: the shared
/// [PlatformWebviewEnvelope] machinery with the Android
/// taxonomy as a pure data set.
class AndroidWebviewChannel {
  /// Native codes that map recoverable; everything else (including
  /// unknown codes) is non-recoverable, preserved verbatim.
  static const Set<String> recoverableCodes = {
    'user_cancelled',
    'api_unavailable',
    'not_supported',
    'timeout',
  };

  final ChannelInvoke invoke;
  final ChannelEventSource? eventSource;
  final Duration timeout;

  const AndroidWebviewChannel({
    required this.invoke,
    this.eventSource,
    this.timeout = const Duration(seconds: 30),
  });

  Future<Map<String, Object?>?> call(
    String method,
    Map<String, Object?> args,
  ) =>
      PlatformWebviewEnvelope(
        invoke: invoke,
        timeout: timeout,
        onTyped: AndroidWebviewException.new,
        mapNativeError: _mapNativeError,
        isTypedError: (error) => error is AndroidWebviewException,
      ).call(method, args);

  static Exception _mapNativeError(String code, String message) =>
      AndroidWebviewException(
        code,
        message,
        recoverable: recoverableCodes.contains(code),
      );
}
