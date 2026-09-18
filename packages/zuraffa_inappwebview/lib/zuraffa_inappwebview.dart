/// zuraffa_inappwebview — Zuraffa-native in-app webview for Flutter.
///
/// A clean, typed webview API (headless lifecycle, navigation, JS
/// evaluation, cookies) over a platform-neutral `WebviewPort`. Platform
/// adapters implement the port over an injected channel — the shared
/// envelope machinery lives in `zuraffa_inappwebview_platform`.
///
/// Fresh API: deliberately does NOT inherit the
/// flutter_inappwebview-derived surface of zikzak_inappwebview. The
/// settings/cookie subsets cover the zuraffa ecosystem's scraping and
/// browsing needs and grow per need.
library;

export 'src/dialogue_dismiss.dart'
    show DialogueDismissPolicy, DialogueDismissScript;
export 'src/webview_exception.dart';
export 'src/webview_module.dart'
    show WebviewModule, registerWebview;
export 'src/webview_port.dart' show WebviewPort;
export 'src/webview_service.dart' show UnwiredWebviewPort, WebviewService;
export 'src/webview_types.dart'
    show
        ScreenshotConfiguration,
        ScreenshotFormat,
        WebviewCookie,
        WebviewSettings,
        WebviewUri;
export 'src/webview_usecases.dart'
    show
        EvaluateJavascriptParams,
        EvaluateJavascriptUseCase,
        LoadUrlParams,
        LoadUrlUseCase,
        SetCookieParams,
        SetCookieUseCase;
