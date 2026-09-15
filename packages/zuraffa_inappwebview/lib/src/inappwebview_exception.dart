/// The typed failure surfaced by the zuraffa_inappwebview port and service.
class InappwebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const InappwebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'InappwebviewException($code, recoverable: $recoverable): $message';
}
