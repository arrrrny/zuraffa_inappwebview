/// JavaScript literal rendering: `jsonEncode` emits a JSON string
/// literal, which is also a valid JS string literal, so the package
/// hand-rolls no escaping of its own.
library;

import 'dart:convert';

/// Renders [raw] as a JS string literal for an injected script.
///
/// The single escaper in the package — every generated script (the
/// portable-session `setItem` call, the recipe tap) goes through here so
/// the two cannot drift. A hand-rolled `'`-only escape silently corrupts
/// ordinary values (backslashes, newlines) and injects code on a hostile
/// one.
String jsStringLiteral(String raw) => jsonEncode(raw);
