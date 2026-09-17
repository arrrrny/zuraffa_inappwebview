import 'webview_types.dart';

/// The platform-neutral port every adapter implements. Pure Dart — the
/// transport is injected behind the platform envelope, so tests run
/// offline with fake channels.
abstract class WebviewPort {
  const WebviewPort();

  /// Whether the running platform provides a webview implementation.
  Future<bool> isSupported();

  /// Creates a headless webview bound to [id].
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  });

  /// Starts the event loop of the headless webview bound to [id].
  Future<void> runHeadless({required String id});

  /// Stops and releases the headless webview bound to [id].
  Future<void> disposeHeadless({required String id});

  /// Loads [url] (with optional [headers]) in the webview bound to [id].
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  });

  /// The webview's current URL, or null before the first load completes.
  Future<String?> currentUrl({required String id});

  /// Evaluates [source] in the webview's main frame and returns the result.
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  });

  /// The serialized HTML of the main frame's current document.
  Future<String?> getHtml({required String id});

  /// Captures the rendered page as image bytes (null when the platform
  /// could not capture). Channel: `takeScreenshot`, response key `data`.
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  });

  /// Exports the rendered page as PDF bytes (null on failure).
  /// Channel: `exportPdf`, response key `data`.
  Future<List<int>?> exportPdf({required String id});

  /// Stores [cookie] in the webview's shared cookie store.
  Future<void> setCookie(WebviewCookie cookie);

  /// The cookies stored for [url] (name/value/domain/path/expiry).
  Future<List<WebviewCookie>> getCookies({required String url});

  /// Deletes the cookie [name] stored for [url]. Returns whether it existed.
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  });

  /// Deletes every cookie in the webview's shared cookie store.
  Future<void> deleteAllCookies();
}
