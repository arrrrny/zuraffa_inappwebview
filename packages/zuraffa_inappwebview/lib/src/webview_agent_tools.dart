/// WebView agent tools (spec 010): the `webview.*` MCP tool suite over
/// the pool (session continuity) and the service, built as zuraffa-core
/// `McpTool`s.
library;

import 'dart:convert';

import 'package:zuraffa/zuraffa.dart' show McpTool, McpToolResult;

import 'webview_exception.dart';
import 'webview_pool.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// Persists screenshot bytes where the agent can dereference them (a
/// file path, content-addressed URI, or object-store key) and returns
/// that key.
///
/// `mcp_tool.dart` defines `artifactRef` as precisely that pointer and
/// requires the body to stay off the JSON-RPC boundary, so the sink is
/// the way to get a real ref: the host owns artifact storage, the tool
/// only names it. Without a sink the tool returns the bytes to the
/// caller instead (see `_ScreenshotTool`).
typedef ScreenshotArtifactSink = Future<String> Function(
  String webviewId,
  List<int> bytes,
);

/// Builds the six-tool `webview.*` suite (spec 010): browse, execute_js,
/// read_cookies, screenshot, dismiss_dialogues, release_session. Every
/// tool validates defensively and returns an [McpToolResult] — typed
/// [WebviewException]s degrade to `isError` results, never throws across
/// the MCP boundary. Sessions ride [WebviewPool] so a mission's whole
/// action sequence operates on one webview.
class WebviewAgentTools {
  final WebviewService service;
  final WebviewPool pool;

  /// Optional resolver for screenshot artifacts; see
  /// [ScreenshotArtifactSink].
  final ScreenshotArtifactSink? artifactSink;

  const WebviewAgentTools({
    required this.service,
    required this.pool,
    this.artifactSink,
  });

  List<McpTool> buildTools() => [
        _BrowseTool(service, pool),
        _ExecuteJsTool(service, pool),
        _ReadCookiesTool(service),
        _ScreenshotTool(service, pool, artifactSink),
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

/// Resolves the pooled webview for [session], refusing a session that was
/// never started (or was already released) — otherwise the tools would
/// silently succeed against a freshly created blank instance.
Future<String> _requireSession(WebviewPool pool, String session) async {
  if (!pool.hasSession(session)) {
    throw WebviewException(
      'session_not_started',
      'No webview is bound to session "$session" — browse with that '
      'session first.',
      recoverable: true,
    );
  }
  return pool.acquire(session);
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
            'Loaded $url on session "$session". webviewId: $webviewId',
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
          final webviewId = await _requireSession(pool, session);
          final result =
              await service.evaluateJavascript(id: webviewId, source: source);
          // The payload rides `text`: McpToolResult.toJson (what the stdio
          // dispatcher sends) serialises isError/text/artifactRef only.
          return McpToolResult.ok(
            'Evaluated JavaScript on session "$session" '
            '(webviewId: $webviewId): $result',
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
      '(name/value/domain/path) from the shared cookie store. Values are '
      'returned verbatim — the capture streams redact cookie headers, an '
      'explicit read does not.';

  @override
  Map<String, dynamic> get inputSchema => _objectSchema({
        'url': {'type': 'string'},
      }, required: ['url']);

  @override
  Future<McpToolResult> call(Map<String, dynamic> arguments) => _guard(
        () async {
          final rawUrl = arguments['url'] as String?;
          if (rawUrl == null || rawUrl.isEmpty) {
            return McpToolResult.error('Missing required argument: url');
          }
          final url = WebviewUri(rawUrl).toString();
          final cookies = await service.getCookies(url: url);
          final data = {
            'cookies': [
              for (final c in cookies)
                {
                  'name': c.name,
                  'value': c.value,
                  if (c.domain != null) 'domain': c.domain,
                  'path': c.path,
                },
            ],
          };
          return McpToolResult.ok(
            'Read ${cookies.length} cookies on $url: '
            '${jsonEncode(data['cookies'])}',
            data: data,
          );
        },
      );
}

class _ScreenshotTool implements McpTool {
  final WebviewService service;
  final WebviewPool pool;
  final ScreenshotArtifactSink? artifactSink;

  const _ScreenshotTool(this.service, this.pool, this.artifactSink);

  @override
  String get name => 'screenshot';

  @override
  String get description => 'Captures the pooled webview bound to '
      '[session] as a PNG. With an artifactSink configured the result '
      'carries a dereferenceable artifactRef plus the byte length and '
      'never the body; without one the bytes are returned base64-encoded '
      'so the caller still gets the image.';

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
          final webviewId = await _requireSession(pool, session);
          final bytes = await service.takeScreenshot(
            id: webviewId,
            config: const ScreenshotConfiguration(),
          );
          if (bytes == null) {
            return McpToolResult.error(
              'webview.capture_failed: the platform returned no bytes.',
              data: {'code': 'capture_failed'},
            );
          }
          final data = {'webviewId': webviewId, 'byteLength': bytes.length};
          final sink = artifactSink;
          if (sink != null) {
            return McpToolResult.artifact(
              await sink(webviewId, bytes),
              text: 'Captured ${bytes.length} bytes.',
              data: data,
            );
          }
          // No sink: return the bytes rather than a ref nothing can
          // resolve. The body rides `text`, which is where every other
          // tool's payload goes — `data` is not serialised on the wire.
          return McpToolResult.ok(
            'Captured ${bytes.length} bytes (image/png, base64): '
            '${base64Encode(bytes)}',
            data: data,
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
          final webviewId = await _requireSession(pool, session);
          await service.dismissDialogues(id: webviewId);
          return McpToolResult.ok(
            'Dismissed overlays on session "$session" '
            '(webviewId: $webviewId).',
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
          if (!pool.hasSession(session)) {
            return McpToolResult.error(
              'webview.session_not_started: no webview is bound to session '
              '"$session".',
              data: {'code': 'session_not_started'},
            );
          }
          await pool.release(session);
          return McpToolResult.ok('Released session "$session".');
        },
      );
}
