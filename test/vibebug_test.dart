import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

void main() {
  test('VibeBugOptions requires auth', () {
    expect(
      () => VibeBugOptions(projectId: 'proj_test'),
      throwsAssertionError,
    );
  });

  test('VibeBugOptions accepts token', () {
    final options = VibeBugOptions(projectId: 'proj_test', token: 'tok');
    expect(options.projectId, 'proj_test');
    expect(options.autoReportCrashes, isTrue);
  });

  test('FlutterIssueMarkdown includes widget selectors and Flutter guidance', () {
    final markdown = const FlutterIssueMarkdown().build(
      summary: 'Checkout button overlaps price text',
      routeName: '/checkout',
      captures: [
        VibeBugScreenshotShot(
          id: 'shot-1',
          description: 'Pay button overlaps total',
          selectedScreenshotDataUrl: 'data:image/png;base64,abc',
          fullScreenshotDataUrl: 'data:image/png;base64,def',
          pageUrl: 'flutter:///checkout',
          cssSelector: 'flutter:ElevatedButton[key=payBtn]>Column>Scaffold',
          domText: 'Pay now',
          htmlSnippet: 'widget: ElevatedButton',
          elementTag: 'ElevatedButton',
        ),
      ],
    );

    expect(markdown, contains('Flutter UI Issue Report'));
    expect(markdown, contains('flutter:ElevatedButton[key=payBtn]'));
    expect(markdown, contains('Instructions for the Flutter coding agent'));
    expect(markdown, contains('layout parents'));
  });

  test('VibeBugScreenshotShot serializes API payload fields', () {
    final json = const VibeBugScreenshotShot(
      id: 'shot-1',
      description: 'Misaligned icon',
      selectedScreenshotDataUrl: 'data:image/png;base64,sel',
      fullScreenshotDataUrl: 'data:image/png;base64,full',
      pageUrl: 'flutter:///home',
      cssSelector: 'flutter:Icon>Row',
      domText: 'Settings',
      elementTag: 'Icon',
    ).toApiJson();

    expect(json['selectedScreenshotDataUrl'], 'data:image/png;base64,sel');
    expect(json['fullScreenshotDataUrl'], 'data:image/png;base64,full');
    expect(json['cssSelector'], 'flutter:Icon>Row');
  });

  test('clampRect keeps crop inside image bounds', () {
    final clamped = VibeBugScreenshotCapture.clampRect(
      const Rect.fromLTWH(-10, -10, 200, 200),
      const Size(100, 80),
    );
    expect(capturedWithin(clamped, const Size(100, 80)), isTrue);
    expect(clamped.width, greaterThan(0));
    expect(clamped.height, greaterThan(0));
  });

  test('exportSelectedRegion returns full when crop too small', () async {
    const capture = VibeBugScreenshotCapture();
    const full = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final selected = await capture.exportSelectedRegion(
      fullDataUrl: full,
      cropRectLogical: const Rect.fromLTWH(0, 0, 1, 1),
      imageLogicalSize: const Size(1, 1),
      pixelRatio: 1,
    );
    expect(selected, isNotEmpty);
    expect(selected.startsWith('data:image/png;base64,'), isTrue);
  });
}

bool capturedWithin(Rect rect, Size bounds) {
  return rect.left >= 0 &&
      rect.top >= 0 &&
      rect.right <= bounds.width &&
      rect.bottom <= bounds.height;
}
