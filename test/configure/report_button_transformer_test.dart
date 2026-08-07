import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/configure/report_button_transformer.dart';

void main() {
  test('inserts showReportButton: false when no argument exists', () {
    const source = '''
builder: (context, child) => VibeBugScope(
  child: child ?? const SizedBox.shrink(),
),
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.changed, isTrue);
    expect(result.bailOutReason, isNull);
    expect(result.output, contains('VibeBugScope(showReportButton: false,'));
    expect(result.output, contains('child: child ?? const SizedBox.shrink()'));
  });

  test('requesting show:true with no existing argument is already configured', () {
    const source = '''
VibeBugScope(
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: true);

    expect(result.alreadyConfigured, isTrue);
    expect(result.changed, isFalse);
  });

  test('flips an existing showReportButton: false to true', () {
    const source = '''
VibeBugScope(
  showReportButton: false,
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: true);

    expect(result.changed, isTrue);
    expect(result.output, contains('showReportButton: true'));
    expect(result.output, isNot(contains('showReportButton: false')));
  });

  test('flips an existing showReportButton: true to false', () {
    const source = '''
VibeBugScope(
  showReportButton: true,
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.changed, isTrue);
    expect(result.output, contains('showReportButton: false'));
  });

  test('already hidden stays already configured', () {
    const source = '''
VibeBugScope(
  showReportButton: false,
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.alreadyConfigured, isTrue);
    expect(result.changed, isFalse);
  });

  test('preserves a leading navigatorKey argument when inserting', () {
    const source = '''
VibeBugScope(
  navigatorKey: _navigatorKey,
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.changed, isTrue);
    expect(result.output, contains('showReportButton: false, '));
    expect(result.output, contains('navigatorKey: _navigatorKey'));
  });

  test('bails out when no VibeBugScope(...) is found', () {
    const source = '''
MaterialApp(
  home: const HomePage(),
)
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('no VibeBugScope'));
  });

  test('bails out when multiple VibeBugScope(...) usages are found', () {
    const source = '''
Widget buildA() => VibeBugScope(child: const A());
Widget buildB() => VibeBugScope(child: const B());
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('multiple VibeBugScope'));
  });

  test('ignores a commented-out VibeBugScope( left behind in the file', () {
    const source = '''
// return VibeBugScope(child: const OldHomePage());

VibeBugScope(
  child: child ?? const SizedBox.shrink(),
)
''';
    final result = setReportButtonVisibility(source, show: false);

    expect(result.bailOutReason, isNull);
    expect(result.changed, isTrue);
  });

  test('is idempotent — re-running on its own output reports alreadyConfigured', () {
    const source = '''
VibeBugScope(
  child: child ?? const SizedBox.shrink(),
)
''';
    final first = setReportButtonVisibility(source, show: false);
    final second = setReportButtonVisibility(first.output!, show: false);

    expect(second.alreadyConfigured, isTrue);
    expect(second.changed, isFalse);
  });
}
