## [7.2.0] - 2026-10-28

- Mono-version fleet alignment: the whole zuraffa family now ships at the same version as the core.
- `zuraffa` dependency constraint unified to ^7.2.0 across the fleet.
- zuraffa_storage now wraps the maintained `zuraffa_minio` fork instead of the abandoned `minio` package (xml 7 compatible).
- Fleet-wide `dependency_overrides: xml: 7.1.0` policy; README install guides refreshed to the release version.

# Changelog

## 0.1.0

- Initial federated scaffold for `zuraffa_inappwebview` (EPIC #214 migration): the
  app-facing package, the shared `zuraffa_inappwebview_platform` envelope core, and the
  Android, iOS, macOS adapters.
- Clean-capture dialogue dismissal for the app-facing package (spec 002).
- The whole family now resolves on `zuraffa: ^7.0.0`; the adapters had been left on
  `^6.3.0`, which made every package unresolvable (#11).
