import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Golden copy of the canonical dismissal script.
///
/// Deliberately duplicated from `DialogueDismissScript.source`: the shipped
/// payload is a behaviour contract, so editing it must be a conscious,
/// reviewable diff here too (spec 002, D3/D4). Whitespace is normalized
/// before comparison, so only a semantic edit trips the pin.
const String _goldenDismissSource = '''
(function () {
  try {
    var removed = 0;
    var all = document.querySelectorAll('*');
    var doomed = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el === document.documentElement || el === document.body) continue;
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') doomed.push(el);
    }
    for (var k = 0; k < doomed.length; k++) {
      doomed[k].remove();
      removed++;
    }
    var roots = [document.documentElement, document.body];
    for (var j = 0; j < roots.length; j++) {
      if (!roots[j]) continue;
      roots[j].style.overflow = '';
      roots[j].style.margin = '';
    }
    return removed;
  } catch (e) {
    return 0;
  }
})()
''';

/// Golden copy of the reset block (spec 002, D4).
const String _goldenResetBlock = '''
    var roots = [document.documentElement, document.body];
    for (var j = 0; j < roots.length; j++) {
      if (!roots[j]) continue;
      roots[j].style.overflow = '';
      roots[j].style.margin = '';
    }
''';

/// Trims each line and drops blanks so the pins tolerate reformatting.
String _normalizeSource(String source) => source
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .join('\n');

/// Fake port that records every evaluated JS source (per id) and can be
/// scripted to raise during evaluation.
class RecordingWebviewPort implements WebviewPort {
  final List<(String id, String source)> evaluated = [];
  Object? Function(String source)? evaluateHook;

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
  }) async {
    evaluated.add((id, source));
    final hook = evaluateHook;
    if (hook != null) {
      return hook(source);
    }
    return null;
  }

  @override
  Future<String?> getHtml({required String id}) async => null;

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
  late RecordingWebviewPort port;
  late WebviewService service;

  setUp(() async {
    port = RecordingWebviewPort();
    service = WebviewService(port: port);
    await service.createHeadless(id: 'scraper');
  });

  group('US1 — typed setting', () {
    test('D1: default is off and serialized', () {
      expect(WebviewSettings().toChannelArgs()['dismissDialogues'], isFalse);
    });

    test('D2: opted-in flag serializes', () {
      expect(
        const WebviewSettings(dismissDialogues: true)
            .toChannelArgs()['dismissDialogues'],
        isTrue,
      );
    });
  });

  group('US2 — canonical script', () {
    final source = DialogueDismissScript.source;

    test('D3: canonical source is pinned (removal contract, golden)', () {
      expect(_normalizeSource(source), _normalizeSource(_goldenDismissSource));
    });

    test('D4: resets overflow/margin on documentElement and body', () {
      expect(
        _normalizeSource(source),
        contains(_normalizeSource(_goldenResetBlock)),
      );
    });

    test('D5: top-level document only (no frames recursion)', () {
      expect(source, isNot(contains('frames')));
      expect(source, isNot(contains('iframe')));
      expect(source, isNot(contains('contentWindow')));
    });
  });

  group('US3 — policy', () {
    test('D6: attempts clamp to >= 1; defaults 1 attempt, zero delay', () {
      const policy = DialogueDismissPolicy(attempts: 0);
      expect(policy.attempts, 1);
      expect(const DialogueDismissPolicy().attempts, 1);
      expect(const DialogueDismissPolicy().delay, Duration.zero);
    });
  });

  group('service facade', () {
    test('D7: one canonical evaluation per default call', () async {
      await service.dismissDialogues(id: 'scraper');
      expect(port.evaluated, hasLength(1));
      expect(port.evaluated.single, ('scraper', DialogueDismissScript.source));
    });

    test('D8: unknown id -> typed not_created', () {
      expect(
        () => service.dismissDialogues(id: 'nope'),
        throwsA(
          isA<WebviewException>().having(
            (e) => e.code,
            'code',
            'not_created',
          ),
        ),
      );
    });

    test('D9: port errors during dismissal are swallowed', () async {
      port.evaluateHook = (_) => throw const WebviewException(
            'javascript_failed',
            'boom',
            recoverable: true,
          );
      await service.dismissDialogues(id: 'scraper');
      expect(port.evaluated, hasLength(1));
    });

    test('D10: attempts drive repeated evaluations with delay', () async {
      const policy = DialogueDismissPolicy(
        attempts: 3,
        delay: Duration(milliseconds: 5),
      );
      await service.dismissDialogues(id: 'scraper', policy: policy);
      expect(port.evaluated, hasLength(3));
      expect(
        port.evaluated.every((e) => e.$2 == DialogueDismissScript.source),
        isTrue,
      );
    });
  });
}
