import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/configure/comment_stripper.dart';

void main() {
  test('blanks out // line comments but keeps length and newlines', () {
    const source = 'void main() { // start\n  runApp(x);\n}';
    final stripped = stripCommentsForScanning(source);

    expect(stripped.length, source.length);
    expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
    expect(stripped, isNot(contains('start')));
    expect(stripped, contains('runApp(x);'));
  });

  test('blanks out /* */ block comments spanning multiple lines', () {
    const source = 'void main() {\n  /* old\n  code */\n  runApp(x);\n}';
    final stripped = stripCommentsForScanning(source);

    expect(stripped.length, source.length);
    expect(stripped, isNot(contains('old')));
    expect(stripped, isNot(contains('code')));
    expect(stripped, contains('runApp(x);'));
  });

  test('does not treat // inside a string literal as a comment', () {
    const source = "const url = 'https://vibebugtracker.com'; // real comment";
    final stripped = stripCommentsForScanning(source);

    expect(stripped, contains("'https://vibebugtracker.com'"));
    expect(stripped, isNot(contains('real comment')));
  });

  test('does not treat // inside a double-quoted string as a comment', () {
    const source = 'const url = "https://example.com/path";';
    final stripped = stripCommentsForScanning(source);

    expect(stripped, contains('"https://example.com/path"'));
  });

  test('handles escaped quotes inside a string without ending it early', () {
    const source = r"const s = 'it\'s // not a comment'; runApp(x);";
    final stripped = stripCommentsForScanning(source);

    expect(stripped, contains('runApp(x);'));
    expect(stripped, contains(r"it\'s"));
  });

  test('leaves already-comment-free source untouched in content', () {
    const source = 'void main() {\n  runApp(const MyApp());\n}';
    expect(stripCommentsForScanning(source), source);
  });
}
