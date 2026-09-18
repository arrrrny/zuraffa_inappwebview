import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'macos_webview_channel.dart';
import 'macos_webview_exception.dart';

/// macOS [WebviewPort] over the typed [MacosWebviewChannel].
///
/// Every operation rides the shared envelope: typed native errors pass
/// through, transport failures become the adapter's typed failures, and the
/// payload contract is the one the native shell implements:
/// `createHeadless/runHeadless/disposeHeadless/loadUrl/currentUrl/
/// evaluateJavascript/getHtml/setCookie/getCookies/deleteCookie/
/// deleteAllCookies/isSupported`.
class MacosWebviewPort implements WebviewPort {
  final MacosWebviewChannel channel;

  const MacosWebviewPort({required this.channel});

  @override
  Future<bool> isSupported() async {
    final result = await channel.call('isSupported', const {});
    return result?['supported'] == true;
  }

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async {
    await channel.call('createHeadless', {
      'id': id,
      ...settings.toChannelArgs(),
    });
  }

  @override
  Future<void> runHeadless({required String id}) async {
    await channel.call('runHeadless', {'id': id});
  }

  @override
  Future<void> disposeHeadless({required String id}) async {
    await channel.call('disposeHeadless', {'id': id});
  }

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async {
    await channel.call('loadUrl', {
      'id': id,
      'url': url.toString(),
      'headers': headers,
    });
  }

  @override
  Future<String?> currentUrl({required String id}) async {
    final result = await channel.call('currentUrl', {'id': id});
    return result?['url'] as String?;
  }

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async {
    final result =
        await channel.call('evaluateJavascript', {'id': id, 'source': source});
    return result?['result'];
  }

  @override
  Future<String?> getHtml({required String id}) async {
    final result = await channel.call('getHtml', {'id': id});
    return result?['html'] as String?;
  }

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) async {
    final result = await channel.call('takeScreenshot', {
      'id': id,
      if (config != null) ...config.toChannelArgs(),
    });
    return _decodeBytes(result?['data']);
  }

  @override
  Future<List<int>?> exportPdf({required String id}) async {
    final result = await channel.call('exportPdf', {'id': id});
    return _decodeBytes(result?['data']);
  }

  List<int>? _decodeBytes(Object? raw) {
    if (raw == null) return null;
    if (raw is! List) {
      throw const MacosWebviewException(
        'malformed_response',
        'The capture result carried a non-list data payload.',
        recoverable: false,
      );
    }
    return [for (final b in raw) b as int];
  }

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) {
    final source = channel.eventSource;
    if (source == null) {
      return Stream.error(const MacosWebviewException(
        'channel_not_wired',
        'No event source was injected — pass one to the channel to '
        'subscribe to navigation events.',
        recoverable: false,
      ));
    }
    // A non-map payload carries no id, so it cannot be attributed: that is
    // the typed `malformed_response` (FR-4). Map payloads are filtered by id
    // *before* their keys are decoded, so a payload bound for another
    // webview can never error this subscription's stream.
    return source('navigationEvents')
        .map(_requirePayload)
        .where((payload) => payload['id'] == id)
        // A null here means the phase wasn't recognized: the event is
        // skipped rather than coerced to `started`.
        .map(_decodeNavigationEvent)
        .where((event) => event != null)
        .cast<WebviewNavigationEvent>();
  }

  Map<Object?, Object?> _requirePayload(Object? raw) {
    if (raw is! Map) {
      throw const MacosWebviewException(
        'malformed_response',
        'A navigation event carried a non-map payload.',
        recoverable: false,
      );
    }
    return raw;
  }

  WebviewNavigationEvent? _decodeNavigationEvent(
    Map<Object?, Object?> payload,
  ) {
    final Map<String, Object?> args;
    try {
      args = Map<String, Object?>.from(payload);
    } on TypeError {
      throw const MacosWebviewException(
        'malformed_response',
        'A navigation event carried unusable keys.',
        recoverable: false,
      );
    }
    try {
      return WebviewNavigationEvent.fromChannelArgs(args);
    } on WebviewException catch (failure) {
      throw MacosWebviewException(
        failure.code,
        failure.message,
        recoverable: false,
      );
    }
  }

  @override
  Future<void> setCookie(WebviewCookie cookie) async {
    await channel.call('setCookie', cookie.toChannelArgs());
  }

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) async {
    final result = await channel.call('getCookies', {'url': url});
    final raw = result?['cookies'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const MacosWebviewException(
        'malformed_response',
        'The getCookies result carried a non-list payload.',
        recoverable: false,
      );
    }
    return [
      for (final entry in raw)
        WebviewCookie.fromChannelArgs(Map<String, Object?>.from(entry as Map)),
    ];
  }

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) async {
    final result = await channel.call('deleteCookie', {
      'url': url,
      'name': name,
      if (domain != null) 'domain': domain,
      'path': path,
    });
    return result?['deleted'] == true;
  }

  @override
  Future<void> deleteAllCookies() async {
    await channel.call('deleteAllCookies', const {});
  }
}
