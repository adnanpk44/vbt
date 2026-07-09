import 'dart:convert';

import 'package:flutter/material.dart';

import 'capture_models.dart';
import 'screenshot_capture.dart';

/// Result from the crop/highlight editor.
class CaptureRegionEditorResult {
  const CaptureRegionEditorResult({
    required this.description,
    required this.selectedScreenshotDataUrl,
    required this.fullScreenshotDataUrl,
    required this.elementRect,
  });

  final String description;
  final String selectedScreenshotDataUrl;
  final String fullScreenshotDataUrl;
  final Rect elementRect;
}

enum _EditorMode { crop, highlight }

/// Full-screen editor: adjust crop region, draw highlights, add per-capture note.
class CaptureRegionEditor extends StatefulWidget {
  const CaptureRegionEditor({
    super.key,
    required this.fullDataUrl,
    required this.imageLogicalSize,
    required this.initialCropRect,
    required this.pixelRatio,
    required this.hit,
    required this.captureIndex,
  });

  final String fullDataUrl;
  final Size imageLogicalSize;
  final Rect initialCropRect;
  final double pixelRatio;
  final FlutterWidgetHit hit;
  final int captureIndex;

  static Future<CaptureRegionEditorResult?> open({
    required BuildContext context,
    required String fullDataUrl,
    required Size imageLogicalSize,
    required Rect initialCropRect,
    required double pixelRatio,
    required FlutterWidgetHit hit,
    required int captureIndex,
  }) {
    return Navigator.of(context).push<CaptureRegionEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaptureRegionEditor(
          fullDataUrl: fullDataUrl,
          imageLogicalSize: imageLogicalSize,
          initialCropRect: initialCropRect,
          pixelRatio: pixelRatio,
          hit: hit,
          captureIndex: captureIndex,
        ),
      ),
    );
  }

  @override
  State<CaptureRegionEditor> createState() => _CaptureRegionEditorState();
}

class _CaptureRegionEditorState extends State<CaptureRegionEditor> {
  final _screenshots = const VibeBugScreenshotCapture();
  final _noteController = TextEditingController();
  late Rect _cropRect;
  final List<VibeBugHighlightStroke> _strokes = [];
  List<Offset>? _activeStroke;
  _EditorMode _mode = _EditorMode.crop;
  _CropHandle? _activeHandle;
  Offset? _dragStart;
  Rect? _cropAtDragStart;
  bool _exporting = false;

  static const _handleSize = 24.0;

  @override
  void initState() {
    super.initState();
    _cropRect = VibeBugScreenshotCapture.clampRect(
      widget.initialCropRect,
      widget.imageLogicalSize,
    );
    if (widget.hit.semanticsLabel.isNotEmpty) {
      _noteController.text = widget.hit.semanticsLabel;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a description for this capture.')),
      );
      return;
    }

    setState(() => _exporting = true);
    final selected = await _screenshots.exportSelectedRegion(
      fullDataUrl: widget.fullDataUrl,
      cropRectLogical: _cropRect,
      imageLogicalSize: widget.imageLogicalSize,
      pixelRatio: widget.pixelRatio,
      strokes: _strokes,
    );
    if (!mounted) return;
    setState(() => _exporting = false);

