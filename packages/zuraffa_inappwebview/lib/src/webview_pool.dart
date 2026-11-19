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

  /// In-flight acquires keyed by session, so overlapping callers for one
  /// session join the first instead of racing it (SC-1).
  final Map<String, Future<String>> _pending = {};
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
  /// (from [domainHint]) is reused across sessions. Concurrent acquires
  /// for one session share a single in-flight future.
  Future<String> acquire(String sessionId, {String? domainHint}) {
    final active = _instanceFor(sessionId);
    if (active != null) return Future.value(active.webviewId);
    // The future is registered before `_acquireNew` first awaits, so an
    // overlapping call for the same session joins it rather than stopping
    // at the same "no instance yet" check and minting a second one.
    return _pending.putIfAbsent(
      sessionId,
      () => _acquireNew(sessionId, domainHint: domainHint).whenComplete(() {
        // Block body on purpose: an arrow body would return the stored
        // future — the one whose completion this callback belongs to — and
        // `whenComplete` awaits a returned future, deadlocking the acquire.
        _pending.remove(sessionId);
      }),
    );
  }

  Future<String> _acquireNew(String sessionId, {String? domainHint}) async {
    await _sweepExpired();

    final domain =
        domainHint == null ? null : registrableDomain(domainHint);
    if (domain != null) {
      // The cap is decided before the affinity scan: an idle instance may
      // only be handed over while its domain sits below `maxPerDomain`,
      // and one at cap evicts that domain's idlest first (FR-6).
      final sameDomain = _held.where((i) => i.domain == domain).toList();
      if (sameDomain.length >= maxPerDomain) {
        final idle = _idlest(sameDomain.where((i) => i.session == null));
        if (idle == null) {
          throw WebviewException(
            'pool_exhausted',
            'Domain "$domain" already holds $maxPerDomain live instances.',
            recoverable: true,
          );
        }
        await _dispose(idle);
      } else {
        for (final i in sameDomain) {
          if (i.session == null) {
            i.session = sessionId;
            return i.webviewId;
          }
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

    final id = 'pool-${++_counter}';
    await service.createHeadless(id: id, settings: settings);
    try {
      await service.runHeadless(id: id);
    } catch (_) {
      // Nothing else holds this id yet: without this the webview stays
      // created on the platform with no path back to a caller.
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

  /// Disposes every held instance (active and idle).
  ///
  /// Every instance is attempted even when one fails — teardown is the one
  /// place a partial result is worst — and the failures are reported
  /// together once the sweep finishes (SC-4).
  Future<void> disposeAll() async {
    final failures = <String>[];
    for (final inst in List.of(_held)) {
      try {
        await _dispose(inst);
      } catch (_) {
        failures.add(inst.webviewId);
      }
    }
    if (failures.isNotEmpty) {
      throw WebviewException(
        'pool_teardown_incomplete',
        'Failed to dispose: ${failures.join(', ')}',
        recoverable: true,
      );
    }
  }

  /// eTLD+1 approximation: the last two host labels (`shop.x.dev` →
  /// `x.dev`). Multi-part TLDs (co.uk) are a documented follow-up.
  ///
  /// The input is normalized first — scheme, user-info, port, path, query
  /// and fragment are stripped and the host is lowercased, since DNS names
  /// are case-insensitive. IP literals and single-label hosts map to
  /// themselves: last-two-labels is meaningless for them, and collapsing
  /// `192.168.1.10` and `10.0.1.10` both to `1.10` would hand a webview
  /// logged into one server to a mission targeting an unrelated one.
  static String registrableDomain(String host) {
    var h = host.trim();
    final scheme = h.indexOf('://');
    if (scheme != -1) h = h.substring(scheme + 3);
    final authorityEnd = h.indexOf(RegExp(r'[/?#]'));
    if (authorityEnd != -1) h = h.substring(0, authorityEnd);
    final userInfo = h.lastIndexOf('@');
    if (userInfo != -1) h = h.substring(userInfo + 1);
    if (h.startsWith('[')) {
      final close = h.indexOf(']'); // IPv6 literal: keep the address
      h = close == -1 ? h : h.substring(0, close + 1);
    } else {
      final port = h.indexOf(':');
      if (port != -1) h = h.substring(0, port);
    }
    h = h.toLowerCase();
    if (h.isEmpty || !h.contains('.') || _ipv4.hasMatch(h)) return h;
    final labels = h.split('.');
    return labels.sublist(labels.length - 2).join('.');
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

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
    // Deregister only once the platform has let go: if the dispose throws,
    // the record still describes a webview that exists, so liveCount,
    // sessions() and the sweep keep counting it instead of leaking it.
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
