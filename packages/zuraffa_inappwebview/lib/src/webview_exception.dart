/// The typed failure surfaced by the zuraffa_inappwebview port, service,
/// and usecases. `code` values are stable: `invalid_uri`, `unsupported_scheme`,
/// `not_created`, `already_created`, `already_disposed`, `port_not_wired`,
/// `session_not_started`, `timeout`, `channel_error`, `malformed_response`.
///
/// The platform adapters' own typed exceptions implement this interface,
/// so a native failure stays catchable both as the adapter's type and as
/// a [WebviewException] carrying its code.
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
