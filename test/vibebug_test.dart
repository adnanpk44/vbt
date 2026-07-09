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
}
