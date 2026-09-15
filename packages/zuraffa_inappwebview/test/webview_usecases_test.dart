import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'webview_service_test.dart' show FakeWebviewPort;

void main() {
  late FakeWebviewPort port;
  late WebviewService service;

  setUp(() {
    port = FakeWebviewPort();
    service = WebviewService(port: port);
    return service.createHeadless(id: 'w');
  });

  group('usecases over the service (W12-W14)', () {
    test('W12: LoadUrlUseCase loads and folds success', () async {
      final usecase = LoadUrlUseCase(service: service);
      final result = await usecase(LoadUrlParams(
        webviewId: 'w',
        url: WebviewUri('https://x.dev/'),
      ));
      expect(result.isSuccess, isTrue);
    });

    test('W13: EvaluateJavascriptUseCase returns the evaluated value',
        () async {
      port.evaluateResult = 'ok';
      final usecase = EvaluateJavascriptUseCase(service: service);
      final result = await usecase(
        EvaluateJavascriptParams(webviewId: 'w', source: 'fn()'),
      );
      expect(result.isSuccess, isTrue);
      result.fold(
        (value) => expect(value, 'ok'),
        (failure) => fail('expected success'),
      );
    });

    test('W14: SetCookieUseCase stores the cookie', () async {
      final usecase = SetCookieUseCase(service: service);
      const cookie = WebviewCookie(name: 'k', value: 'v', domain: 'x.dev');
      final result = await usecase(SetCookieParams(cookie: cookie));
      expect(result.isSuccess, isTrue);
      expect(port.storedCookies, contains(cookie));
    });
  });
}
