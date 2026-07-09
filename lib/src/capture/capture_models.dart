import 'dart:ui';

/// One visual capture attached to an issue (mirrors the Chrome extension draft shot).
class VibeBugScreenshotShot {
  const VibeBugScreenshotShot({
    required this.id,
    required this.description,
    required this.selectedScreenshotDataUrl,
    required this.fullScreenshotDataUrl,
    required this.pageUrl,
    required this.cssSelector,
    this.domText = '',
    this.htmlSnippet = '',
    this.elementTag = '',
    this.elementClasses = '',
    this.elementId = '',
    this.viewportWidth = 0,
    this.viewportHeight = 0,
    this.elementRect,
    this.attachments = const [],
  });

  final String id;
  final String description;
  final String selectedScreenshotDataUrl;
  final String fullScreenshotDataUrl;
  final String pageUrl;
  final String cssSelector;
  final String domText;
  final String htmlSnippet;
  final String elementTag;
  final String elementClasses;
  final String elementId;
  final int viewportWidth;
  final int viewportHeight;
  final Rect? elementRect;
  final List<Map<String, dynamic>> attachments;

  Map<String, dynamic> toApiJson() => {
        'id': id,
        'description': description,
        'selectedScreenshotDataUrl': selectedScreenshotDataUrl,
        'fullScreenshotDataUrl': fullScreenshotDataUrl,
        'screenshotDataUrl': selectedScreenshotDataUrl,
        'pageUrl': pageUrl,
        'cssSelector': cssSelector,
        'domText': domText,
        'htmlSnippet': htmlSnippet,
        'elementTag': elementTag,
        'elementClasses': elementClasses,
        'elementId': elementId,
        'viewportWidth': viewportWidth,
        'viewportHeight': viewportHeight,
        if (elementRect != null)
          'elementRect': {
            'x': elementRect!.left,
            'y': elementRect!.top,
            'width': elementRect!.width,
            'height': elementRect!.height,
          },
        'attachments': attachments,
      };
}

/// Widget metadata collected during pointer hit-testing.
class FlutterWidgetHit {
  const FlutterWidgetHit({
    required this.widgetType,
    required this.selector,
    required this.globalRect,
    required this.ancestorTrail,
    this.widgetKey,
    this.semanticsLabel = '',
    this.widgetSnippet = '',
    this.routeName = '',
  });

  final String widgetType;
  final String? widgetKey;
  final String selector;
  final String semanticsLabel;
  final String widgetSnippet;
  final String routeName;
  final Rect globalRect;
  final List<String> ancestorTrail;
}
