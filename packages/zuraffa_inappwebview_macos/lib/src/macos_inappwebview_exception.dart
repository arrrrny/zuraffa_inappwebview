/// The typed native failure on macOS.
class MacosInappwebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const MacosInappwebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'MacosInappwebviewException($code, recoverable: $recoverable): $message';
}
