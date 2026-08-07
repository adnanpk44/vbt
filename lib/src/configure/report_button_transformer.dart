import 'comment_stripper.dart';

/// Result of attempting to toggle [VibeBugScope.showReportButton] in an
/// already-wired-up file. See [MainDartTransformResult] in
/// `main_dart_transformer.dart` for the same three-state shape.
class ReportButtonTransformResult {
  const ReportButtonTransformResult.success(this.output)
      : bailOutReason = null,
        alreadyConfigured = false;

  const ReportButtonTransformResult.alreadyConfigured()
      : output = null,
        bailOutReason = null,
        alreadyConfigured = true;

  const ReportButtonTransformResult.bailOut(this.bailOutReason)
      : output = null,
        alreadyConfigured = false;

  /// The rewritten source, or null if nothing was changed.
  final String? output;

  /// Why the transform was refused, or null if it succeeded / was already
  /// in the requested state.
  final String? bailOutReason;

  /// True if `VibeBugScope(...)` was already showing/hiding the button as
  /// requested — not an error.
  final bool alreadyConfigured;

  bool get changed => output != null;
}

final _scopePattern = RegExp(r'\bVibeBugScope\s*\(');
final _showReportButtonPattern = RegExp(r'showReportButton\s*:\s*(true|false)');

/// Finds the single `VibeBugScope(...)` usage in [source] and sets its
/// `showReportButton:` argument so it matches [show] — inserting the
/// argument if absent, or replacing an existing `true`/`false` value.
///
/// Powers `dart run vibebug_flutter:configure --hide-report-button` /
/// `--show-report-button`, so the floating Report button can be toggled
/// without a manual code edit. Returns
/// [ReportButtonTransformResult.alreadyConfigured] when the button is
/// already in the requested state (including the implicit default of
/// `true` when no argument is present at all).
///
/// Detection runs against a comment/string-literal-aware stripped copy of
/// [source] (see [stripCommentsForScanning]) for the same reason every
/// other configure transform does: a commented-out `VibeBugScope(...)` must
/// never be mistaken for a real occurrence.
ReportButtonTransformResult setReportButtonVisibility(
  String source, {
  required bool show,
}) {
  final scan = stripCommentsForScanning(source);

  final matches = _scopePattern.allMatches(scan).toList();
  if (matches.isEmpty) {
    return const ReportButtonTransformResult.bailOut(
      'no VibeBugScope(...) found — run `dart run vibebug_flutter:configure` '
      'first, or wrap your app root manually (see README)',
    );
  }
  if (matches.length > 1) {
    return const ReportButtonTransformResult.bailOut(
      'multiple VibeBugScope(...) usages found; edit the showReportButton: '
      'argument manually',
    );
  }

  final match = matches.first;
  final openParenIndex = match.end - 1;
  final closeParenIndex = _findMatchingParen(scan, openParenIndex);
  if (closeParenIndex == -1) {
    return const ReportButtonTransformResult.bailOut(
      'could not find the end of VibeBugScope(...) — unbalanced parens',
    );
  }

  final argsStart = openParenIndex + 1;
  final scanArgs = scan.substring(argsStart, closeParenIndex);
  final args = source.substring(argsStart, closeParenIndex);

  final existing = _showReportButtonPattern.firstMatch(scanArgs);
  final currentlyShown = existing == null ? true : existing.group(1) == 'true';
  if (currentlyShown == show) {
    return const ReportButtonTransformResult.alreadyConfigured();
  }

  final String newArgs;
  if (existing == null) {
    newArgs = 'showReportButton: $show, $args';
  } else {
    newArgs =
        '${args.substring(0, existing.start)}showReportButton: $show${args.substring(existing.end)}';
  }

  final newSource =
      source.substring(0, argsStart) + newArgs + source.substring(closeParenIndex);
  return ReportButtonTransformResult.success(newSource);
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
