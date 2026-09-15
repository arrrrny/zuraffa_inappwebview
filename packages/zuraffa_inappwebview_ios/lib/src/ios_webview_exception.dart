/// The typed native failure on iOS.
class IosWebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const IosWebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'IosWebviewException($code, recoverable: $recoverable): $message';
}
