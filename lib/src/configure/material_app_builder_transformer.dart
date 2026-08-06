import 'comment_stripper.dart';
import 'dart_import_utils.dart';

/// Result of attempting to wrap an app root widget's `builder:` with
/// `VibeBugScope`. See [MainDartTransformResult] in `main_dart_transformer.dart`
/// for the same three-state shape.
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

// MaterialApp, CupertinoApp, and GetX's GetMaterialApp/GetCupertinoApp all
// expose the same `builder: (context, child) => Widget` contract (the
// standard WidgetsApp shape), so the same wrap-the-return-value transform
// works for all of them.
final _appRootPattern =
    RegExp(r'\b(MaterialApp|CupertinoApp|GetMaterialApp|GetCupertinoApp)(\.router)?\s*\(');
final _navigatorKeyPattern = RegExp(
  r'navigatorKey\s*:\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)',
);
final _builderPattern = RegExp(r'\bbuilder\s*:');
final _builderHeadPattern = RegExp(
  r'^builder\s*:\s*\(\s*context\s*,\s*child\s*\)\s*(=>|\{)',
  dotAll: true,
);
final _trivialChildPattern = RegExp(r'^child(\s*\?\?\s*.+)?$', dotAll: true);

/// Finds the single app root widget (`MaterialApp`, `MaterialApp.router`,
/// `CupertinoApp`, `GetMaterialApp`, etc.) in [source] and threads
/// `VibeBugScope` into its `builder:`.
///
/// If `builder:` is missing or is a trivial `(context, child) => child`
/// pass-through, inserts/replaces it outright. If it already returns
/// something else — localization wrappers, `ScreenUtilInit`, theme
/// providers, anything — wraps that *return value* with
/// `VibeBugScope(child: ...)` instead of replacing it, so existing app
/// wiring is preserved. Only bails out when it can't safely identify a
/// single return value: multiple/zero app-root usages, multiple return
/// statements in a block-bodied builder, or a builder with unrecognized
/// parameter names.
///
/// All *detection* runs against a comment/string-literal-aware stripped
/// copy of [source] (see [stripCommentsForScanning]), so commented-out code
/// — an old `MaterialApp(...)` left behind, one shown in a doc comment —
/// can never masquerade as a second real occurrence and trigger a false
/// "ambiguous" bail-out. The stripped copy has identical length and newline
/// positions to [source], so its offsets are always valid for slicing the
/// *real* text back out (including any real comments inside the builder)
/// when building the output.
MaterialAppTransformResult transformMaterialAppBuilder(String source) {
  final scan = stripCommentsForScanning(source);

  final appMatches = _appRootPattern.allMatches(scan).toList();
  if (appMatches.isEmpty) {
    return const MaterialAppTransformResult.bailOut(
      'no MaterialApp(...), CupertinoApp(...), or GetMaterialApp(...) found in this file',
    );
  }
  var match = appMatches.first;
  if (appMatches.length > 1) {
    // Multiple app roots (e.g. a main app plus a Picture-in-Picture widget
    // with its own MaterialApp, or a preview/entry-point variant): pick the
    // one that threads a navigatorKey — that is almost always the app's real
    // root — and treat the rest as secondary. Only bail out if that doesn't
    // narrow it down to exactly one.
    final withNavigatorKey = appMatches.where((m) {
      final closeParen = _findMatchingParen(scan, m.end - 1);
      if (closeParen == -1) return false;
      final args = scan.substring(m.end - 1, closeParen);
      return _navigatorKeyPattern.hasMatch(args);
    }).toList();
    if (withNavigatorKey.length == 1) {
      match = withNavigatorKey.first;
    } else {
      return const MaterialAppTransformResult.bailOut(
        'multiple app root widgets found in this file; ambiguous',
      );
    }
  }
  final appName = match.group(1)!;
  final isRouter = match.group(2) != null;
  final openParenIndex = match.end - 1;
  final closeParenIndex = _findMatchingParen(scan, openParenIndex);
  if (closeParenIndex == -1) {
    return MaterialAppTransformResult.bailOut(
      'could not find the end of $appName(...) — unbalanced parens',
    );
  }

  final argsStart = openParenIndex + 1;
  final args = source.substring(argsStart, closeParenIndex);
  final scanArgs = scan.substring(argsStart, closeParenIndex);

  if (scanArgs.contains('VibeBugScope(')) {
    return const MaterialAppTransformResult.alreadyConfigured();
  }

  final navKeyMatch = _navigatorKeyPattern.firstMatch(scanArgs);
  final navKeyArg = navKeyMatch == null ? '' : 'navigatorKey: ${navKeyMatch.group(1)}, ';

  String newArgs;
  final builderMatch = _findTopLevelBuilder(scanArgs);
  if (builderMatch == null) {
    final replacement =
        'builder: (context, child) => VibeBugScope(${navKeyArg}child: child ?? const SizedBox.shrink())';
    newArgs = '\n  $replacement,$args';
  } else {
    final argEnd = _findArgEnd(scanArgs, builderMatch.start);
    final argSpan = args.substring(builderMatch.start, argEnd);
    final scanArgSpan = scanArgs.substring(builderMatch.start, argEnd);
    final rewritten = _rewriteBuilderArg(argSpan, scanArgSpan, navKeyArg);
    if (rewritten == null) {
      return MaterialAppTransformResult.bailOut(
        '$appName\'s builder: has a shape this tool doesn\'t recognize (expected '
        '"(context, child) => ..." or a block body with exactly one return) — '
        'wrap it with VibeBugScope manually',
      );
    }
    newArgs = args.substring(0, builderMatch.start) + rewritten + args.substring(argEnd);
  }

  final warnings = <String>[];
  if (isRouter && navKeyMatch == null) {
    warnings.add(
      "$appName.router detected — for best results, thread your router's "
      'navigatorKey into VibeBugScope (see README)',
    );
  }

  var newSource = source.substring(0, argsStart) + newArgs + source.substring(closeParenIndex);
  newSource = ensureImport(newSource, 'package:vibebug_flutter/vibebug_flutter.dart');

  return MaterialAppTransformResult.success(newSource, warnings: warnings);
}

