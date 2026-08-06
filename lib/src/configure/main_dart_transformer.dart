import 'comment_stripper.dart';
import 'dart_import_utils.dart';

/// Result of attempting to rewrite `main.dart` to wire in VibeBug.
///
/// Kept as a pure function of a source string (see [transformMainDart]) with
/// no file I/O, so the risky part of `dart run vibebug_flutter:configure` —
/// rewriting someone else's source file — is fully unit-testable.
class MainDartTransformResult {
  const MainDartTransformResult.success(this.output)
      : bailOutReason = null,
        alreadyConfigured = false;

  const MainDartTransformResult.alreadyConfigured()
      : output = null,
        bailOutReason = null,
        alreadyConfigured = true;

  const MainDartTransformResult.bailOut(this.bailOutReason)
      : output = null,
        alreadyConfigured = false;

  /// The rewritten source, or null if nothing was changed.
  final String? output;

  /// Why the transform was refused, or null if it succeeded / was already
  /// configured.
  final String? bailOutReason;

  /// True if `main.dart` already wires up VibeBug — not an error.
  final bool alreadyConfigured;

  bool get changed => output != null;
}

final _mainFnPattern = RegExp(
  r'(Future<void>|void)\s+main\s*\([^)]*\)\s*(async\s*)?\{',
  multiLine: true,
);
final _ensureInitializedPattern =
    RegExp(r'WidgetsFlutterBinding\.ensureInitialized\s*\(\s*\)\s*;');
final _runAppPattern = RegExp(r'runApp\s*\(');

/// Rewrites `main()` in [source] so `runApp(...)` runs inside
/// `VibeBug.runGuarded(...)`, with `VibeBug.initialize(...)` awaited just
/// before it. Only ever *inserts* two lines (plus imports) — every other
/// line of the original body is preserved verbatim, including comments and
/// any existing setup (e.g. `Firebase.initializeApp(...)`).
///
/// Bails out (leaving [MainDartTransformResult.bailOutReason] set, and the
/// file untouched by the caller) rather than attempting anything it can't do
/// safely: multiple/zero `main()` functions, multiple/zero `runApp(...)`
/// calls, `runApp(...)` nested inside another callback, or trailing code
/// chained onto the `runApp(...)` statement (e.g. `.then(...)`).
///
/// All *detection* (finding `main()`, `runApp(...)`, counting braces, etc.)
/// runs against a comment/string-literal-aware stripped copy of [source]
/// (see [stripCommentsForScanning]) so commented-out code — an old `main()`
/// left behind, a `// runApp(...)` in a doc example — can never masquerade
/// as a second real occurrence and trigger a false "ambiguous" bail-out.
/// The stripped copy has identical length and newline positions to
/// [source], so its offsets are always valid for slicing the *real* text
/// back out when building the output.
MainDartTransformResult transformMainDart(
  String source, {
  String configImportPath = 'vibebug_config.dart',
}) {
  final scan = stripCommentsForScanning(source);

  final mainMatches = _mainFnPattern.allMatches(scan).toList();
  if (mainMatches.length != 1) {
    return MainDartTransformResult.bailOut(
      'expected exactly one top-level main() function, found ${mainMatches.length}',
    );
  }
  final mainMatch = mainMatches.first;
  final openBraceIndex = mainMatch.end - 1;
  final closeBraceIndex = _findMatchingBrace(scan, openBraceIndex);
  if (closeBraceIndex == -1) {
    return const MainDartTransformResult.bailOut(
      'could not find the end of main() — unbalanced braces',
    );
  }

  final bodyStart = openBraceIndex + 1;
  final body = source.substring(bodyStart, closeBraceIndex);
  final scanBody = scan.substring(bodyStart, closeBraceIndex);

  if (scanBody.contains('VibeBug.runGuarded(')) {
    if (scanBody.contains('VibeBug.initialize(')) {
      return const MainDartTransformResult.alreadyConfigured();
    }
    return const MainDartTransformResult.bailOut(
      'VibeBug.runGuarded() is already present but VibeBug.initialize() was '
      'not found inside it — add "await VibeBug.initialize(...)" before '
      'runApp() manually',
    );
  }

  final runAppMatches = _runAppPattern.allMatches(scanBody).toList();
  if (runAppMatches.length != 1) {
    return MainDartTransformResult.bailOut(
      'expected exactly one runApp(...) call inside main(), found ${runAppMatches.length}',
    );
  }
  final runAppMatch = runAppMatches.first;

  var depth = 0;
  for (var i = 0; i < runAppMatch.start; i++) {
    final ch = scanBody[i];
    if (ch == '(' || ch == '{' || ch == '[') depth++;
    if (ch == ')' || ch == '}' || ch == ']') depth--;
  }
  if (depth != 0) {
    return const MainDartTransformResult.bailOut(
      'runApp() is nested inside another callback; wire VibeBug manually',
    );
  }

  final runAppParenIndex = runAppMatch.end - 1;
  final runAppArgsEnd = _findMatchingParen(scanBody, runAppParenIndex);
  if (runAppArgsEnd == -1) {
    return const MainDartTransformResult.bailOut(
      'could not find the end of the runApp(...) call — unbalanced parens',
    );
  }
  var trailing = runAppArgsEnd + 1;
  while (trailing < scanBody.length && scanBody[trailing].trim().isEmpty) {
    trailing++;
  }
  if (trailing >= scanBody.length || scanBody[trailing] != ';') {
    return const MainDartTransformResult.bailOut(
      'runApp() has unexpected trailing code (e.g. .then(...)); wire VibeBug manually',
    );
  }

  var lineStart = scanBody.lastIndexOf('\n', runAppMatch.start);
  lineStart = lineStart == -1 ? 0 : lineStart + 1;
  final indentMatch = RegExp(r'^[ \t]*').firstMatch(scanBody.substring(lineStart))!;
  final indent = indentMatch.group(0)!;

  final insertion = StringBuffer();
  if (!_ensureInitializedPattern.hasMatch(scanBody)) {
    insertion.write('$indent' r'WidgetsFlutterBinding.ensureInitialized();' '\n');
  }
  insertion.write(
    '$indent'
    'await VibeBug.initialize(VibeBugOptions(baseUrl: VibeBugConfig.baseUrl));'
    '\n',
  );

  final newBody =
      body.substring(0, lineStart) + insertion.toString() + body.substring(lineStart);

  final newMainBlock = '{\n  VibeBug.runGuarded(() async {$newBody  });\n}';
  var newSource =
      source.substring(0, openBraceIndex) + newMainBlock + source.substring(closeBraceIndex + 1);

  newSource = ensureImport(newSource, 'package:vibebug_flutter/vibebug_flutter.dart');
  newSource = ensureImport(newSource, configImportPath);

  return MainDartTransformResult.success(newSource);
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
