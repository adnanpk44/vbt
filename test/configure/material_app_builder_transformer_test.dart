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

  test('wraps the return value of a block-bodied builder with a single return', () {
    const source = '''
MaterialApp(
  builder: (context, child) {
    return Directionality(textDirection: TextDirection.ltr, child: child!);
  },
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.bailOutReason, isNull);
    expect(
      result.output,
      contains('return VibeBugScope(child: Directionality(textDirection: TextDirection.ltr, child: child!));'),
    );
  });

  test('wraps the return value of a real-world multi-statement block builder', () {
    const source = '''
MaterialApp(
  builder: (context, child) {
    final mediaQuery = MediaQuery.of(context);
    return ScreenUtilInit(
      builder: (context, _) => MediaQuery(
        data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
        child: EasyLocalization.of(context)!.delegates.isEmpty ? child! : child!,
      ),
    );
  },
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    // The statement before the return is untouched.
    expect(result.output, contains('final mediaQuery = MediaQuery.of(context);'));
    // The returned widget tree is wrapped, not replaced.
    expect(result.output, contains('return VibeBugScope(child: ScreenUtilInit('));
    expect(result.output, contains("data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),"));
  });

  test('wraps a non-trivial arrow-form builder return value', () {
    const source = '''
MaterialApp(
  builder: (context, child) => ResponsiveWrapper.builder(child),
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('builder: (context, child) => VibeBugScope(child: ResponsiveWrapper.builder(child))'));
  });

  test('bails out on a block builder with multiple return statements', () {
    const source = '''
MaterialApp(
  builder: (context, child) {
    if (child == null) return const SizedBox();
    return Directionality(textDirection: TextDirection.ltr, child: child);
  },
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('shape this tool doesn\'t recognize'));
  });

  test('supports GetMaterialApp', () {
    const source = '''
GetMaterialApp(
  title: 'My App',
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('builder: (context, child) => VibeBugScope('));
  });

  test('supports CupertinoApp with an existing non-trivial builder', () {
    const source = '''
CupertinoApp(
  builder: (context, child) => CupertinoTheme(data: theme, child: child!),
  home: const HomePage(),
)
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('VibeBugScope(child: CupertinoTheme(data: theme, child: child!))'));
  });

  test('bails out when no app root widget is found', () {
    const result = 'Widget build(BuildContext context) => const SizedBox();';
    final transformed = transformMaterialAppBuilder(result);

    expect(transformed.changed, isFalse);
    expect(transformed.bailOutReason, contains('no MaterialApp'));
  });

  test('bails out when multiple app root widgets are found', () {
    const source = '''
Widget buildA() => MaterialApp(home: const A());
Widget buildB() => MaterialApp(home: const B());
''';
    final result = transformMaterialAppBuilder(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('multiple app root widgets'));
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
