/// Canonical dialogue dismissal for clean captures (spec 002).
///
/// Removes fixed/sticky overlays (cookie banners, chat widgets, sticky
/// navbars) from the top-level document and resets overflow/margin so
/// screenshots and PDF exports carry no scrollbar artifacts. Pure Dart —
/// the script is a payload evaluated through the existing
/// `evaluateJavascript` port op, so no new channel contract is needed.
library;

/// The canonical overlay-removal script.
///
/// Contract (spec 002, FR-2/FR-6): removes every element whose computed
/// position is `fixed` or `sticky` except the two document roots —
/// `documentElement` and `body` may legitimately be `fixed` themselves (the
/// common `body { position: fixed }` scroll-lock used behind modals), and
/// removing them would blank the page while still reporting `removed > 0`.
/// Resets `overflow`/`margin` on those roots instead, touches only the
/// top-level document, and never throws — the whole body is guarded,
/// returning the removed count. Matches are collected before any removal so
/// `getComputedStyle` is not interleaved with DOM mutations.
class DialogueDismissScript {
  const DialogueDismissScript._();

  static const String source = '''
(function () {
  try {
    var removed = 0;
    var all = document.querySelectorAll('*');
    var doomed = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el === document.documentElement || el === document.body) continue;
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') doomed.push(el);
    }
    for (var k = 0; k < doomed.length; k++) {
      doomed[k].remove();
      removed++;
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
