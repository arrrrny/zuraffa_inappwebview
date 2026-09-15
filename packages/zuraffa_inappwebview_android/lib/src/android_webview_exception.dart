/// The typed native failure on Android.
class AndroidWebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const AndroidWebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'AndroidWebviewException($code, recoverable: $recoverable): $message';
}
