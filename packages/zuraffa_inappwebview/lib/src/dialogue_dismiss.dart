/// Canonical dialogue dismissal for clean captures (spec 002).
///
/// Hides fixed/sticky overlays (cookie banners, chat widgets, sticky
/// navbars) in the top-level document and resets overflow/margin so
/// screenshots and PDF exports carry no scrollbar artifacts. Hiding is
/// reversible — unlike removal it cannot erase a content-bearing container
/// (an SPA root is often `position: fixed`). Pure Dart — the script is a
/// payload evaluated through the existing `evaluateJavascript` port op, so
/// no new channel contract is needed.
library;

/// The canonical overlay-hiding script.
///
/// Contract (spec 002, FR-2/FR-6): hides every element whose computed
/// position is `fixed` or `sticky` (`display: none`), resets
/// `overflow`/`margin` on `documentElement` and `body`, touches only the
/// top-level document, and never throws — the whole body is guarded,
/// returning the count of elements taken out of the capture.
class DialogueDismissScript {
  const DialogueDismissScript._();

  static const String source = '''
(function () {
  try {
    var removed = 0;
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') {
        el.style.setProperty('display', 'none');
        removed++;
      }
    }
    var roots = [document.documentElement, document.body];
    for (var j = 0; j < roots.length; j++) {
      if (!roots[j]) continue;
      roots[j].style.overflow = '';
      roots[j].style.margin = '';
    }
    return removed;
  } catch (e) {
    return 0;
  }
})()
''';
}

/// Retry policy for dismissing late-loading overlays (spec 002, FR-7).
///
/// [attempts] is clamped to at least 1; [delay] runs between attempts.
class DialogueDismissPolicy {
  final int attempts;
  final Duration delay;

  const DialogueDismissPolicy({
    int attempts = 1,
    this.delay = Duration.zero,
  }) : attempts = attempts < 1 ? 1 : attempts;
}
