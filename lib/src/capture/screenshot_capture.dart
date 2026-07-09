import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Freehand highlight stroke in image logical coordinates.
class VibeBugHighlightStroke {
  const VibeBugHighlightStroke(this.points);

  final List<Offset> points;
}

/// Captures screenshots from a [RepaintBoundary] and crops selected widget bounds.
class VibeBugScreenshotCapture {
  const VibeBugScreenshotCapture();

  /// Caps GPU memory use on high-DPI phones (e.g. 480dpi Android).
  static const double maxPixelRatio = 2.0;

  /// Padding around the selected widget in logical pixels.
  static const double defaultSelectionPadding = 12;

  /// Captures the full [RepaintBoundary] as a PNG data URL.
  Future<({String fullDataUrl, Size logicalSize, double pixelRatio})?>
      captureFull({
    required GlobalKey boundaryKey,
    double pixelRatio = 1,
  }) async {
    await _waitForNextFrame();
    await _waitForNextFrame();

    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final ratio = (pixelRatio > 0 ? pixelRatio : 1.0).clamp(1.0, maxPixelRatio);

    try {
      final fullImage = await boundary.toImage(pixelRatio: ratio);
      final fullDataUrl = await _encodePngDataUrl(fullImage);
      final logicalSize = boundary.size;
      fullImage.dispose();
      if (fullDataUrl.isEmpty) return null;
      return (
        fullDataUrl: fullDataUrl,
        logicalSize: logicalSize,
        pixelRatio: ratio
      );
    } catch (_) {
      return null;
    }
  }

  /// Maps a global widget rect into boundary-local logical coordinates.
  Rect globalRectToBoundaryLocal({
    required GlobalKey boundaryKey,
    required Rect globalRect,
    double padding = defaultSelectionPadding,
  }) {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return globalRect;

    final boundaryOffset = boundary.localToGlobal(Offset.zero);
    final padded = globalRect.inflate(padding);
    return Rect.fromLTWH(
      padded.left - boundaryOffset.dx,
      padded.top - boundaryOffset.dy,
      padded.width,
      padded.height,
    );
  }

  /// Maps a boundary-local rect back to global screen coordinates.
  Rect boundaryLocalToGlobal({
    required GlobalKey boundaryKey,
    required Rect localRect,
  }) {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return localRect;

    final boundaryOffset = boundary.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      localRect.left + boundaryOffset.dx,
      localRect.top + boundaryOffset.dy,
      localRect.width,
      localRect.height,
    );
  }

  /// Exports cropped region with optional highlight strokes burned in.
  Future<String> exportSelectedRegion({
    required String fullDataUrl,
    required Rect cropRectLogical,
    required Size imageLogicalSize,
    required double pixelRatio,
    List<VibeBugHighlightStroke> strokes = const [],
  }) async {
    final image = await decodeDataUrl(fullDataUrl);
    if (image == null) return fullDataUrl;

    try {
      final clamped = clampRect(cropRectLogical, imageLogicalSize);
      if (clamped.width < 4 || clamped.height < 4) {
        return fullDataUrl;
      }

      final cropped = await _cropImage(image, clamped, pixelRatio);
      final withHighlights = strokes.isEmpty
          ? cropped
          : await _drawHighlightsOnImage(cropped, strokes, clamped, pixelRatio);

      final dataUrl = await _encodePngDataUrl(withHighlights);
      if (cropped != withHighlights) cropped.dispose();
      withHighlights.dispose();
      return dataUrl.isEmpty ? fullDataUrl : dataUrl;
    } finally {
      image.dispose();
    }
  }

  Future<({String fullDataUrl, String selectedDataUrl})?> capturePair({
    required GlobalKey boundaryKey,
    required Rect globalRect,
    double pixelRatio = 1,
    double selectionPadding = defaultSelectionPadding,
  }) async {
    final full =
        await captureFull(boundaryKey: boundaryKey, pixelRatio: pixelRatio);
    if (full == null) return null;

    final localRect = globalRectToBoundaryLocal(
      boundaryKey: boundaryKey,
      globalRect: globalRect,
      padding: selectionPadding,
    );

    final selectedDataUrl = await exportSelectedRegion(
      fullDataUrl: full.fullDataUrl,
      cropRectLogical: localRect,
      imageLogicalSize: full.logicalSize,
      pixelRatio: full.pixelRatio,
    );

    return (fullDataUrl: full.fullDataUrl, selectedDataUrl: selectedDataUrl);
  }

  static Future<ui.Image?> decodeDataUrl(String dataUrl) async {
    try {
      final encoded = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
      final bytes = base64Decode(encoded);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Rect clampRect(Rect rect, Size bounds, {double minSize = 4}) {
    if (bounds.width <= 0 || bounds.height <= 0) return Rect.zero;

    final normalized = Rect.fromLTRB(
      rect.left < rect.right ? rect.left : rect.right,
      rect.top < rect.bottom ? rect.top : rect.bottom,
      rect.left < rect.right ? rect.right : rect.left,
      rect.top < rect.bottom ? rect.bottom : rect.top,
    );

    final effectiveMinWidth = minSize.clamp(1.0, bounds.width).toDouble();
    final effectiveMinHeight = minSize.clamp(1.0, bounds.height).toDouble();
    final width =
        normalized.width.clamp(effectiveMinWidth, bounds.width).toDouble();
    final height =
        normalized.height.clamp(effectiveMinHeight, bounds.height).toDouble();
    var left = normalized.left.clamp(0.0, bounds.width - width).toDouble();
    var top = normalized.top.clamp(0.0, bounds.height - height).toDouble();

    if (normalized.right > bounds.width) left = bounds.width - width;
    if (normalized.bottom > bounds.height) top = bounds.height - height;

    return Rect.fromLTWH(left, top, width, height);
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  Future<ui.Image> _cropImage(
      ui.Image source, Rect sourceRect, double pixelRatio) async {
    final width = (sourceRect.width * pixelRatio).round().clamp(1, 2048);
    final height = (sourceRect.height * pixelRatio).round().clamp(1, 2048);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final src = Rect.fromLTWH(
      sourceRect.left * pixelRatio,
      sourceRect.top * pixelRatio,
      sourceRect.width * pixelRatio,
      sourceRect.height * pixelRatio,
    );
    final dst = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    canvas.drawImageRect(source, src, dst, ui.Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }

  Future<ui.Image> _drawHighlightsOnImage(
    ui.Image cropped,
    List<VibeBugHighlightStroke> strokes,
    Rect cropRectLogical,
    double pixelRatio,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..color = const ui.Color(0xCCBEF264)
      ..strokeWidth = 4 * pixelRatio
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;

    canvas.drawImage(cropped, Offset.zero, ui.Paint());

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final path = ui.Path();
      final first =
          _toCropPixel(stroke.points.first, cropRectLogical, pixelRatio);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        final p = _toCropPixel(stroke.points[i], cropRectLogical, pixelRatio);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(cropped.width, cropped.height);
    picture.dispose();
    return image;
  }

  Offset _toCropPixel(
      Offset logicalPoint, Rect cropRectLogical, double pixelRatio) {
    return Offset(
      (logicalPoint.dx - cropRectLogical.left) * pixelRatio,
      (logicalPoint.dy - cropRectLogical.top) * pixelRatio,
    );
  }

  Future<String> _encodePngDataUrl(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    final bytes = byteData.buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}
