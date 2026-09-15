/// The typed native failure on macOS.
class MacosWebviewException implements Exception {
  final String code;
  final String message;
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
