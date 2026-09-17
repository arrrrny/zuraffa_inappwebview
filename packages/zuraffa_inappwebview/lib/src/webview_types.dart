import 'webview_exception.dart';

/// A validated webview URL. Only `http`, `https`, and `about:blank` are
/// accepted — the webview is a scraping/browsing surface, not a file or
/// custom-scheme loader (custom schemes can be added behind an explicit
/// setting later).
class WebviewUri {
  final Uri uri;

  WebviewUri(String raw) : uri = _validate(raw);

  static Uri _validate(String raw) {
    final Uri parsed;
    try {
      parsed = Uri.parse(raw);
    } on FormatException {
      throw WebviewException(
        'invalid_uri',
        '"$raw" is not a valid URI.',
        recoverable: false,
      );
    }
    final scheme = parsed.scheme.toLowerCase();
    const allowed = {'http', 'https', 'about'};
    if (!allowed.contains(scheme)) {
      throw WebviewException(
        'unsupported_scheme',
        'Scheme "${parsed.scheme}" is not allowed — use http, https, or about:blank.',
        recoverable: false,
      );
    }
    if (scheme == 'about' && parsed.toString() != 'about:blank') {
      throw WebviewException(
        'unsupported_scheme',
        'The only supported about: URI is about:blank.',
        recoverable: false,
      );
    }
    return parsed;
  }

  @override
  String toString() => uri.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WebviewUri && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Typed subset of webview settings, shipped in the platform envelope.
///
/// The clean API starts with the settings the zuraffa ecosystem actually
/// uses (headless scraping: JS, UA, incognito, media gestures, viewport) —
/// the raw `InAppWebViewSettings`-style firehose is deliberately not
/// inherited from zikzak_inappwebview.
class WebviewSettings {
  final String? userAgent;
  final bool javaScriptEnabled;
  final bool incognito;
  final bool transparentBackground;
  final bool mediaPlaybackRequiresUserGesture;
  final bool supportZoom;
  final Duration loadTimeout;

  /// Removes fixed/sticky overlays (dialogue banners) after load for clean
  /// captures — off by default; the native side may also honor it (spec 002).
  final bool dismissDialogues;

  const WebviewSettings({
    this.userAgent,
    this.javaScriptEnabled = true,
    this.incognito = false,
    this.transparentBackground = false,
    this.mediaPlaybackRequiresUserGesture = true,
    this.supportZoom = true,
    this.loadTimeout = const Duration(seconds: 30),
    this.dismissDialogues = false,
  });

  Map<String, Object?> toChannelArgs() => {
        if (userAgent != null) 'userAgent': userAgent,
        'javaScriptEnabled': javaScriptEnabled,
        'incognito': incognito,
        'transparentBackground': transparentBackground,
        'mediaPlaybackRequiresUserGesture': mediaPlaybackRequiresUserGesture,
        'supportZoom': supportZoom,
        'loadTimeoutMs': loadTimeout.inMilliseconds,
        'dismissDialogues': dismissDialogues,
      };
}

/// A cookie for the webview's cookie store.
class WebviewCookie {
  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expiresAt;
  final bool secure;

  const WebviewCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path = '/',
    this.expiresAt,
    this.secure = false,
  });

  WebviewCookie copyWith({String? value, DateTime? expiresAt}) =>
      WebviewCookie(
        name: name,
        value: value ?? this.value,
        domain: domain,
        path: path,
        expiresAt: expiresAt ?? this.expiresAt,
        secure: secure,
      );

  Map<String, Object?> toChannelArgs() => {
        'name': name,
        'value': value,
        if (domain != null) 'domain': domain,
        'path': path,
        if (expiresAt != null)
          'expiresAtMs': expiresAt!.millisecondsSinceEpoch,
        'secure': secure,
      };

  static WebviewCookie fromChannelArgs(Map<String, Object?> args) =>
      WebviewCookie(
        name: args['name'] as String,
        value: args['value'] as String? ?? '',
        domain: args['domain'] as String?,
        path: args['path'] as String? ?? '/',
        expiresAt: args['expiresAtMs'] is int
            ? DateTime.fromMillisecondsSinceEpoch(args['expiresAtMs'] as int)
            : null,
        secure: args['secure'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebviewCookie &&
          other.name == name &&
          other.domain == domain &&
          other.path == path;

  @override
  int get hashCode => Object.hash(name, domain, path);
}
