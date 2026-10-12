# Changelog

## 0.1.0

- Initial federated scaffold for `zuraffa_inappwebview` (EPIC #214 migration): the
  app-facing package, the shared `zuraffa_inappwebview_platform` envelope core, and the
  Android, iOS, macOS adapters.
- Clean-capture dialogue dismissal for the app-facing package (spec 002).
- The whole family now resolves on `zuraffa: ^7.0.0`; the adapters had been left on
  `^6.3.0`, which made every package unresolvable (#11).
