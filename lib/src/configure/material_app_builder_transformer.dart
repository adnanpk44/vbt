import 'dart_import_utils.dart';

/// Result of attempting to wrap a `MaterialApp`/`MaterialApp.router`'s
/// `builder:` with `VibeBugScope`. See [MainDartTransformResult] in
/// `main_dart_transformer.dart` for the same three-state shape.
class MaterialAppTransformResult {
  const MaterialAppTransformResult.success(this.output, {this.warnings = const []})
      : bailOutReason = null,
        alreadyConfigured = false;

  const MaterialAppTransformResult.alreadyConfigured()
      : output = null,
        bailOutReason = null,
        alreadyConfigured = true,
        warnings = const [];

  const MaterialAppTransformResult.bailOut(this.bailOutReason)
      : output = null,
        alreadyConfigured = false,
        warnings = const [];

  final String? output;
  final String? bailOutReason;
  final bool alreadyConfigured;
  final List<String> warnings;

  bool get changed => output != null;
}

final _materialAppPattern = RegExp(r'\bMaterialApp(\.router)?\s*\(');
final _navigatorKeyPattern = RegExp(r'navigatorKey\s*:\s*([A-Za-z_]\w*)');
final _builderPattern = RegExp(r'\bbuilder\s*:');
// Matched against a single already-isolated argument span (see _findArgEnd),
// so it's safe to use a greedy `.+` for the optional default value without
// risking it swallowing the next named argument.
final _trivialBuilderPattern = RegExp(
  r'^builder\s*:\s*\(\s*context\s*,\s*child\s*\)\s*=>\s*child(\s*\?\?\s*.+)?$',
  dotAll: true,
);

/// Finds the single `MaterialApp(...)`/`MaterialApp.router(...)` call in
/// [source] and threads a `VibeBugScope`-wrapping `builder:` into it.
///
/// Bails out on anything ambiguous or already customized: zero or multiple
/// `MaterialApp` usages, or an existing non-trivial `builder:` that isn't a
/// simple `(context, child) => child` pass-through.
MaterialAppTransformResult transformMaterialAppBuilder(String source) {
  final appMatches = _materialAppPattern.allMatches(source).toList();
  if (appMatches.isEmpty) {
    return const MaterialAppTransformResult.bailOut(
      'no MaterialApp(...) or MaterialApp.router(...) found in this file',
    );
  }
  if (appMatches.length > 1) {
    return const MaterialAppTransformResult.bailOut(
      'multiple MaterialApp usages found in this file; ambiguous',
    );
  }
  final match = appMatches.first;
  final isRouter = match.group(1) != null;
  final openParenIndex = match.end - 1;
  final closeParenIndex = _findMatchingParen(source, openParenIndex);
  if (closeParenIndex == -1) {
    return const MaterialAppTransformResult.bailOut(
      'could not find the end of MaterialApp(...) — unbalanced parens',
    );
  }

  final argsStart = openParenIndex + 1;
  final args = source.substring(argsStart, closeParenIndex);

  if (args.contains('VibeBugScope(')) {
    return const MaterialAppTransformResult.alreadyConfigured();
  }

  final navKeyMatch = _navigatorKeyPattern.firstMatch(args);
  final navKeyArg = navKeyMatch == null ? '' : 'navigatorKey: ${navKeyMatch.group(1)}, ';

  final warnings = <String>[];
  String newArgs;
  final builderMatch = _builderPattern.firstMatch(args);
  final replacement =
      'builder: (context, child) => VibeBugScope($navKeyArg child: child ?? const SizedBox.shrink())';
  if (builderMatch == null) {
    newArgs = '\n  $replacement,$args';
  } else {
    // Isolate this one named argument's full span (up to its top-level
    // trailing comma) before checking its shape, so the "trivial" regex
    // can't accidentally run past this argument into the next one.
    final argEnd = _findArgEnd(args, builderMatch.start);
    final argSpan = args.substring(builderMatch.start, argEnd).trim();
    if (!_trivialBuilderPattern.hasMatch(argSpan)) {
      return const MaterialAppTransformResult.bailOut(
        'MaterialApp already has a custom builder: — wrap it with VibeBugScope manually',
      );
    }
    newArgs = args.substring(0, builderMatch.start) + replacement + args.substring(argEnd);
  }

  if (isRouter && navKeyMatch == null) {
    warnings.add(
      "MaterialApp.router detected — for best results, thread your router's "
      'navigatorKey into VibeBugScope (see README)',
    );
  }

  var newSource = source.substring(0, argsStart) + newArgs + source.substring(closeParenIndex);
  newSource = ensureImport(newSource, 'package:vibebug_flutter/vibebug_flutter.dart');

  return MaterialAppTransformResult.success(newSource, warnings: warnings);
}

/// Finds the top-level comma that ends the named argument starting at
/// [start] within [args] (or the end of [args] if it's the last argument,
/// i.e. has no trailing comma).
int _findArgEnd(String args, int start) {
  var depth = 0;
  for (var i = start; i < args.length; i++) {
    final ch = args[i];
    if (ch == '(' || ch == '{' || ch == '[') depth++;
    if (ch == ')' || ch == '}' || ch == ']') depth--;
    if (depth == 0 && ch == ',') return i;
  }
  return args.length;
}

int _findMatchingParen(String text, int openParenIndex) {
  var depth = 0;
  for (var i = openParenIndex; i < text.length; i++) {
    final ch = text[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
