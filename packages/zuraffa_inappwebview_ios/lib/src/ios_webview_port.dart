import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'ios_webview_channel.dart';
import 'ios_webview_exception.dart';

/// iOS [WebviewPort] over the typed [IosWebviewChannel].
///
/// Every operation rides the shared envelope: typed native errors pass
/// through, transport failures become the adapter's typed failures, and the
/// payload contract is the one the native shell implements:
/// `createHeadless/runHeadless/disposeHeadless/loadUrl/currentUrl/
/// evaluateJavascript/getHtml/setCookie/getCookies/deleteCookie/
/// deleteAllCookies/isSupported`.
class IosWebviewPort implements WebviewPort {
  final IosWebviewChannel channel;

  const IosWebviewPort({required this.channel});

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

  /// Captures the page as raw image bytes; `null` when the platform could
  /// not capture (spec 003).
  ///
  /// Captures are MB-scale, so whatever `ChannelInvoke` transport the native
  /// milestone ships, `data` should be encoded binary-first
  /// (`Uint8List`/byte buffer): a ~3 MB PNG arrives as a ~10-20 MB list of
  /// boxed ints if it is carried JSON-style.
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

  /// Exports the page as PDF bytes; `null` on failure (spec 003).
  ///
  /// Same binary-first note as [takeScreenshot] — PDFs are MB-scale too.
  @override
  Future<List<int>?> exportPdf({required String id}) async {
    final result = await channel.call('exportPdf', {'id': id});
    return _decodeBytes(result?['data']);
  }

  List<int>? _decodeBytes(Object? raw) {
    if (raw == null) return null;
    if (raw is! List) {
      throw const IosWebviewException(
        'malformed_response',
        'The capture result carried a non-list data payload.',
        recoverable: false,
      );
    }
    return [
      for (final b in raw)
        if (b is int)
          b
        else
          throw const IosWebviewException(
            'malformed_response',
            'The capture data list carried a non-int byte.',
            recoverable: false,
          ),
    ];
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
      throw const IosWebviewException(
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
