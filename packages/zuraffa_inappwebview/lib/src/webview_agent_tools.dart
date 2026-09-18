/// WebView agent tools (spec 010): the `webview.*` MCP tool suite over
/// the pool (session continuity) and the service, built as zuraffa-core
/// `McpTool`s.
library;

import 'package:zuraffa/zuraffa.dart' show McpTool, McpToolResult;

import 'webview_exception.dart';
import 'webview_pool.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// Builds the six-tool `webview.*` suite (spec 010): browse, execute_js,
/// read_cookies, screenshot, dismiss_dialogues, release_session. Every
/// tool validates defensively and returns an [McpToolResult] — typed
/// [WebviewException]s degrade to `isError` results, never throws across
/// the MCP boundary. Sessions ride [WebviewPool] so a mission's whole
/// action sequence operates on one webview.
class WebviewAgentTools {
  final WebviewService service;
  final WebviewPool pool;

  const WebviewAgentTools({required this.service, required this.pool});

  List<McpTool> buildTools() => [
        _BrowseTool(service, pool),
        _ExecuteJsTool(service, pool),
        _ReadCookiesTool(service),
        _ScreenshotTool(service, pool),
        _DismissDialoguesTool(service, pool),
        _ReleaseSessionTool(pool),
      ];
}

McpToolResult _degrade(Object error) {
  if (error is WebviewException) {
    return McpToolResult.error(
      'webview.${error.code}: ${error.message}',
      data: {'code': error.code},
    );
  }
  return McpToolResult.error('webview.tool_failed: $error');
}

Future<McpToolResult> _guard(Future<McpToolResult> Function() body) async {
  try {
    return await body();
  } catch (e) {
    return _degrade(e);
  }
}

Map<String, Object?> _objectSchema(
  Map<String, Object?> properties, {
  List<String> required = const [],
}) =>
    {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };

class _BrowseTool implements McpTool {
  final WebviewService service;
  final WebviewPool pool;

  const _BrowseTool(this.service, this.pool);

  @override
  String get name => 'browse';

  @override
  String get description => 'Loads [url] on the pooled headless webview '
      'for [session]. Further webview.* calls with the same session '
      'operate on the same instance (navigation state and cookies stay '
      'intact). Returns the webviewId.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'session': {'type': 'string'},
        'url': {'type': 'string'},
      }, required: ['session', 'url']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final session = arguments['session'] as String?;
          final rawUrl = arguments['url'] as String?;
          if (session == null || session.isEmpty) {
            return McpToolResult.error('Missing required argument: session');
          }
          if (rawUrl == null || rawUrl.isEmpty) {
            return McpToolResult.error('Missing required argument: url');
          }
          final url = WebviewUri(rawUrl);
          final host = url.uri.host.isEmpty ? null : url.uri.host;
          final webviewId = await pool.acquire(session, domainHint: host);
          await service.loadUrl(id: webviewId, url: url);
          return McpToolResult.ok(
            'Loaded $url on session "$session".',
            data: {'webviewId': webviewId, 'url': url.toString()},
          );
        },
      );
}

class _ExecuteJsTool implements McpTool {
  final WebviewService service;
  final WebviewPool pool;

  const _ExecuteJsTool(this.service, this.pool);

  @override
  String get name => 'execute_js';

  @override
  String get description => 'Evaluates [source] in the pooled webview '
      'bound to [session] and returns the result plus its webviewId.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'session': {'type': 'string'},
        'source': {'type': 'string'},
      }, required: ['session', 'source']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final session = arguments['session'] as String?;
          final source = arguments['source'] as String?;
          if (session == null || session.isEmpty) {
            return McpToolResult.error('Missing required argument: session');
          }
          if (source == null || source.isEmpty) {
            return McpToolResult.error('Missing required argument: source');
          }
          final webviewId = await pool.acquire(session);
          final result =
              await service.evaluateJavascript(id: webviewId, source: source);
          return McpToolResult.ok(
            'Evaluated JavaScript on session "$session".',
            data: {'webviewId': webviewId, 'result': '$result'},
          );
        },
      );
}

class _ReadCookiesTool implements McpTool {
  final WebviewService service;

  const _ReadCookiesTool(this.service);

  @override
  String get name => 'read_cookies';

  @override
  String get description => 'Returns the cookies stored for [url] '
      '(name/value/domain/path) from the shared cookie store.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'url': {'type': 'string'},
      }, required: ['url']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final url = arguments['url'] as String?;
          if (url == null || url.isEmpty) {
            return McpToolResult.error('Missing required argument: url');
          }
          final cookies = await service.getCookies(url: url);
          return McpToolResult.ok(
            'Read ${cookies.length} cookies.',
            data: {
              'cookies': [
                for (final c in cookies)
                  {
                    'name': c.name,
                    'value': c.value,
                    if (c.domain != null) 'domain': c.domain,
                    'path': c.path,
                  },
              ],
            },
          );
        },
      );
}

class _ScreenshotTool implements McpTool {
  final WebviewService service;
  final WebviewPool pool;

  const _ScreenshotTool(this.service, this.pool);

  @override
  String get name => 'screenshot';

  @override
  String get description => 'Captures the pooled webview bound to '
      '[session] as a PNG. Size discipline: the payload carries an '
      'artifactRef and byteLength only — never the byte body.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'session': {'type': 'string'},
      }, required: ['session']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final session = arguments['session'] as String?;
          if (session == null || session.isEmpty) {
            return McpToolResult.error('Missing required argument: session');
          }
          final webviewId = await pool.acquire(session);
          final bytes = await service.takeScreenshot(id: webviewId);
          if (bytes == null) {
            return McpToolResult.error(
              'webview.capture_failed: the platform returned no bytes.',
              data: {'code': 'capture_failed'},
            );
          }
          return McpToolResult.artifact(
            'webview:$webviewId:screenshot',
            text: 'Captured ${bytes.length} bytes.',
            data: {'webviewId': webviewId, 'byteLength': bytes.length},
          );
        },
      );
}

class _DismissDialoguesTool implements McpTool {
  final WebviewService service;
  final WebviewPool pool;

  const _DismissDialoguesTool(this.service, this.pool);

  @override
  String get name => 'dismiss_dialogues';

  @override
  String get description => 'Removes fixed/sticky overlays (cookie '
      'banners, chat widgets) from the pooled webview bound to [session] '
      'for clean captures.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'session': {'type': 'string'},
      }, required: ['session']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final session = arguments['session'] as String?;
          if (session == null || session.isEmpty) {
            return McpToolResult.error('Missing required argument: session');
          }
          final webviewId = await pool.acquire(session);
          await service.dismissDialogues(id: webviewId);
          return McpToolResult.ok(
            'Dismissed overlays on session "$session".',
            data: {'webviewId': webviewId},
          );
        },
      );
}

class _ReleaseSessionTool implements McpTool {
  final WebviewPool pool;

  const _ReleaseSessionTool(this.pool);

  @override
  String get name => 'release_session';

  @override
  String get description => 'Returns the pooled webview bound to '
      '[session] to the pool (kept warm for same-domain reuse).';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'session': {'type': 'string'},
      }, required: ['session']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final session = arguments['session'] as String?;
          if (session == null || session.isEmpty) {
            return McpToolResult.error('Missing required argument: session');
          }
          await pool.release(session);
          return McpToolResult.ok('Released session "$session".');
        },
      );
}
