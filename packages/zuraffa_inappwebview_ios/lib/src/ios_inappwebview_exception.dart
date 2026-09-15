/// The typed native failure on iOS.
class IosInappwebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const IosInappwebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'IosInappwebviewException($code, recoverable: $recoverable): $message';
}
