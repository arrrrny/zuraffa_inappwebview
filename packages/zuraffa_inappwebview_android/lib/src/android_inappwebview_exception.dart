/// The typed native failure on Android.
class AndroidInappwebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const AndroidInappwebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'AndroidInappwebviewException($code, recoverable: $recoverable): $message';
}
