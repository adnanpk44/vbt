import 'dart:io';

final _materialAppPattern = RegExp(r'\bMaterialApp(\.router)?\s*\(');

/// All `.dart` files under `lib/`, excluding generated (`*.g.dart`) files.
List<File> findLibDartFiles(Directory projectRoot) {
  final libDir = Directory('${projectRoot.path}/lib');
  if (!libDir.existsSync()) return [];
  return libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();
}

/// Finds the single `.dart` file under `lib/` (other than [exclude]) that
/// contains a `MaterialApp(...)`/`MaterialApp.router(...)` usage. Returns
/// null if there are zero or more than one candidates — both are treated as
/// "can't safely automate this" by the caller.
File? findSoleMaterialAppFile(Directory projectRoot, {required File exclude}) {
  final candidates = findLibDartFiles(projectRoot)
      .where((f) => f.path != exclude.path)
      .where((f) => _materialAppPattern.hasMatch(f.readAsStringSync()))
      .toList();
  return candidates.length == 1 ? candidates.first : null;
}

bool fileContainsMaterialApp(String source) => _materialAppPattern.hasMatch(source);

String relativePath(Directory root, File file) {
  final rootPath = root.path.endsWith('/') ? root.path : '${root.path}/';
  return file.path.startsWith(rootPath) ? file.path.substring(rootPath.length) : file.path;
}

/// A minimal line-level diff — good enough for main.dart-sized files whose
/// changes are a handful of inserted/replaced lines, not a full rewrite.
/// Trims the common prefix/suffix and shows only the differing middle.
List<String> simpleDiffLines(String before, String after) {
  final b = before.split('\n');
  final a = after.split('\n');
  var prefix = 0;
  while (prefix < b.length && prefix < a.length && b[prefix] == a[prefix]) {
    prefix++;
  }
  var endB = b.length;
  var endA = a.length;
  while (endB > prefix && endA > prefix && b[endB - 1] == a[endA - 1]) {
    endB--;
    endA--;
  }
  return [
    for (var i = prefix; i < endB; i++) '  - ${b[i]}',
    for (var i = prefix; i < endA; i++) '  + ${a[i]}',
  ];
}

bool confirm(String message) {
  stdout.write('$message [y/N] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase();
  return answer == 'y' || answer == 'yes';
}

/// Backs up [file]'s current contents to `<path>.bak`, overwriting any
/// previous backup — its purpose is "undo my last configure run", not a
/// history of every run.
void writeBackup(File file, String originalContent) {
  File('${file.path}.bak').writeAsStringSync(originalContent);
}
