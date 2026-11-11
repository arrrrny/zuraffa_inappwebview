import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'android_webview_channel.dart';
import 'android_webview_exception.dart';

/// Android [WebviewPort] over the typed [AndroidWebviewChannel].
///
/// Every operation rides the shared envelope: typed native errors pass
/// through, transport failures become the adapter's typed failures, and the
/// payload contract is the one the native shell implements:
/// `createHeadless/runHeadless/disposeHeadless/loadUrl/currentUrl/
/// evaluateJavascript/getHtml/setCookie/getCookies/deleteCookie/
/// deleteAllCookies/isSupported`.
class AndroidWebviewPort implements WebviewPort {
  final AndroidWebviewChannel channel;

  const AndroidWebviewPort({required this.channel});

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
      throw const AndroidWebviewException(
        'malformed_response',
        'The capture result carried a non-list data payload.',
        recoverable: false,
      );
    }
    if (raw.any((b) => b is! int)) {
      throw const AndroidWebviewException(
        'malformed_response',
        'The capture result carried non-integer byte values.',
        recoverable: false,
      );
    }
    return raw.cast<int>();
  }

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) {
    final source = channel.eventSource;
    if (source == null) {
      return Stream.error(const AndroidWebviewException(
        'channel_not_wired',
        'No event source was injected — pass one to the channel to '
        'subscribe to navigation events.',
        recoverable: false,
      ));
    }
    return source('navigationEvents').asyncMap((raw) {
      if (raw is! Map) {
        throw const AndroidWebviewException(
          'malformed_response',
          'A navigation event carried a non-map payload.',
          recoverable: false,
        );
      }
      return Map<String, Object?>.from(raw);
    }).where((map) => map['id'] == id).map(
          WebviewNavigationEvent.fromChannelArgs,
        );
  }

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {
    await channel.call('loadHtml', {
      'id': id,
      'html': html,
      if (baseUrl != null) 'baseUrl': baseUrl,
    });
  }

  @override
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) async {
    await channel.call('setCaptureEnabled', {
      'id': id,
      'enabled': enabled,
      if (filter != null) ...filter.toChannelArgs(),
    });
  }

  @override
  Stream<WebviewCaptureEntry> captureEvents({required String id}) {
    final source = channel.eventSource;
    if (source == null) {
      return Stream.error(const AndroidWebviewException(
        'channel_not_wired',
        'No event source was injected — pass one to the channel to '
        'subscribe to capture events.',
        recoverable: false,
      ));
    }
    return source('captureEvents').asyncMap((raw) {
      if (raw is! Map) {
        throw const AndroidWebviewException(
          'malformed_response',
          'A capture event carried a non-map payload.',
          recoverable: false,
        );
      }
      return Map<String, Object?>.from(raw);
    }).where((map) => map['id'] == id).map(
          WebviewCaptureEntry.fromChannelArgs,
        );
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
      throw const AndroidWebviewException(
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