/// Finds the `builder:` named argument that belongs to the app root widget
/// itself — i.e. the one sitting at argument depth 0 of [args] — rather than
/// one nested inside another widget's argument list (`routes: { ... }`,
/// `onGenerateRoute: (settings) => MaterialPageRoute(builder: ...)`, etc.).
/// Returns null when the app root has no `builder:` of its own.
Match? _findTopLevelBuilder(String args) {
  var depth = 0;
  var i = 0;
  while (i < args.length) {
    final ch = args[i];
    if (ch == '(' || ch == '{' || ch == '[') {
      depth++;
      i++;
      continue;
    }
    if (ch == ')' || ch == '}' || ch == ']') {
      depth--;
      i++;
      continue;
    }
    if (depth == 0) {
      final m = _builderPattern.matchAsPrefix(args, i);
      if (m != null) return m;
    }
    i++;
  }
  return null;
}

/// Rewrites a single `builder: (context, child) => ...` or
/// `builder: (context, child) { ... }` argument span (as isolated by
/// [_findArgEnd], so it has no trailing comma) to wrap its return value
/// with `VibeBugScope`. Returns null if the shape isn't recognized.
///
/// [argSpan] is the real source text (used to build the output, preserving
/// any real comments); [scanArgSpan] is the same span from the
/// comment-stripped copy, at identical offsets, used only to decide
/// structure (where the arrow/brace/return/statement boundaries are).
String? _rewriteBuilderArg(String argSpan, String scanArgSpan, String navKeyArg) {
  final headMatch = _builderHeadPattern.firstMatch(scanArgSpan);
  if (headMatch == null) return null;

  if (headMatch.group(1) == '=>') {
    final expr = argSpan.substring(headMatch.end).trim();
    final scanExpr = scanArgSpan.substring(headMatch.end).trim();
    if (expr.isEmpty) return null;
    return 'builder: (context, child) => ${_wrapExpr(expr, scanExpr, navKeyArg)}';
  }

  // Block body: `builder: (context, child) { ... }`. headMatch consumed the
  // opening `{`; find its matching `}` and require exactly one top-level
  // `return <expr>;` inside — anything else (no return, multiple returns,
  // conditional returns) is ambiguous about which value becomes the app's
  // actual widget, so it's left for the developer to wrap manually.
  final openBraceIndex = headMatch.end - 1;
  final closeBraceIndex = _findMatchingBrace(scanArgSpan, openBraceIndex);
  if (closeBraceIndex == -1) return null;

  final body = argSpan.substring(openBraceIndex + 1, closeBraceIndex);
  final scanBody = scanArgSpan.substring(openBraceIndex + 1, closeBraceIndex);
  final returnStarts = _findTopLevelReturnStarts(scanBody);
  if (returnStarts.length != 1) return null;

  final returnStart = returnStarts.first;
  var exprStart = returnStart + 'return'.length;
  while (exprStart < scanBody.length && scanBody[exprStart].trim().isEmpty) {
    exprStart++;
  }
  final stmtEnd = _findStatementEnd(scanBody, exprStart);
  if (stmtEnd == -1) return null;

  final expr = body.substring(exprStart, stmtEnd).trim();
  final scanExpr = scanBody.substring(exprStart, stmtEnd).trim();
  if (expr.isEmpty) return null;

  final newBody =
      '${body.substring(0, returnStart)}return ${_wrapExpr(expr, scanExpr, navKeyArg)};${body.substring(stmtEnd + 1)}';
  return 'builder: (context, child) {$newBody}';
}

