import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Fake port with scriptable byte payloads for the capture ops.
class CaptureFakePort implements WebviewPort {
  List<int>? screenshotBytes;
  List<int>? pdfBytes;
  ScreenshotConfiguration? lastScreenshotConfig;
  String? lastPdfId;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async {}

  @override
  Future<void> runHeadless({required String id}) async {}

  @override
  Future<void> disposeHeadless({required String id}) async {}

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async {}

  @override
  Future<String?> currentUrl({required String id}) async => null;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async =>
      null;

  @override
  Future<String?> getHtml({required String id}) async => null;

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) async {
    lastScreenshotConfig = config;
    return screenshotBytes;
  }

  @override
  Future<List<int>?> exportPdf({required String id}) async {
    lastPdfId = id;
    return pdfBytes;
  }

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) =>
      const Stream.empty();

  @override
  Future<void> setCookie(WebviewCookie cookie) async {}

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) async => [];

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) async =>
      false;

  @override
  Future<void> deleteAllCookies() async {}
}

void main() {
  group('US2 — configuration', () {
    test('S1: defaults png/100; jpeg/80 overrides', () {
      expect(
        const ScreenshotConfiguration().toChannelArgs(),
        {'format': 'png', 'quality': 100},
      );
      expect(
        const ScreenshotConfiguration(
          format: ScreenshotFormat.jpeg,
          quality: 80,
        ).toChannelArgs(),
        {'format': 'jpeg', 'quality': 80},
      );
    });

    test('S1: quality is clamped to 1–100', () {
      expect(
        const ScreenshotConfiguration(quality: 500).toChannelArgs(),
        {'format': 'png', 'quality': 100},
      );
      expect(
        const ScreenshotConfiguration(quality: 0).toChannelArgs(),
        {'format': 'png', 'quality': 1},
      );
      expect(
        const ScreenshotConfiguration(quality: -3).toChannelArgs(),
        {'format': 'png', 'quality': 1},
      );
    });
  });

  group('US1 — service passthrough', () {
    late CaptureFakePort port;
    late WebviewService service;

    setUp(() async {
      port = CaptureFakePort();
      service = WebviewService(port: port);
      await service.createHeadless(id: 'scraper');
    });

    test('S2: bytes pass through unchanged (screenshot + pdf)', () async {
      port.screenshotBytes = [1, 2, 3];
      port.pdfBytes = [9, 8, 7];
      expect(await service.takeScreenshot(id: 'scraper'), [1, 2, 3]);
      expect(await service.exportPdf(id: 'scraper'), [9, 8, 7]);
      expect(port.lastPdfId, 'scraper');
    });

    test('S2: config reaches the port', () async {
      const config = ScreenshotConfiguration(
        format: ScreenshotFormat.jpeg,
        quality: 80,
      );
      await service.takeScreenshot(id: 'scraper', config: config);
      expect(port.lastScreenshotConfig, config);
    });

    test('S3: null port result -> null service result', () async {
      expect(await service.takeScreenshot(id: 'scraper'), isNull);
      expect(await service.exportPdf(id: 'scraper'), isNull);
    });

    test('S4: unknown id -> typed not_created (both ops)', () {
      for (final call in [
        () => service.takeScreenshot(id: 'nope'),
        () => service.exportPdf(id: 'nope'),
      ]) {
        expect(
          call,
          throwsA(
            isA<WebviewException>()
                .having((e) => e.code, 'code', 'not_created'),
          ),
        );
      }
    });
  });

  group('unwired', () {
    test('S5: port_not_wired for both ops', () {
      const port = UnwiredWebviewPort();
      expect(
        () => port.takeScreenshot(id: 'w'),
        throwsA(
          isA<WebviewException>()
              .having((e) => e.code, 'code', 'port_not_wired'),
        ),
      );
      expect(
        () => port.exportPdf(id: 'w'),
        throwsA(
          isA<WebviewException>()
              .having((e) => e.code, 'code', 'port_not_wired'),
        ),
      );
    });
  });
}
