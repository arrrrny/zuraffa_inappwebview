import 'dialogue_dismiss.dart';
import 'navigation_tracking.dart';
import 'network_capture.dart';
import 'webview_exception.dart';
import 'webview_port.dart';
import 'webview_types.dart';

/// Facade over the [WebviewPort]: owns the headless-webview registry and
/// turns lifecycle mistakes (double create, use-before-create,
/// use-after-dispose) into typed failures before they reach the platform.
class WebviewService {
  final WebviewPort port;
  final Set<String> _created = {};
  final Set<String> _running = {};

  WebviewService({required this.port});

  /// The headless webviews currently created (not necessarily running).
  Set<String> get created => Set.unmodifiable(_created);

  /// The headless webviews currently running.
  Set<String> get running => Set.unmodifiable(_running);

  Future<bool> supported() => port.isSupported();

  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async {
    if (_created.contains(id)) {
      throw WebviewException(
        'already_created',
        'Webview "$id" already exists — dispose it first.',
        recoverable: false,
      );
    }
    await port.createHeadless(id: id, settings: settings);
    _created.add(id);
  }

  Future<void> runHeadless({required String id}) async {
    _requireCreated(id);
    if (_running.contains(id)) {
      throw WebviewException(
        'already_running',
        'Webview "$id" is already running.',
        recoverable: false,
      );
    }
    await port.runHeadless(id: id);
    _running.add(id);
  }

  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async {
    _requireCreated(id);
    await port.loadUrl(id: id, url: url, headers: headers);
  }

  Future<String?> currentUrl({required String id}) async {
    _requireCreated(id);
    return port.currentUrl(id: id);
  }

  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async {
    _requireCreated(id);
    return port.evaluateJavascript(id: id, source: source);
  }

  Future<String?> getHtml({required String id}) async {
    _requireCreated(id);
    return port.getHtml(id: id);
  }

  /// Captures the rendered page as image bytes; null when the platform
  /// could not capture (spec 003).
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) {
    _requireCreated(id);
    return port.takeScreenshot(id: id, config: config);
  }

  /// Exports the rendered page as PDF bytes; null on failure (spec 003).
  Future<List<int>?> exportPdf({required String id}) {
    _requireCreated(id);
    return port.exportPdf(id: id);
  }

  /// Renders [html] directly with an optional [baseUrl] (spec 008).
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) {
    _requireCreated(id);
    return port.loadHtml(id: id, html: html, baseUrl: baseUrl);
  }

  /// Navigation events for the webview bound to [id] (spec 004).
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) {
    _requireCreated(id);
    return port.navigationEvents(id: id);
  }

  /// Removes fixed/sticky overlays from the loaded page for clean captures
  /// (spec 002). Best-effort by contract: port errors during dismissal are
  /// swallowed and never break the caller's flow.
  Future<void> dismissDialogues({
    required String id,
    DialogueDismissPolicy policy = const DialogueDismissPolicy(),
  }) async {
    _requireCreated(id);
    for (var attempt = 0; attempt < policy.attempts; attempt++) {
      if (attempt > 0 && policy.delay > Duration.zero) {
        await Future<void>.delayed(policy.delay);
      }
      try {
        await port.evaluateJavascript(
          id: id,
          source: DialogueDismissScript.source,
        );
      } on Object {
        // FR-5: dismissal is best-effort — a page-level JS failure must not
        // propagate. `Error`s (StateError/TypeError from a mis-wired port)
        // count too, not just `Exception`s.
      }
    }
  }

  Future<void> disposeHeadless({required String id}) async {
    _requireCreated(id);
    await port.disposeHeadless(id: id);
    _created.remove(id);
    _running.remove(id);
  }

  /// Enables/disables network capture for [id] (spec 005).
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) {
    _requireCreated(id);
    return port.setCaptureEnabled(id: id, enabled: enabled, filter: filter);
  }

  /// Intercepted traffic stream for [id] (spec 005).
  Stream<WebviewCaptureEntry> captureEvents({required String id}) {
    _requireCreated(id);
    return port.captureEvents(id: id);
  }

  // -- Cookies are global (shared store), no id scoping. --

  Future<void> setCookie(WebviewCookie cookie) => port.setCookie(cookie);

  Future<List<WebviewCookie>> getCookies({required String url}) =>
      port.getCookies(url: url);

  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) =>
      port.deleteCookie(
          url: url, name: name, domain: domain, path: path);

  Future<void> deleteAllCookies() => port.deleteAllCookies();

  void _requireCreated(String id) {
    if (!_created.contains(id)) {
      throw WebviewException(
        'not_created',
        'Webview "$id" is not created — call createHeadless() first.',
        recoverable: false,
      );
    }
  }
}

/// A port placeholder registered when no platform adapter was wired:
/// every operation surfaces the typed `port_not_wired` failure instead of
/// a null dereference at resolve time.
class UnwiredWebviewPort implements WebviewPort {
  const UnwiredWebviewPort();

  Never _unwired() => throw const WebviewException(
        'port_not_wired',
        'No WebviewPort was registered — wire the platform adapter for the '
        'running platform before resolving WebviewService.',
        recoverable: false,
      );

  @override
  Future<bool> isSupported() async => _unwired();

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) =>
      _unwired();

  @override
  Future<void> runHeadless({required String id}) => _unwired();

  @override
  Future<void> disposeHeadless({required String id}) => _unwired();

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) =>
      _unwired();

  @override
  Future<String?> currentUrl({required String id}) => _unwired();

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) =>
      _unwired();

  @override
  Future<String?> getHtml({required String id}) => _unwired();

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) =>
      _unwired();

  @override
  Future<List<int>?> exportPdf({required String id}) => _unwired();

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) =>
      _unwired();

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) =>
      _unwired();

  @override
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) =>
      _unwired();

  @override
  Stream<WebviewCaptureEntry> captureEvents({required String id}) =>
      _unwired();

  @override
  Future<void> setCookie(WebviewCookie cookie) => _unwired();

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) => _unwired();

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) =>
      _unwired();

  @override
  Future<void> deleteAllCookies() => _unwired();
}