String _wrapExpr(String expr, String scanExpr, String navKeyArg) {
  if (_trivialChildPattern.hasMatch(scanExpr)) {
    return 'VibeBugScope(${navKeyArg}child: child ?? const SizedBox.shrink())';
  }
  return 'VibeBugScope(${navKeyArg}child: $expr)';
}

/// Finds the start index of every `return` keyword in [body] that sits at
/// brace/paren/bracket depth 0 — i.e. a return of the block itself, not one
/// nested inside an inner closure (which would be a different function's
/// return and must be left alone).
List<int> _findTopLevelReturnStarts(String body) {
  final starts = <int>[];
  var depth = 0;
  var i = 0;
  while (i < body.length) {
    final ch = body[i];
    if (ch == '(' || ch == '{' || ch == '[') {
      depth++;
    } else if (ch == ')' || ch == '}' || ch == ']') {
      depth--;
    } else if (depth == 0 && body.startsWith('return', i)) {
      final before = i == 0 ? '' : body[i - 1];
      final afterIndex = i + 6;
      final after = afterIndex < body.length ? body[afterIndex] : ' ';
      if (!_isWordChar(before) && !_isWordChar(after)) {
        starts.add(i);
      }
    }
    i++;
  }
  return starts;
}

bool _isWordChar(String s) => s.isNotEmpty && RegExp(r'\w').hasMatch(s);

/// Finds the top-level `;` that ends the statement starting at [start].
int _findStatementEnd(String body, int start) {
  var depth = 0;
  for (var i = start; i < body.length; i++) {
    final ch = body[i];
    if (ch == '(' || ch == '{' || ch == '[') depth++;
    if (ch == ')' || ch == '}' || ch == ']') depth--;
    if (depth == 0 && ch == ';') return i;
  }
  return -1;
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

int _findMatchingBrace(String source, int openBraceIndex) {
  var depth = 0;
  for (var i = openBraceIndex; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
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
