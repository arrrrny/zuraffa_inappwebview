import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// The typed native failure on macOS.
///
/// Implements [WebviewException] so the core layer — which matches on that
/// type — surfaces the native code instead of flattening every platform
/// failure to `webview.tool_failed`.
class MacosWebviewException implements WebviewException {
  @override
  final String code;
  @override
  final String message;
  @override
  final bool recoverable;

  const MacosWebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'MacosWebviewException($code, recoverable: $recoverable): $message';
}
