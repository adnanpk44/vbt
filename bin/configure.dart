// ignore_for_file: avoid_print
//
// Zero-config setup for vibebug_flutter — run with:
//   dart run vibebug_flutter:configure
//
// Rewrites your app's main.dart (wraps runApp in VibeBug.runGuarded, awaits
// VibeBug.initialize) and MaterialApp (wires VibeBugScope into builder:) so
// no manual integration is required, then generates lib/vibebug_config.dart
// with your backend base URL. Always shows a diff and asks for confirmation
// before writing anything (skip the prompt with --yes), and takes a `.bak`
// backup of every file it edits.
import 'dart:io';

import 'package:vibebug_flutter/src/configure/cli_io.dart';
import 'package:vibebug_flutter/src/configure/config_file_writer.dart';
import 'package:vibebug_flutter/src/configure/main_dart_transformer.dart';
import 'package:vibebug_flutter/src/configure/material_app_builder_transformer.dart';

class _PendingChange {
  _PendingChange({required this.file, required this.originalContent, required this.newContent});
  final File file;
  final String? originalContent;
  final String newContent;
  bool get isNewFile => originalContent == null;
}

void main(List<String> arguments) {
  final yes = arguments.contains('--yes') || arguments.contains('-y');
  final baseUrl = _argValue(arguments, '--base-url') ?? 'https://vibebugtracker.com';
  final projectRoot = Directory.current;

  final pubspec = File('${projectRoot.path}/pubspec.yaml');
  if (!pubspec.existsSync() || !pubspec.readAsStringSync().contains('flutter:')) {
    stderr.writeln(
      'error: run this from the root of a Flutter app (no pubspec.yaml with a '
      'flutter: section found in ${projectRoot.path}).',
    );
    exitCode = 1;
    return;
  }

  final mainDartFile = File('${projectRoot.path}/lib/main.dart');
  if (!mainDartFile.existsSync()) {
    stderr.writeln('error: ${mainDartFile.path} not found.');
    exitCode = 1;
    return;
  }

  final originalMainDart = mainDartFile.readAsStringSync();
  final mainResult = transformMainDart(originalMainDart);

  final notes = <String>[];
  final pending = <_PendingChange>[];

  if (fileContainsMaterialApp(originalMainDart)) {
    _handleCombinedMainDart(
      mainDartFile: mainDartFile,
      originalMainDart: originalMainDart,
      mainResult: mainResult,
      notes: notes,
      pending: pending,
    );
  } else {
    _handleMainDartOnly(
      mainDartFile: mainDartFile,
      originalMainDart: originalMainDart,
      mainResult: mainResult,
      notes: notes,
      pending: pending,
    );
    _handleSeparateMaterialAppFile(
      projectRoot: projectRoot,
      mainDartFile: mainDartFile,
      notes: notes,
      pending: pending,
    );
  }

  final configFile = File('${projectRoot.path}/lib/vibebug_config.dart');
  if (!configFile.existsSync()) {
    pending.add(_PendingChange(
      file: configFile,
      originalContent: null,
      newContent: buildConfigFileContents(baseUrl: baseUrl),
    ));
  }

  if (notes.isNotEmpty) {
    print(notes.join('\n'));
    print('');
  }

  if (pending.isEmpty) {
    print('Nothing to do — VibeBug already appears to be wired up.');
    return;
  }

  for (final change in pending) {
    if (change.isNewFile) {
      print('Create ${relativePath(projectRoot, change.file)}');
    } else {
      print('Update ${relativePath(projectRoot, change.file)}');
      for (final line in simpleDiffLines(change.originalContent!, change.newContent)) {
        print(line);
      }
    }
  }
  print('');

  if (!yes && !confirm('Apply these changes?')) {
    print('Aborted — no files were changed.');
    return;
  }

  for (final change in pending) {
    if (!change.isNewFile) {
      writeBackup(change.file, change.originalContent!);
    } else {
      change.file.parent.createSync(recursive: true);
    }
    change.file.writeAsStringSync(change.newContent);
  }

  print('Done. Run your app — first launch will show a sign-in screen, then a project picker.');
}

