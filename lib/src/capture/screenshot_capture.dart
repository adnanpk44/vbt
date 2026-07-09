import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures screenshots from a [RepaintBoundary] and crops selected widget bounds.
class VibeBugScreenshotCapture {
  const VibeBugScreenshotCapture();

  Future<({String fullDataUrl, String selectedDataUrl})?> capturePair({
    required GlobalKey boundaryKey,
    required Rect globalRect,
    double pixelRatio = 1,
  }) async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final ratio = pixelRatio > 0 ? pixelRatio.toDouble() : 1.0;
    final fullImage = await boundary.toImage(pixelRatio: ratio);
    final fullDataUrl = await _encodePngDataUrl(fullImage);

    final boundaryBox = boundary;
  final boundaryOffset = boundaryBox.localToGlobal(Offset.zero);
    final localRect = Rect.fromLTWH(
      globalRect.left - boundaryOffset.dx,
      globalRect.top - boundaryOffset.dy,
      globalRect.width,
      globalRect.height,
    );

    final clamped = _clampRect(localRect, Size(boundaryBox.size.width, boundaryBox.size.height));
    if (clamped.width < 2 || clamped.height < 2) {
      fullImage.dispose();
      return (fullDataUrl: fullDataUrl, selectedDataUrl: fullDataUrl);
    }

    final selectedImage = await _cropImage(fullImage, clamped, ratio);
    final selectedDataUrl = await _encodePngDataUrl(selectedImage);
    fullImage.dispose();
    selectedImage.dispose();

    return (fullDataUrl: fullDataUrl, selectedDataUrl: selectedDataUrl);
  }

  Rect _clampRect(Rect rect, Size bounds) {
    final left = rect.left.clamp(0.0, bounds.width);
    final top = rect.top.clamp(0.0, bounds.height);
    final right = rect.right.clamp(0.0, bounds.width);
    final bottom = rect.bottom.clamp(0.0, bounds.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Future<ui.Image> _cropImage(ui.Image source, Rect sourceRect, double pixelRatio) async {
    final width = (sourceRect.width * pixelRatio).round().clamp(1, 4096);
    final height = (sourceRect.height * pixelRatio).round().clamp(1, 4096);
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

  Future<String> _encodePngDataUrl(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    final bytes = byteData.buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}
