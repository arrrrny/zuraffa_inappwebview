/// The typed failure surfaced by the zuraffa_inappwebview port, service,
/// and usecases. `code` values are stable: `invalid_uri`, `unsupported_scheme`,
/// `not_created`, `already_created`, `already_disposed`, `port_not_wired`,
/// `timeout`, `channel_error`, `malformed_response`.
class WebviewException implements Exception {
  final String code;
  final String message;
  final bool recoverable;

  const WebviewException(
    this.code,
    this.message, {
    required this.recoverable,
  });

  @override
  String toString() =>
      'WebviewException($code, recoverable: $recoverable): $message';
}