/// `MaterialApp(...)` lives inside main.dart itself (the default
/// `flutter create` template shape) — apply both transforms to the same
/// file, in sequence, since they touch non-overlapping regions of it.
void _handleCombinedMainDart({
  required File mainDartFile,
  required String originalMainDart,
  required MainDartTransformResult mainResult,
  required List<String> notes,
  required List<_PendingChange> pending,
}) {
  if (mainResult.alreadyConfigured) {
    notes.add('lib/main.dart: runApp() is already wired up.');
  } else if (mainResult.bailOutReason != null) {
    notes.add('lib/main.dart (runApp wiring): ${mainResult.bailOutReason}');
  }

  final baseText = mainResult.changed ? mainResult.output! : originalMainDart;
  final materialAppResult = transformMaterialAppBuilder(baseText);

  if (materialAppResult.alreadyConfigured) {
    notes.add('lib/main.dart: MaterialApp is already wired up.');
  } else if (materialAppResult.bailOutReason != null) {
    notes.add('lib/main.dart (MaterialApp wiring): ${materialAppResult.bailOutReason}');
  }
  for (final warning in materialAppResult.warnings) {
    notes.add('Warning: $warning');
  }

  var finalContent = materialAppResult.changed ? materialAppResult.output! : baseText;
  final anyChange = mainResult.changed || materialAppResult.changed;
  final anyBail = mainResult.bailOutReason != null || materialAppResult.bailOutReason != null;

  if (!anyChange && anyBail) {
    finalContent = '// TODO(vibebug): manual setup needed — see '
        'https://pub.dev/packages/vibebug_flutter and the notes above\n$originalMainDart';
    pending.add(_PendingChange(
      file: mainDartFile,
      originalContent: originalMainDart,
      newContent: finalContent,
    ));
  } else if (anyChange) {
    pending.add(_PendingChange(
      file: mainDartFile,
      originalContent: originalMainDart,
      newContent: finalContent,
    ));
  }
}

void _handleMainDartOnly({
  required File mainDartFile,
  required String originalMainDart,
  required MainDartTransformResult mainResult,
  required List<String> notes,
  required List<_PendingChange> pending,
}) {
  if (mainResult.alreadyConfigured) {
    notes.add('lib/main.dart: already wired up.');
  } else if (mainResult.bailOutReason != null) {
    notes.add('lib/main.dart: ${mainResult.bailOutReason}');
    pending.add(_PendingChange(
      file: mainDartFile,
      originalContent: originalMainDart,
      newContent: '// TODO(vibebug): ${mainResult.bailOutReason} — see '
          'https://pub.dev/packages/vibebug_flutter\n$originalMainDart',
    ));
  } else if (mainResult.changed) {
    pending.add(_PendingChange(
      file: mainDartFile,
      originalContent: originalMainDart,
      newContent: mainResult.output!,
    ));
  }
}

void _handleSeparateMaterialAppFile({
  required Directory projectRoot,
  required File mainDartFile,
  required List<String> notes,
  required List<_PendingChange> pending,
}) {
  final materialAppFile = findSoleMaterialAppFile(projectRoot, exclude: mainDartFile);
  if (materialAppFile == null) {
    notes.add(
      'Could not find a single MaterialApp(...) usage outside main.dart — '
      'wire VibeBugScope into your MaterialApp builder manually (see README).',
    );
    return;
  }

  final original = materialAppFile.readAsStringSync();
  final result = transformMaterialAppBuilder(original);
  final path = relativePath(projectRoot, materialAppFile);

  if (result.alreadyConfigured) {
    notes.add('$path: already wired up.');
    return;
  }
  if (result.bailOutReason != null) {
    notes.add('$path: ${result.bailOutReason}');
    pending.add(_PendingChange(
      file: materialAppFile,
      originalContent: original,
      newContent: '// TODO(vibebug): ${result.bailOutReason} — see '
          'https://pub.dev/packages/vibebug_flutter\n$original',
    ));
    return;
  }
  if (result.changed) {
    pending.add(_PendingChange(
      file: materialAppFile,
      originalContent: original,
      newContent: result.output!,
    ));
    for (final warning in result.warnings) {
      notes.add('Warning: $warning');
    }
  }
}

String? _argValue(List<String> arguments, String flag) {
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == flag && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
    if (arguments[i].startsWith('$flag=')) {
      return arguments[i].substring(flag.length + 1);
    }
  }
  return null;
}
