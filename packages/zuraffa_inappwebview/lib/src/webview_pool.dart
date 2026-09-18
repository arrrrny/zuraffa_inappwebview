import 'webview_exception.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// Mission-scoped webview sessions over [WebviewService] (spec 006).
///
/// Agent tool sequences are stateful (browse → intercept → execute JS →
/// cookies); keying instances by session handle — not URL — keeps state
/// consistent per mission and stops parallel missions from leaking
/// webviews. Released instances stay warm (idle) and are reused by the
/// next session on the same registrable domain (eTLD+1 approximation:
/// last two host labels); a reused instance is navigated to `about:blank`
/// first so it never carries the previous mission's document or JS state.
/// Caps and TTL keep the pool memory-safe; expiry is swept lazily on
/// acquire (no Flutter lifecycle dependency).
///
/// [acquire] is serialised on an internal gate: the pool caps and the
/// session→instance mapping are checked and mutated with no interleaving
/// `await` in between, so concurrent acquires can neither double-create an
/// instance for one session nor overshoot [maxLive].
class WebviewPool {
  final WebviewService service;
  final WebviewSettings settings;
  final int maxLive;
  final int maxPerDomain;
  final Duration idleTtl;
  final DateTime Function() clock;

  final List<_PooledInstance> _held = [];
  int _counter = 0;
  Future<void> _gate = Future<void>.value();

  WebviewPool({
    required this.service,
    this.settings = const WebviewSettings(),
    this.maxLive = 8,
    this.maxPerDomain = 2,
    this.idleTtl = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Number of instances currently held (active sessions + warm idles).
  int get liveCount => _held.length;

  /// The active session ids.
  Set<String> sessions() => {
        for (final i in _held)
          if (i.session != null) i.session!,
      };

  /// Whether [sessionId] currently holds an instance. Tools use this to
  /// reject an unknown (typo'd or already-released) session with a typed
  /// failure instead of silently acquiring a blank instance for it.
  bool hasSession(String sessionId) => _instanceFor(sessionId) != null;

  /// Returns the webview id for [sessionId], creating+running a fresh
  /// headless instance on first acquire. Same session always maps to the
  /// same instance; a warm idle instance on the same registrable domain
  /// (from [domainHint]) is reused across sessions.
  ///
  /// Concurrent calls are serialised — see the class doc.
  Future<String> acquire(String sessionId, {String? domainHint}) {
    final result = _gate.then((_) => _acquireNow(sessionId, domainHint));
    _gate = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> _acquireNow(String sessionId, String? domainHint) async {
    await _sweepExpired();

    final domain =
        domainHint == null ? null : registrableDomain(domainHint);
    final active = _instanceFor(sessionId);
    if (active != null) {
      if (domain != null) active.domain = domain;
      return active.webviewId;
    }

    if (domain != null) {
      for (final i in _held) {
        if (i.session == null && i.domain == domain) {
          await service.loadUrl(
            id: i.webviewId,
            url: WebviewUri('about:blank'),
          );
          i.session = sessionId;
          i.idleSince = clock();
          return i.webviewId;
        }
      }
    }

    if (_held.length >= maxLive) {
      final idle = _idlest(_held.where((i) => i.session == null));
      if (idle == null) {
        throw WebviewException(
          'pool_exhausted',
          'The pool holds $maxLive live instances and none are idle — '
          'release a session before acquiring.',
          recoverable: true,
        );
      }
      await _dispose(idle);
    }

    // The reuse loop above already claimed any idle same-domain instance,
    // so every same-domain instance left is active: eviction cannot help
    // and the acquire genuinely exceeds the per-domain cap.
    if (domain != null) {
      final sameDomain = _held.where((i) => i.domain == domain).length;
      if (sameDomain >= maxPerDomain) {
        throw WebviewException(
          'pool_exhausted',
          'Domain "$domain" already holds $maxPerDomain live instances — '
          'release one before acquiring.',
          recoverable: true,
        );
      }
    }

    final id = 'pool-${++_counter}';
    await service.createHeadless(id: id, settings: settings);
    try {
      await service.runHeadless(id: id);
    } on Object {
      await _disposeUnstarted(id);
      rethrow;
    }
    _held.add(_PooledInstance(
      webviewId: id,
      domain: domain,
      session: sessionId,
      idleSince: clock(),
    ));
    return id;
  }

  /// Returns the session's instance to the pool as a warm idle. Releasing
  /// an unknown session is a no-op.
  Future<void> release(String sessionId) async {
    final inst = _instanceFor(sessionId);
    if (inst == null) return;
    inst.session = null;
    inst.idleSince = clock();
  }

  /// Disposes every held instance (active and idle).
  Future<void> disposeAll() async {
    for (final inst in List.of(_held)) {
      await _dispose(inst);
    }
  }

  /// eTLD+1 approximation: the last two host labels (`shop.x.dev` →
  /// `x.dev`). Single-label hosts map to themselves. Multi-part TLDs
  /// (co.uk) are a documented follow-up.
  static String registrableDomain(String host) {
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    return labels.sublist(labels.length - 2).join('.');
  }

  _PooledInstance? _instanceFor(String sessionId) {
    for (final i in _held) {
      if (i.session == sessionId) return i;
    }
    return null;
  }

  _PooledInstance? _idlest(Iterable<_PooledInstance> candidates) {
    _PooledInstance? idlest;
    for (final i in candidates) {
      if (idlest == null || i.idleSince.isBefore(idlest.idleSince)) {
        idlest = i;
      }
    }
    return idlest;
  }

  Future<void> _sweepExpired() async {
    final now = clock();
    final expired = _held
        .where((i) =>
            i.session == null &&
            now.difference(i.idleSince) > idleTtl)
        .toList();
    for (final i in expired) {
      await _dispose(i);
    }
  }

  /// Disposes a created-but-never-registered instance, swallowing a
  /// secondary disposal failure so the original one still propagates.
  Future<void> _disposeUnstarted(String webviewId) async {
    try {
      await service.disposeHeadless(id: webviewId);
    } on Object {
      // The failure that stopped the acquire is the one worth reporting.
    }
  }

  Future<void> _dispose(_PooledInstance inst) async {
    _held.remove(inst);
    await service.disposeHeadless(id: inst.webviewId);
  }
}

class _PooledInstance {
  final String webviewId;
  String? domain;
  String? session;
  DateTime idleSince;

  _PooledInstance({
    required this.webviewId,
    required this.domain,
    required this.session,
    required this.idleSince,
  });
}