    Navigator.of(context).pop(
      CaptureRegionEditorResult(
        description: note,
        selectedScreenshotDataUrl: selected,
        fullScreenshotDataUrl: widget.fullDataUrl,
        elementRect: _cropRect,
      ),
    );
  }

  void _onPanStart(DragStartDetails details, _ImageLayout layout) {
    final logical = layout.displayToLogical(details.localPosition);
    if (_mode == _EditorMode.highlight) {
      _activeStroke = [logical];
      return;
    }

    _activeHandle = _hitHandle(logical);
    _dragStart = logical;
    _cropAtDragStart = _cropRect;
  }

  void _onPanUpdate(DragUpdateDetails details, _ImageLayout layout) {
    final logical = layout.displayToLogical(details.localPosition);

    if (_mode == _EditorMode.highlight) {
      if (_activeStroke == null) return;
      setState(() => _activeStroke = [..._activeStroke!, logical]);
      return;
    }

    if (_activeHandle == null || _dragStart == null || _cropAtDragStart == null) return;
    final delta = logical - _dragStart!;
    setState(() {
      _cropRect = _resizeCrop(_cropAtDragStart!, _activeHandle!, delta);
      _cropRect = VibeBugScreenshotCapture.clampRect(_cropRect, widget.imageLogicalSize);
      if (_cropRect.width < 32 || _cropRect.height < 32) {
        _cropRect = _cropAtDragStart!;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_mode == _EditorMode.highlight && _activeStroke != null && _activeStroke!.length > 1) {
      setState(() {
        _strokes.add(VibeBugHighlightStroke(List.from(_activeStroke!)));
        _activeStroke = null;
      });
      return;
    }
    _activeHandle = null;
    _dragStart = null;
    _cropAtDragStart = null;
    _activeStroke = null;
  }

  Rect _resizeCrop(Rect base, _CropHandle handle, Offset delta) {
    switch (handle) {
      case _CropHandle.move:
        return base.shift(delta);
      case _CropHandle.topLeft:
        return Rect.fromLTRB(base.left + delta.dx, base.top + delta.dy, base.right, base.bottom);
      case _CropHandle.topRight:
        return Rect.fromLTRB(base.left, base.top + delta.dy, base.right + delta.dx, base.bottom);
      case _CropHandle.bottomLeft:
        return Rect.fromLTRB(base.left + delta.dx, base.top, base.right, base.bottom + delta.dy);
      case _CropHandle.bottomRight:
        return Rect.fromLTRB(base.left, base.top, base.right + delta.dx, base.bottom + delta.dy);
    }
  }

  _CropHandle? _hitHandle(Offset logical) {
    final r = _cropRect;
    final hit = _handleSize;
    if (Rect.fromCenter(center: r.topLeft, width: hit, height: hit).contains(logical)) {
      return _CropHandle.topLeft;
    }
    if (Rect.fromCenter(center: r.topRight, width: hit, height: hit).contains(logical)) {
      return _CropHandle.topRight;
    }
    if (Rect.fromCenter(center: r.bottomLeft, width: hit, height: hit).contains(logical)) {
      return _CropHandle.bottomLeft;
    }
    if (Rect.fromCenter(center: r.bottomRight, width: hit, height: hit).contains(logical)) {
      return _CropHandle.bottomRight;
    }
    if (r.contains(logical)) return _CropHandle.move;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: Text('Capture ${widget.captureIndex}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exporting ? null : () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _exporting ? null : _save,
            child: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFBEF264)),
                  )
                : const Text('Save', style: TextStyle(color: Color(0xFFBEF264), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = _ImageLayout.compute(
                  imageSize: widget.imageLogicalSize,
                  maxSize: Size(constraints.maxWidth, constraints.maxHeight - 8),
                );
                return GestureDetector(
                  onPanStart: (d) => _onPanStart(d, layout),
                  onPanUpdate: (d) => _onPanUpdate(d, layout),
                  onPanEnd: _onPanEnd,
                  child: Center(
                    child: SizedBox(
                      width: layout.displaySize.width,
                      height: layout.displaySize.height,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _EditorImage(dataUrl: widget.fullDataUrl)),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EditorPainter(
                                cropRect: layout.logicalToDisplayRect(_cropRect),
                                strokes: [
                                  ..._strokes.map(
                                    (s) => s.points.map(layout.logicalToDisplay).toList(),
                                  ),
                                  if (_activeStroke != null)
                                    _activeStroke!.map(layout.logicalToDisplay).toList(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildToolbar(),
          _buildMetadataPanel(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SegmentedButton<_EditorMode>(
              segments: const [
                ButtonSegment(value: _EditorMode.crop, label: Text('Crop'), icon: Icon(Icons.crop, size: 18)),
                ButtonSegment(
                  value: _EditorMode.highlight,
                  label: Text('Highlight'),
                  icon: Icon(Icons.draw, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _exporting ? null : (s) => setState(() => _mode = s.first),
            ),
            const Spacer(),
            if (_strokes.isNotEmpty)
              TextButton.icon(
                onPressed: _exporting ? null : () => setState(() => _strokes.clear()),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Clear marks'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataPanel() {
    return Material(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Widget: ${widget.hit.widgetType}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              widget.hit.selector,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            if (widget.hit.semanticsLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Text: ${widget.hit.semanticsLabel}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'What is wrong with this widget?',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CropHandle { move, topLeft, topRight, bottomLeft, bottomRight }

class _ImageLayout {
  const _ImageLayout({required this.displaySize, required this.scale});

  final Size displaySize;
  final double scale;

  static _ImageLayout compute({required Size imageSize, required Size maxSize}) {
    final fitted = _fitScale(imageSize, maxSize);
    return _ImageLayout(
      displaySize: Size(imageSize.width * fitted, imageSize.height * fitted),
      scale: fitted,
    );
  }

  static double _fitScale(Size imageSize, Size maxSize) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return 1;
    final sx = maxSize.width / imageSize.width;
    final sy = maxSize.height / imageSize.height;
    return sx < sy ? sx : sy;
  }

  Offset displayToLogical(Offset display) => display / scale;
  Offset logicalToDisplay(Offset logical) => logical * scale;

  Rect logicalToDisplayRect(Rect logical) => Rect.fromLTWH(
        logical.left * scale,
        logical.top * scale,
        logical.width * scale,
        logical.height * scale,
      );
}

class _EditorImage extends StatelessWidget {
  const _EditorImage({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    try {
      final encoded = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
      final bytes = base64Decode(encoded);
      return Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
    } catch (_) {
      return const ColoredBox(
        color: Color(0xFF1E293B),
        child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38)),
      );
    }
  }
}

class _EditorPainter extends CustomPainter {
  const _EditorPainter({required this.cropRect, required this.strokes});

  final Rect cropRect;
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x99000000));

    canvas.drawRect(
      cropRect,
      Paint()
        ..color = const Color(0xFF60A5FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final handlePaint = Paint()..color = const Color(0xFF60A5FA);
    for (final c in [cropRect.topLeft, cropRect.topRight, cropRect.bottomLeft, cropRect.bottomRight]) {
      canvas.drawCircle(c, 6, handlePaint);
    }

    final strokePaint = Paint()
      ..color = const Color(0xCCBEF264)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || oldDelegate.strokes.length != strokes.length;
  }
}
