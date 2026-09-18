/// Canonical dialogue dismissal for clean captures (spec 002).
///
/// Removes fixed/sticky overlays (cookie banners, chat widgets, sticky
/// navbars) from the top-level document and forces overflow/margin on the
/// document roots past stylesheet rules so screenshots and PDF exports
/// carry no scrollbar artifacts. Pure Dart — the script is a payload
/// evaluated through the existing `evaluateJavascript` port op, so no new
/// channel contract is needed.
library;

/// The canonical overlay-removal script.
///
/// Contract (spec 002, FR-2/FR-6): removes every element whose computed
/// position is `fixed` or `sticky`, overrides `overflow`/`margin` on
/// `documentElement` and `body`, touches only the top-level document, and
/// never throws — the whole body is guarded, returning the removed count.
///
/// Two costs callers should know about:
///
/// * **Removal is destructive.** `el.remove()` detaches nodes that SPA
///   renderers still track — React's reconciler can later throw
///   `NotFoundError: Failed to execute 'removeChild'` when it unmounts a
///   subtree removed underneath it. That is fine for the headless
///   capture-and-discard flow this repo targets (spec 002 pins it), but a
///   caller that keeps interacting with the page should hide instead
///   (`el.style.display = 'none'`).
/// * **The scan is O(document).** `querySelectorAll('*')` plus one
///   `getComputedStyle` read per element forces a style recalc across every
///   node — tens of ms on a multi-thousand-element page, right before a
///   capture you want fast. Nodes already detached by an earlier removal are
///   skipped, so the count never double-counts a removed overlay's
///   descendants.
class DialogueDismissScript {
  const DialogueDismissScript._();

  static const String source = '''
(function () {
  try {
    var removed = 0;
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (!el.isConnected) continue;
      var pos = window.getComputedStyle(el).position;
      if (pos === 'fixed' || pos === 'sticky') {
        el.remove();
        removed++;
      }
    }
    var roots = [document.documentElement, document.body];
    for (var j = 0; j < roots.length; j++) {
      if (!roots[j]) continue;
      roots[j].style.setProperty('overflow', 'auto', 'important');
      roots[j].style.setProperty('margin', '0', 'important');
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
