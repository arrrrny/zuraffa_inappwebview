/// Mission-scoped headless webview pooling (spec 006): each [sessionId]
/// gets its own webview, sessions on the same registrable domain (eTLD+1
/// approximation: last two host labels) reuse a warm idle instance, and
/// caps (`maxLive`, `maxPerDomain`) plus an idle TTL keep the process
/// memory-safe. Single-label hosts and IP literals map to themselves.
/// Multi-part TLDs (co.uk) are a documented follow-up.
///
/// A reused instance is navigated to `about:blank` first, so it never
/// carries the previous mission's document or JS state. `acquire` is
/// serialised on an internal gate: the caps and the session→instance
/// mapping are checked and mutated with no interleaving `await` in
/// between, so concurrent acquires can neither double-create an instance
/// for one session nor overshoot [maxLive].
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
    this.maxLive = 3,
    this.maxPerDomain = 1,
    this.idleTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// The pool's live (non-disposed) instances.
  int get liveCount => _held.length;

  /// Sessions currently holding an instance.
  List<String> get sessions => <String>[
        for (final i in _held)
          if (i.session != null) i.session!,
      ];

  /// Whether [sessionId] currently holds an instance.
  bool hasSession(String sessionId) => _instanceFor(sessionId) != null;

  /// Returns the webview id for [sessionId], creating+running a fresh
  /// headless instance on first acquire. Same session always maps to the
  /// same instance; a warm idle instance on the same registrable domain
  /// (from [domainHint]) is reused across sessions.
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

    // The reuse loop above already claimed any idle same-domain instance,
    // so every same-domain instance left is active: eviction cannot help
    // and the acquire genuinely exceeds the per-domain cap. Checked BEFORE
    // the maxLive eviction so an acquire that is going to fail leaves the
    // pool untouched instead of first destroying another domain's idle.
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

    final id = 'pool-${++_counter}';
    await service.createHeadless(id: id, settings: settings);
    try {
      await service.runHeadless(id: id);
    } on Object {
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
  /// `x.dev`). Single-label hosts map to themselves. IP literals are
  /// returned verbatim — the last-two-labels rule would collapse
  /// `127.0.0.1` and `10.0.0.1` onto one bucket and hand an unrelated
  /// host a warm instance. Multi-part TLDs (co.uk) are a documented
  /// follow-up.
  static String registrableDomain(String host) {
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    if (_looksLikeIp(host)) return host;
    return labels.sublist(labels.length - 2).join('.');
  }

  /// Whether [host] is an IP literal (v4 or v6, with or without brackets).
  /// Kept dependency-free: the core package has no `dart:io` import.
  static bool _looksLikeIp(String host) {
    final bare = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    if (bare.contains(':')) return true; // IPv6
    final labels = bare.split('.');
    if (labels.length != 4) return false;
    for (final label in labels) {
      if (label.isEmpty || label.length > 3) return false;
      final value = int.tryParse(label);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }

  _PooledInstance? _instanceFor(String sessionId) {
    for (final i in _held) {
      if (i.session == sessionId) return i;
    }
    return null;
  }

  Future<void> _sweepExpired() async {
    final cutoff = clock().subtract(idleTtl);
    final expired = _held
        .where((i) => i.session == null && i.idleSince.isBefore(cutoff))
        .toList(growable: false);
    for (final inst in expired) {
      try {
        await _dispose(inst);
      } on Object {
        // A failed sweep dispose must not abort the acquire; the instance
        // stays held and is retried on the next sweep.
      }
    }
  }

  _PooledInstance? _idlest(Iterable<_PooledInstance> candidates) {
    _PooledInstance? best;
    for (final c in candidates) {
      if (best == null || c.idleSince.isBefore(best.idleSince)) best = c;
    }
    return best;
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
