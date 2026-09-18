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
/// last two host labels). Caps and TTL keep the pool memory-safe; expiry
/// is swept lazily on acquire (no Flutter lifecycle dependency).
class WebviewPool {
  final WebviewService service;
  final WebviewSettings settings;
  final int maxLive;
  final int maxPerDomain;
  final Duration idleTtl;
  final DateTime Function() clock;

  final List<_PooledInstance> _held = [];
  int _counter = 0;

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

  /// Returns the webview id for [sessionId], creating+running a fresh
  /// headless instance on first acquire. Same session always maps to the
  /// same instance; a warm idle instance on the same registrable domain
  /// (from [domainHint]) is reused across sessions.
  Future<String> acquire(String sessionId, {String? domainHint}) async {
    await _sweepExpired();
    final active = _instanceFor(sessionId);
    if (active != null) return active.webviewId;

    final domain =
        domainHint == null ? null : registrableDomain(domainHint);
    if (domain != null) {
      for (final i in _held) {
        if (i.session == null && i.domain == domain) {
          i.session = sessionId;
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

    if (domain != null) {
      final sameDomain = _held.where((i) => i.domain == domain).length;
      if (sameDomain >= maxPerDomain) {
        // An idle instance of this domain would have been reused by the
        // affinity loop above, so everything counted here is live — the
        // per-domain cap has nothing to evict and only FR-6's fallback
        // applies.
        throw WebviewException(
          'pool_exhausted',
          'Domain "$domain" already holds $maxPerDomain live instances.',
          recoverable: true,
        );
      }
    }

    final id = 'pool-${++_counter}';
    await service.createHeadless(id: id, settings: settings);
    try {
      await service.runHeadless(id: id);
    } catch (_) {
      // The service has already registered the webview, so a failed run
      // must be disposed here or nothing can ever reach it again.
      await service.disposeHeadless(id: id);
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

  /// Disposes every held instance (active and idle). Every instance is
  /// attempted before the first failure is surfaced, so one broken
  /// dispose cannot leave the rest warm.
  Future<void> disposeAll() async {
    Object? firstError;
    for (final inst in List.of(_held)) {
      try {
        await _dispose(inst);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
  }

  /// eTLD+1 approximation: the last two host labels (`shop.x.dev` →
  /// `x.dev`). Single-label hosts and IP literals (`10.0.0.5`, IPv6)
  /// map to themselves — collapsing them would make unrelated hosts
  /// share sessions. Multi-part TLDs (co.uk) are a documented
  /// follow-up.
  static String registrableDomain(String host) {
    if (host.contains(':') || _ipv4Literal.hasMatch(host)) return host;
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    return labels.sublist(labels.length - 2).join('.');
  }

  static final RegExp _ipv4Literal = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

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

  Future<void> _dispose(_PooledInstance inst) async {
    // Forget the instance only once the port has released it: a failed
    // dispose leaves the webview registered with the service, so keeping
    // it here is what makes a retry reachable.
    await service.disposeHeadless(id: inst.webviewId);
    _held.remove(inst);
  }
}

class _PooledInstance {
  final String webviewId;
  final String? domain;
  String? session;
  DateTime idleSince;

  _PooledInstance({
    required this.webviewId,
    required this.domain,
    required this.session,
    required this.idleSince,
  });
}
