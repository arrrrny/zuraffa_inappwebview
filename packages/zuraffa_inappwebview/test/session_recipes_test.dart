import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

WebviewNavigationEvent _completed(String url, {bool mainFrame = true}) =>
    WebviewNavigationEvent.fromChannelArgs(
        {'type': 'completed', 'url': url, 'isMainFrame': mainFrame})!;

void main() {
  group('US1 — recorder', () {
    test('R1: completed main-frame visits become ordered url steps',
        () async {
      final controller = StreamController<WebviewNavigationEvent>();
      final recorder = RecipeRecorder(name: 'buy-flow')
        ..attach('w', controller.stream);
      controller.add(_completed('https://a.dev/'));
      controller.add(_completed('https://b.dev/cart'));
      await Future<void>.delayed(Duration.zero);
      final recipe = recorder.finish();
      expect(recipe.name, 'buy-flow');
      expect(
        recipe.steps,
        [
          isA<RecipeUrlStep>().having((s) => s.url, 'url', 'https://a.dev/'),
          isA<RecipeUrlStep>()
              .having((s) => s.url, 'url', 'https://b.dev/cart'),
        ],
      );
      await controller.close();
    });

    test('R2: taps interleave in recording order', () {
      final recorder = RecipeRecorder(name: 'mixed');
      recorder.recordTap('#buy');
      recorder.handleEvent('w', _completed('https://a.dev/'));
      recorder.recordTap('.checkout');
      final recipe = recorder.finish();
      expect(recipe.steps, hasLength(3));
      expect(recipe.steps[0], isA<RecipeTapStep>()
          .having((s) => s.selector, 'selector', '#buy'));
      expect(recipe.steps[1], isA<RecipeUrlStep>());
      expect(recipe.steps[2], isA<RecipeTapStep>()
          .having((s) => s.selector, 'selector', '.checkout'));
    });

    test('R3: empty recorder -> empty named recipe', () {
      final recipe = RecipeRecorder(name: 'noop').finish();
      expect(recipe.name, 'noop');
      expect(recipe.steps, isEmpty);
    });

    test('R4: started/sub-frame events are ignored', () {
      final recorder = RecipeRecorder(name: 'noise');
      recorder.handleEvent('w',
          WebviewNavigationEvent.fromChannelArgs(
              {'type': 'started', 'url': 'https://a.dev/'})!);
      recorder.handleEvent('w', _completed('https://a.dev/frame',
          mainFrame: false));
      expect(recorder.finish().steps, isEmpty);
    });
  });

  group('US2 — replayer', () {
    late RecordingDriver driver;
    late SessionRecipe recipe;

    setUp(() {
      driver = RecordingDriver();
      recipe = const SessionRecipe(name: 'r', steps: [
        RecipeUrlStep(url: 'https://a.dev/'),
        RecipeTapStep(selector: '#buy'),
        RecipeUrlStep(url: 'https://b.dev/cart'),
      ]);
    });

    test('R5: drives steps in order; progress; completed result',
        () async {
      final progress = <ReplayProgress>[];
      final result = await replay(recipe, driver,
          onProgress: progress.add);
      expect(
        driver.calls,
        ['load:https://a.dev/', "tap:#buy", 'load:https://b.dev/cart'],
      );
      expect(result.completed, isTrue);
      expect(result.stepsDriven, 3);
      expect(progress.map((p) => p.stepIndex), [0, 1, 2]);
      expect(progress.every((p) => p.total == 3), isTrue);
    });

    test('R6: driver failure at step k -> failed result, partial drive',
        () async {
      driver.failOn('tap:#buy');
      final result = await replay(recipe, driver);
      expect(result.completed, isFalse);
      expect(result.failedStep, 1);
      expect(result.error, isNotNull);
      expect(
        driver.calls,
        ['load:https://a.dev/', 'tap:#buy'],
      );
      expect(result.stepsDriven, 1);
    });
  });

  group('US3 — service driver', () {
    test('R7: loadUrl + canonical tap script through the service',
        () async {
      final port = _RecipeFakePort();
      final service = WebviewService(port: port);
      await service.createHeadless(id: 'w');
      final driver = WebviewServiceRecipeDriver(
          service: service, webviewId: 'w');

      await driver.loadUrl(Uri.parse('https://x.dev/'));
      expect(port.lastLoadedUrl, 'https://x.dev/');

      await driver.tap('#buy');
      expect(port.lastEvaluatedSource, contains('querySelector'));
      expect(port.lastEvaluatedSource, contains('#buy'));
      expect(port.lastEvaluatedSource, contains('click'));
    });
  });
}

class RecordingDriver implements RecipeDriver {
  final List<String> calls = [];
  final Set<String> _failOn = {};

  void failOn(String call) => _failOn.add(call);

  @override
  Future<void> loadUrl(Uri url) async => _drive('load:$url');

  @override
  Future<void> tap(String selector) async => _drive('tap:$selector');

  Future<void> _drive(String call) async {
    calls.add(call);
    if (_failOn.contains(call)) throw StateError('driver failed at $call');
  }
}

class _RecipeFakePort implements WebviewPort {
  String? lastLoadedUrl;
  String? lastEvaluatedSource;

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
  }) async =>
      lastLoadedUrl = url.toString();

  @override
  Future<String?> currentUrl({required String id}) async => null;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async {
    lastEvaluatedSource = source;
    return null;
  }

  @override
  Future<String?> getHtml({required String id}) async => null;

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) async =>
      null;

  @override
  Future<List<int>?> exportPdf({required String id}) async => null;

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) =>
      const Stream.empty();

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {}

  @override
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) async {}

  @override
  Stream<WebviewCaptureEntry> captureEvents({required String id}) =>
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
