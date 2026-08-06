import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/configure/material_app_builder_transformer.dart';

void main() {
  test('inserts builder: as the first argument when none exists', () {
    const source = '''
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      home: const HomePage(),
    );
  }
}
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.bailOutReason, isNull);
    expect(result.output, contains('builder: (context, child) => VibeBugScope('));
    expect(result.output, contains("child: child ?? const SizedBox.shrink()"));
    expect(result.output, contains("title: 'My App',"));
    expect(result.output, contains("import 'package:vibebug_flutter/vibebug_flutter.dart';"));
  });

  test('replaces a trivial pass-through builder', () {
    const source = '''
Widget build(BuildContext context) {
  return MaterialApp(
    builder: (context, child) => child ?? const SizedBox.shrink(),
    home: const HomePage(),
  );
}
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('VibeBugScope('));
    // Only one builder: parameter should remain.
    expect('builder:'.allMatches(result.output!).length, 1);
  });

  test('threads an existing navigatorKey into VibeBugScope', () {
    const source = '''
MaterialApp(
  navigatorKey: _navigatorKey,
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('navigatorKey: _navigatorKey'));
    expect(result.output, contains('VibeBugScope(navigatorKey: _navigatorKey,'));
  });

  test('bails out on a non-trivial existing builder', () {
    const source = '''
MaterialApp(
  builder: (context, child) {
    return Directionality(textDirection: TextDirection.ltr, child: child!);
  },
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('custom builder'));
  });

  test('bails out when MaterialApp is not found', () {
    const result = 'Widget build(BuildContext context) => const SizedBox();';
    final transformed = transformMaterialAppBuilder(result);

    expect(transformed.changed, isFalse);
    expect(transformed.bailOutReason, contains('no MaterialApp'));
  });

  test('bails out when multiple MaterialApp usages are found', () {
    const source = '''
Widget buildA() => MaterialApp(home: const A());
Widget buildB() => MaterialApp(home: const B());
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('multiple MaterialApp'));
  });

  test('is idempotent — re-running on its own output reports alreadyConfigured', () {
    const source = '''
MaterialApp(
  home: const HomePage(),
)
''';
    final first = transformMaterialAppBuilder(source);
    final second = transformMaterialAppBuilder(first.output!);

    expect(second.alreadyConfigured, isTrue);
    expect(second.changed, isFalse);
  });

  test('warns when MaterialApp.router has no navigatorKey to thread', () {
    const source = '''
MaterialApp.router(
  routerConfig: router,
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.warnings, isNotEmpty);
    expect(result.warnings.first, contains('navigatorKey'));
  });
}
