import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures screenshots from a [RepaintBoundary] and crops selected widget bounds.
class VibeBugScreenshotCapture {
  const VibeBugScreenshotCapture();

  /// Caps GPU memory use on high-DPI phones (e.g. 480dpi Android).
  static const double maxPixelRatio = 2.0;

  /// Padding around the selected widget in logical pixels.
  static const double defaultSelectionPadding = 12;

  Future<({String fullDataUrl, String selectedDataUrl})?> capturePair({
    required GlobalKey boundaryKey,
    required Rect globalRect,
    double pixelRatio = 1,
    double selectionPadding = defaultSelectionPadding,
  }) async {
    await _waitForNextFrame();
    await _waitForNextFrame();

    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    final ratio = (pixelRatio > 0 ? pixelRatio : 1.0).clamp(1.0, maxPixelRatio);

    try {
      final fullImage = await boundary.toImage(pixelRatio: ratio);
      final fullDataUrl = await _encodePngDataUrl(fullImage);
      if (fullDataUrl.isEmpty) {
        fullImage.dispose();
        return null;
      }

      final boundaryOffset = boundary.localToGlobal(Offset.zero);
      final paddedGlobal = globalRect.inflate(selectionPadding);
      final localRect = Rect.fromLTWH(
        paddedGlobal.left - boundaryOffset.dx,
        paddedGlobal.top - boundaryOffset.dy,
        paddedGlobal.width,
        paddedGlobal.height,
      );

      final clamped = _clampRect(localRect, Size(boundary.size.width, boundary.size.height));
      if (clamped.width < 4 || clamped.height < 4) {
        fullImage.dispose();
        return (fullDataUrl: fullDataUrl, selectedDataUrl: fullDataUrl);
      }

      final selectedImage = await _cropImage(fullImage, clamped, ratio);
      final selectedDataUrl = await _encodePngDataUrl(selectedImage);
      fullImage.dispose();
      selectedImage.dispose();

      if (selectedDataUrl.isEmpty) {
        return (fullDataUrl: fullDataUrl, selectedDataUrl: fullDataUrl);
      }

      return (fullDataUrl: fullDataUrl, selectedDataUrl: selectedDataUrl);
    } catch (_) {
      return null;
    }
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  Rect _clampRect(Rect rect, Size bounds) {
    final left = rect.left.clamp(0.0, bounds.width);
    final top = rect.top.clamp(0.0, bounds.height);
    final right = rect.right.clamp(0.0, bounds.width);
    final bottom = rect.bottom.clamp(0.0, bounds.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Future<ui.Image> _cropImage(ui.Image source, Rect sourceRect, double pixelRatio) async {
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

  Future<String> _encodePngDataUrl(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    final bytes = byteData.buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}
