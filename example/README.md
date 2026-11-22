# zuraffa_inappwebview

An in-app WebView plugin for Zuraffa/Flutter — display web content inside the
app with full control over navigation, cookies and JavaScript bridges.

## Show a web page

```dart
import 'package:flutter/material.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

class WebScreen extends StatelessWidget {
  const WebScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: Uri.parse('https://example.com')),
    );
  }
}
```

## Listen to URL changes

```dart
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

final controller = InAppWebViewController();
controller.onUrlChange = (url) => debugPrint('navigated to $url');
```