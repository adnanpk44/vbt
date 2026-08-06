import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/configure/main_dart_transformer.dart';

void main() {
  test('wraps a simple sync main() with ensureInitialized already present', () {
    const source = '''
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isTrue);
    expect(result.bailOutReason, isNull);
    final output = result.output!;
    expect(output, contains('VibeBug.runGuarded(() async {'));
    expect(output,
        contains('await VibeBug.initialize(VibeBugOptions(baseUrl: VibeBugConfig.baseUrl));'));
    expect(output, contains('runApp(const MyApp());'));
    // ensureInitialized should not be duplicated.
    expect('ensureInitialized'.allMatches(output).length, 1);
    expect(output, contains("import 'package:vibebug_flutter/vibebug_flutter.dart';"));
    expect(output, contains("import 'vibebug_config.dart';"));
  });

  test('inserts WidgetsFlutterBinding.ensureInitialized() when missing', () {
    const source = '''
void main() {
  runApp(const MyApp());
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isTrue);
    expect(result.output, contains('WidgetsFlutterBinding.ensureInitialized();'));
    expect(result.output, contains('await VibeBug.initialize'));
  });

  test('preserves existing async setup (e.g. Firebase) verbatim, before initialize', () {
    const source = '''
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isTrue);
    final output = result.output!;
    expect(output, contains('await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);'));
    // The outer main() signature itself is untouched.
    expect(output, contains('Future<void> main() async {'));
    // VibeBug.initialize runs after other setup, still before runApp.
    final initializeIndex = output.indexOf('VibeBug.initialize');
    final runAppIndex = output.indexOf('runApp(const MyApp());');
    final firebaseIndex = output.indexOf('Firebase.initializeApp');
    expect(firebaseIndex, lessThan(initializeIndex));
    expect(initializeIndex, lessThan(runAppIndex));
  });

  test('is idempotent — re-running on its own output reports alreadyConfigured', () {
    const source = '''
void main() {
  runApp(const MyApp());
}
''';
    final first = transformMainDart(source);
    final second = transformMainDart(first.output!);

    expect(second.alreadyConfigured, isTrue);
    expect(second.changed, isFalse);
  });

  test('bails out when main() already has runGuarded but no initialize', () {
    const source = '''
void main() {
  VibeBug.runGuarded(() {
    runApp(const MyApp());
  });
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isFalse);
    expect(result.alreadyConfigured, isFalse);
    expect(result.bailOutReason, contains('initialize'));
  });

  test('bails out on multiple runApp() calls', () {
    const source = '''
void main() {
  if (kDebugMode) {
    runApp(const DebugApp());
  } else {
    runApp(const MyApp());
  }
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('exactly one runApp'));
  });

  test('bails out when runApp() is nested inside another callback', () {
    const source = '''
void main() {
  Timer(Duration.zero, () => runApp(const MyApp()));
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('nested'));
  });

  test('bails out on trailing code chained onto runApp()', () {
    const source = '''
void main() {
  runApp(const MyApp()).then((_) => print('done'));
}
''';
    final result = transformMainDart(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('trailing code'));
  });

  test('bails out when there is no main() function', () {
    const source = '''
class Foo {}
''';
    final result = transformMainDart(source);

    expect(result.changed, isFalse);
    expect(result.bailOutReason, contains('main()'));
  });
}
