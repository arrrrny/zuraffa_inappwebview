import 'package:zuraffa/zuraffa.dart';

import 'webview_exception.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// Parameters for [LoadUrlUseCase].
class LoadUrlParams {
  final String webviewId;
  final WebviewUri url;
  final Map<String, String> headers;

  const LoadUrlParams({
    required this.webviewId,
    required this.url,
    this.headers = const {},
  });
}

/// Loads a URL in a created webview. Lifecycle mistakes surface as
/// [WebviewException]s (an `AppFailure` subtype is not used here: the
/// webview failures are already typed and recoverable-flagged).
class LoadUrlUseCase extends UseCase<void, LoadUrlParams> {
  final WebviewService service;

  LoadUrlUseCase({required this.service});

  @override
  Future<void> execute(LoadUrlParams params, CancelToken? cancelToken) =>
      service.loadUrl(id: params.webviewId, url: params.url,
          headers: params.headers);
}

/// Parameters for [EvaluateJavascriptUseCase].
class EvaluateJavascriptParams {
  final String webviewId;
  final String source;

  const EvaluateJavascriptParams({
    required this.webviewId,
    required this.source,
  });
}

/// Evaluates JavaScript in a created webview's main frame.
class EvaluateJavascriptUseCase extends UseCase<Object?, EvaluateJavascriptParams> {
  final WebviewService service;

  EvaluateJavascriptUseCase({required this.service});

  @override
  Future<Object?> execute(
          EvaluateJavascriptParams params, CancelToken? cancelToken) =>
      service.evaluateJavascript(id: params.webviewId, source: params.source);
}

/// Parameters for [SetCookieUseCase].
class SetCookieParams {
  final WebviewCookie cookie;

  const SetCookieParams({required this.cookie});
}

/// Stores a cookie in the webview's shared cookie store.
class SetCookieUseCase extends UseCase<void, SetCookieParams> {
  final WebviewService service;

  SetCookieUseCase({required this.service});

  @override
  Future<void> execute(SetCookieParams params, CancelToken? cancelToken) =>
      service.setCookie(params.cookie);
}
