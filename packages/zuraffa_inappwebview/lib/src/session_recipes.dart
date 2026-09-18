/// Session recipes (spec 007): record a user flow (url visits + taps),
/// replay it against any [RecipeDriver].
library;

import 'dart:async';

import 'navigation_tracking.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// One recorded step of a flow.
sealed class RecipeStep {
  const RecipeStep();
}

/// A completed main-frame navigation.
class RecipeUrlStep extends RecipeStep {
  final String url;

  const RecipeUrlStep({required this.url});
}

/// A tap on a CSS selector.
class RecipeTapStep extends RecipeStep {
  final String selector;

  const RecipeTapStep({required this.selector});
}

/// A named, ordered user flow.
class SessionRecipe {
  final String name;
  final List<RecipeStep> steps;

  const SessionRecipe({required this.name, this.steps = const []});
}

/// Where a replayed flow lands: webview or any scripted surface.
abstract class RecipeDriver {
  Future<void> loadUrl(Uri url);
  Future<void> tap(String selector);
}

/// Records a flow into a [SessionRecipe] (spec 007). Completed
/// main-frame navigation events become url steps; taps are recorded
/// explicitly by the caller (`recordTap`).
class RecipeRecorder {
  final String name;
  final List<RecipeStep> _steps = [];
  final Map<String, StreamSubscription<WebviewNavigationEvent>> _subs = {};

  RecipeRecorder({required this.name});

  /// Records completed main-frame visits from the webview's event stream.
  void attach(String id, Stream<WebviewNavigationEvent> events) {
    _subs[id]?.cancel();
    _subs[id] = events.listen((e) => handleEvent(id, e));
  }

  /// Stops recording (keeps the steps accumulated so far).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Records one navigation event — only completed main-frame visits
  /// become steps.
  void handleEvent(String id, WebviewNavigationEvent event) {
    if (event.phase == WebviewNavigationPhase.completed && event.isMainFrame) {
      _steps.add(RecipeUrlStep(url: event.url));
    }
  }

  /// Records a tap on [selector].
  void recordTap(String selector) {
    _steps.add(RecipeTapStep(selector: selector));
  }

  /// Freezes the recording into a recipe.
  SessionRecipe finish() => SessionRecipe(name: name, steps: List.of(_steps));
}

/// Progress of one replay step (zero-based [stepIndex] of [total]).
class ReplayProgress {
  final int stepIndex;
  final int total;

  const ReplayProgress({required this.stepIndex, required this.total});
}

/// Outcome of a replay.
class ReplayResult {
  final bool completed;
  final int stepsDriven;
  final int? failedStep;
  final Object? error;

  const ReplayResult({
    required this.completed,
    required this.stepsDriven,
    this.failedStep,
    this.error,
  });
}

/// Drives [recipe] through [driver], step by step in order. Driver
/// failures are captured into a failed [ReplayResult] — replay never
/// throws.
Future<ReplayResult> replay(
  SessionRecipe recipe,
  RecipeDriver driver, {
  void Function(ReplayProgress progress)? onProgress,
}) async {
  final total = recipe.steps.length;
  for (var i = 0; i < total; i++) {
    onProgress?.call(ReplayProgress(stepIndex: i, total: total));
    final step = recipe.steps[i];
    try {
      switch (step) {
        case RecipeUrlStep(:final url):
          await driver.loadUrl(Uri.parse(url));
        case RecipeTapStep(:final selector):
          await driver.tap(selector);
      }
    } catch (e) {
      return ReplayResult(
        completed: false,
        stepsDriven: i,
        failedStep: i,
        error: e,
      );
    }
  }
  return ReplayResult(completed: true, stepsDriven: total);
}

/// [RecipeDriver] over [WebviewService] (spec 007 US3): loads validated
/// urls and clicks selectors via the canonical tap script.
class WebviewServiceRecipeDriver implements RecipeDriver {
  final WebviewService service;
  final String webviewId;

  const WebviewServiceRecipeDriver({
    required this.service,
    required this.webviewId,
  });

  @override
  Future<void> loadUrl(Uri url) => service.loadUrl(
        id: webviewId,
        url: WebviewUri(url.toString()),
      );

  @override
  Future<void> tap(String selector) => service.evaluateJavascript(
        id: webviewId,
        source:
            "(document.querySelector(${_quote(selector)}) ?? {click: null}).click()",
      );

  static String _quote(String raw) => "'${raw.replaceAll("'", r"\'")}'";
}
