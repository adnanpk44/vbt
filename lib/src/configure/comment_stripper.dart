/// Blanks out `//` line comments and `/* */` block comments in [source] —
/// replacing comment characters (but never newlines) with spaces — so
/// pattern matching can ignore commented-out code (e.g. an old `main()` or
/// `MaterialApp(...)` left behind, which would otherwise look like a second,
/// real occurrence and trigger a false "ambiguous" bail-out).
///
/// Skips over string literals (single/double/triple-quoted, with basic
/// escape handling) while scanning, so a URL like `'https://example.com'`
/// is never mistaken for the start of a `//` comment.
///
/// The result has the exact same length and newline positions as [source],
/// so every character offset found by matching against it is valid for
/// slicing the original [source] too — callers use the stripped text only
/// to decide *where* things are, then read the real content (including
/// real comments) back out of the original string.
String stripCommentsForScanning(String source) {
  final buffer = StringBuffer();
  var i = 0;
  String? stringDelim;

  while (i < source.length) {
    if (stringDelim != null) {
      if (source.startsWith(stringDelim, i)) {
        buffer.write(stringDelim);
        i += stringDelim.length;
        stringDelim = null;
        continue;
      }
      if (source[i] == r'\' && stringDelim.length == 1 && i + 1 < source.length) {
        buffer.write(source.substring(i, i + 2));
        i += 2;
        continue;
      }
      buffer.write(source[i]);
      i++;
      continue;
    }

    if (source.startsWith("'''", i) || source.startsWith('"""', i)) {
      stringDelim = source.substring(i, i + 3);
      buffer.write(stringDelim);
      i += 3;
      continue;
    }
    if (source[i] == "'" || source[i] == '"') {
      stringDelim = source[i];
      buffer.write(source[i]);
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      final stop = end == -1 ? source.length : end;
      buffer.write(' ' * (stop - i));
      i = stop;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end == -1 ? source.length : end + 2;
      for (var j = i; j < stop; j++) {
        buffer.write(source[j] == '\n' ? '\n' : ' ');
      }
      i = stop;
      continue;
    }
    buffer.write(source[i]);
    i++;
  }

  return buffer.toString();
}
