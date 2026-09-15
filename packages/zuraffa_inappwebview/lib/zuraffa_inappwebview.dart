/// zuraffa_inappwebview — Inappwebview support for the Zuraffa ecosystem.
///
/// A pure-Dart port (`InappwebviewPort`), a facade (`InappwebviewService`),
/// typed failures, and DI registration. Platform adapters implement the
/// port over an injected platform channel — the shared envelope machinery
/// lives in `zuraffa_inappwebview_platform`.
library;

export 'src/inappwebview_exception.dart';
export 'src/inappwebview_module.dart';
export 'src/inappwebview_port.dart';
export 'src/inappwebview_service.dart';
export 'src/inappwebview_value.dart';
