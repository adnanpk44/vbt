import 'dart:io';

import 'package:flutter/foundation.dart';

import 'capture_models.dart';

/// Builds a Flutter-focused issue description for developers and coding agents.
class FlutterIssueMarkdown {
  const FlutterIssueMarkdown();

  String build({
    required String summary,
    required List<VibeBugScreenshotShot> captures,
    String? routeName,
    String? platformLabel,
  }) {
    final buffer = StringBuffer()
      ..writeln('# Flutter UI Issue Report')
      ..writeln()
      ..writeln('## Summary')
      ..writeln(summary.trim())
      ..writeln()
      ..writeln('## Environment')
      ..writeln('- Platform: ${platformLabel ?? _platformLabel()}')
      ..writeln('- Framework: Flutter')
      ..writeln('- Debug mode: $kDebugMode')
      ..writeln('- Profile mode: $kProfileMode')
      ..writeln('- Release mode: $kReleaseMode');
    if (routeName != null && routeName.trim().isNotEmpty) {
      buffer.writeln('- Route: `$routeName`');
    }

    buffer
      ..writeln()
      ..writeln('## Visual captures (${captures.length})')
      ..writeln('Each capture includes a selected widget crop and full screen context.');

    for (var i = 0; i < captures.length; i++) {
      final shot = captures[i];
      buffer
        ..writeln()
        ..writeln('### Capture ${i + 1}')
        ..writeln('- Tester note: ${shot.description.trim().isEmpty ? '(none)' : shot.description.trim()}')
        ..writeln('- Page route: `${shot.pageUrl.isEmpty ? routeName ?? 'unknown' : shot.pageUrl}`')
        ..writeln('- Widget selector: `${shot.cssSelector}`')
        ..writeln('- Widget type: `${shot.elementTag.isEmpty ? 'unknown' : shot.elementTag}`');
      if (shot.domText.trim().isNotEmpty) {
        buffer.writeln('- Semantics / text: ${shot.domText.trim()}');
      }
      if (shot.elementRect != null) {
        final rect = shot.elementRect!;
        buffer.writeln(
          '- Bounds: ${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)} at (${rect.left.toStringAsFixed(0)}, ${rect.top.toStringAsFixed(0)})',
        );
      }
      if (shot.htmlSnippet.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('```text')
          ..writeln(shot.htmlSnippet.trim())
          ..writeln('```');
      }
    }

    buffer
      ..writeln()
      ..writeln('## Instructions for the Flutter coding agent')
      ..writeln('1. Start with the **selected widget screenshot** for each capture — that is the primary visual source.')
      ..writeln('2. Use the widget selector trail to locate the widget in Dart source (`StatelessWidget` / `StatefulWidget` tree).')
      ..writeln('3. Check layout parents (`Row`, `Column`, `Flex`, `Stack`, `ListView`, `Sliver*`) and constraints before changing child widgets.')
      ..writeln('4. Prefer fixing theme, padding, alignment, and `MediaQuery` usage over hard-coded pixel sizes.')
      ..writeln('5. Use the full-screen screenshot only when the bug depends on page context, scrolling, or overlays.')
      ..writeln('6. Reproduce on the same route and verify with `flutter test` / widget tests when possible.');

    if (captures.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Primary widget target')
        ..writeln('`${captures.first.cssSelector}`');
    }

    return buffer.toString().trim();
  }

  String _platformLabel() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }
}
