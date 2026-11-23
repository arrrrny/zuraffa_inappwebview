/// Portable sessions (spec 009): save/restore a headless webview's
/// session state (cookies + localStorage) through a store port — the
/// package never introduces its own storage format.
///
/// The stored payload is plaintext: cookie values and localStorage
/// entries are persisted exactly as the page set them, with no
/// encryption or redaction (an opt-out/encryption layer is a documented
/// follow-up). Back the store with an appropriately protected backend.
library;

import 'dart:convert';

import 'webview_exception.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// A persisted webview session: the cookies and localStorage of one
/// origin at save time.
class PortableSession {
  final String name;
  final String origin;
  final List<WebviewCookie> cookies;
  final Map<String, String> localStorage;
  final DateTime savedAt;

  PortableSession({
    required this.name,
    required this.origin,
    this.cookies = const [],
    this.localStorage = const {},
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  Map<String, Object?> toJson() => {
        'name': name,
        'origin': origin,
        'cookies': [for (final c in cookies) c.toChannelArgs()],
        'localStorage': localStorage,
        'savedAtMs': savedAt.millisecondsSinceEpoch,
      };

  /// Decodes a stored payload. A missing or foreign shape fails typed
  /// (`malformed_response`) instead of escaping as an untyped `TypeError`.
  static PortableSession fromJson(Map<String, Object?> json) {
    try {
      return PortableSession(
        name: json['name'] as String,
        origin: json['origin'] as String? ?? '',
        cookies: [
          for (final c in (json['cookies'] as List? ?? const []))
            WebviewCookie.fromChannelArgs(
                Map<String, Object?>.from(c as Map)),
        ],
        localStorage: Map<String, String>.from(
            json['localStorage'] as Map? ?? const {}),
        savedAt: json['savedAtMs'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['savedAtMs'] as int)
            : null,
      );
    } on Object catch (error) {
      throw WebviewException(
        'malformed_response',
        'The portable session payload could not be decoded: $error',
        recoverable: false,
      );
    }
  }
}

/// The only persistence path for portable sessions (spec 009 FR-2/FR-5):
/// implemented by the zuraffa session package or any store backend.
/// Every method is asynchronous so a real backend (file, keychain,
/// secure storage, remote) can be implemented without keeping the whole
/// store resident in memory.
abstract class WebviewSessionStore {
  Future<void> save(PortableSession session);
  Future<PortableSession?> read(String name);
  Future<void> delete(String name);
  Future<List<String>> list();
}

/// Saves and restores webview session state through a
/// [WebviewSessionStore] (spec 009): save snapshots the origin's cookies
/// plus the webview's localStorage (canonical JSON read); load re-applies
/// cookies through the cookie store and localStorage through `setItem`
/// evaluations. A missing session fails typed — nothing is applied.
class WebViewSessions {
  final WebviewService service;
  final WebviewSessionStore store;

  WebViewSessions({required this.service, required this.store});

  /// Snapshots the webview's cookies (for [origin]) and localStorage
  /// into a named session persisted via the store.
  Future<void> save({
    required String webviewId,
    required String name,
    required String origin,
  }) async {
    final cookies = await service.getCookies(url: origin);
    final raw = await service.evaluateJavascript(
      id: webviewId,
      source: 'JSON.stringify(window.localStorage)',
    );
    final localStorage = <String, String>{};
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          localStorage['$key'] = '$value';
        });
      }
    }
    await store.save(PortableSession(
      name: name,
      origin: origin,
      cookies: List.of(cookies),
      localStorage: localStorage,
    ));
  }

  /// Re-applies a named session onto the webview: every cookie is re-set
  /// through the cookie store and every localStorage entry through an
  /// `setItem` evaluation.
  Future<void> load({
    required String webviewId,
    required String name,
  }) async {
    final session = await store.read(name);
    if (session == null) {
      throw WebviewException(
        'session_not_found',
        'No portable session named "$name" — save it before loading.',
        recoverable: true,
      );
    }
    for (final cookie in session.cookies) {
      await service.setCookie(cookie);
    }
    for (final entry in session.localStorage.entries) {
      // JSON string literals are valid JS literals: keys/values coming
      // from the page cannot break out of the literal.
      await service.evaluateJavascript(
        id: webviewId,
        source: 'window.localStorage.setItem('
            '${jsonEncode(entry.key)}, ${jsonEncode(entry.value)})',
      );
    }
  }

  /// Removes the named session from the store.
  Future<void> delete({required String name}) => store.delete(name);

  /// The stored session names.
  Future<List<String>> list() => store.list();
}
