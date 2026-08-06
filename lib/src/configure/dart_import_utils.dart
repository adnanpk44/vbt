final _importLinePattern = RegExp(r"^import\s+'[^']+'[^;]*;[ \t]*$", multiLine: true);

/// Inserts `import '<importUri>';` after the last existing import line (or at
/// the top of the file if there are none), unless it's already present.
String ensureImport(String source, String importUri) {
  final statement = "import '$importUri';";
  if (source.contains(statement)) return source;

  final matches = _importLinePattern.allMatches(source).toList();
  if (matches.isEmpty) {
    return '$statement\n\n$source';
  }
  final insertAt = matches.last.end;
  return '${source.substring(0, insertAt)}\n$statement${source.substring(insertAt)}';
}
