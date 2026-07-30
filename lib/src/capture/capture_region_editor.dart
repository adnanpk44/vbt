import 'dart:convert';
import 'dart:math' as math;

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
  bool _drawingNewCrop = false;

  /// Touch targets in display pixels (independent of screenshot scale).
  static const _cornerHitDisplay = 44.0;
  static const _edgeBandDisplay = 28.0;
  static const _minCropSize = 40.0;
  static const _defaultTapCrop = 140.0;

  @override
  void initState() {
    super.initState();
    _cropRect = VibeBugScreenshotCapture.clampRect(
      widget.initialCropRect,
      widget.imageLogicalSize,
      minSize: _minCropSize,
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
    // localPosition is relative to the image SizedBox (GestureDetector is inside it).
    final display = details.localPosition;
    final logical = layout.displayToLogical(display);

    if (_mode == _EditorMode.highlight) {
      _activeStroke = [logical];
      _activeHandle = null;
      _drawingNewCrop = false;
      return;
    }

    final handle = _hitHandleDisplay(display, layout);
    _dragStart = logical;
    _cropAtDragStart = _cropRect;

    if (handle != null) {
      _activeHandle = handle;
      _drawingNewCrop = false;
      return;
    }

    // Tap/drag outside the frame starts a new crop from that point.
    _activeHandle = _CropHandle.bottomRight;
    _drawingNewCrop = true;
    final seed = VibeBugScreenshotCapture.clampRect(
      Rect.fromLTWH(logical.dx, logical.dy, 1, 1),
      widget.imageLogicalSize,
      minSize: 1,
    );
    setState(() => _cropRect = seed);
    _cropAtDragStart = seed;
  }

  void _onPanUpdate(DragUpdateDetails details, _ImageLayout layout) {
    final logical = layout.displayToLogical(details.localPosition);

    if (_mode == _EditorMode.highlight) {
      if (_activeStroke == null) return;
      setState(() => _activeStroke = [..._activeStroke!, logical]);
      return;
    }

    if (_activeHandle == null ||
        _dragStart == null ||
        _cropAtDragStart == null) {
      return;
    }

    if (_drawingNewCrop) {
      setState(() {
        _cropRect = VibeBugScreenshotCapture.clampRect(
          Rect.fromPoints(_dragStart!, logical),
          widget.imageLogicalSize,
          minSize: 1,
        );
      });
      return;
    }

    final delta = logical - _dragStart!;
    setState(() {
      _cropRect = VibeBugScreenshotCapture.clampRect(
        _resizeCrop(_cropAtDragStart!, _activeHandle!, delta),
        widget.imageLogicalSize,
        minSize: _minCropSize,
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_mode == _EditorMode.highlight &&
        _activeStroke != null &&
        _activeStroke!.length > 1) {
      setState(() {
        _strokes.add(VibeBugHighlightStroke(List.from(_activeStroke!)));
        _activeStroke = null;
      });
      _resetDrag();
      return;
    }

    if (_mode == _EditorMode.crop && _drawingNewCrop && _dragStart != null) {
      // Tap without meaningful drag → place a default-size frame at the tap.
      final size = _cropRect;
      final tooSmall = size.width < _minCropSize || size.height < _minCropSize;
      if (tooSmall) {
        setState(() {
          _cropRect = VibeBugScreenshotCapture.clampRect(
            Rect.fromCenter(
              center: _dragStart!,
              width: _defaultTapCrop,
              height: _defaultTapCrop,
            ),
            widget.imageLogicalSize,
            minSize: _minCropSize,
          );
        });
      } else {
        setState(() {
          _cropRect = VibeBugScreenshotCapture.clampRect(
            _cropRect,
            widget.imageLogicalSize,
            minSize: _minCropSize,
          );
        });
      }
    }

    _resetDrag();
  }

  void _resetDrag() {
    _activeHandle = null;
    _dragStart = null;
    _cropAtDragStart = null;
    _activeStroke = null;
    _drawingNewCrop = false;
  }

  Rect _resizeCrop(Rect base, _CropHandle handle, Offset delta) {
    switch (handle) {
      case _CropHandle.move:
        return base.shift(delta);
      case _CropHandle.topLeft:
        return Rect.fromLTRB(
            base.left + delta.dx, base.top + delta.dy, base.right, base.bottom);
      case _CropHandle.topRight:
        return Rect.fromLTRB(
            base.left, base.top + delta.dy, base.right + delta.dx, base.bottom);
      case _CropHandle.bottomLeft:
        return Rect.fromLTRB(
            base.left + delta.dx, base.top, base.right, base.bottom + delta.dy);
      case _CropHandle.bottomRight:
        return Rect.fromLTRB(
            base.left, base.top, base.right + delta.dx, base.bottom + delta.dy);
      case _CropHandle.top:
        return Rect.fromLTRB(
            base.left, base.top + delta.dy, base.right, base.bottom);
      case _CropHandle.bottom:
        return Rect.fromLTRB(
            base.left, base.top, base.right, base.bottom + delta.dy);
      case _CropHandle.left:
        return Rect.fromLTRB(
            base.left + delta.dx, base.top, base.right, base.bottom);
      case _CropHandle.right:
        return Rect.fromLTRB(
            base.left, base.top, base.right + delta.dx, base.bottom);
    }
  }

  /// Hit-test in display pixels so handles stay easy to grab at any zoom.
  _CropHandle? _hitHandleDisplay(Offset display, _ImageLayout layout) {
    final r = layout.logicalToDisplayRect(_cropRect);
    final corner = _cornerHitDisplay;
    final edge = _edgeBandDisplay;

    final corners = <_CropHandle, Offset>{
      _CropHandle.topLeft: r.topLeft,
      _CropHandle.topRight: r.topRight,
      _CropHandle.bottomLeft: r.bottomLeft,
      _CropHandle.bottomRight: r.bottomRight,
    };
    for (final entry in corners.entries) {
      if (Rect.fromCenter(center: entry.value, width: corner, height: corner)
          .contains(display)) {
        return entry.key;
      }
    }

    final inHorizontalSpan =
        display.dx >= r.left + corner / 2 && display.dx <= r.right - corner / 2;
    final inVerticalSpan =
        display.dy >= r.top + corner / 2 && display.dy <= r.bottom - corner / 2;

    if (inHorizontalSpan &&
        display.dy >= r.top - edge / 2 &&
        display.dy <= r.top + edge) {
      return _CropHandle.top;
    }
    if (inHorizontalSpan &&
        display.dy >= r.bottom - edge &&
        display.dy <= r.bottom + edge / 2) {
      return _CropHandle.bottom;
    }
    if (inVerticalSpan &&
        display.dx >= r.left - edge / 2 &&
        display.dx <= r.left + edge) {
      return _CropHandle.left;
    }
    if (inVerticalSpan &&
        display.dx >= r.right - edge &&
        display.dx <= r.right + edge / 2) {
      return _CropHandle.right;
    }

    // Interior of the frame moves it. Outer margin still counts as move so
    // small frames remain draggable.
    final moveZone = r.inflate(4);
    if (moveZone.contains(display)) {
      return _CropHandle.move;
    }

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
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFBEF264)),
                  )
                : const Text('Save',
                    style: TextStyle(
                        color: Color(0xFFBEF264), fontWeight: FontWeight.w600)),
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
                  maxSize:
                      Size(constraints.maxWidth, constraints.maxHeight - 8),
                );
                return Center(
                  child: SizedBox(
                    width: layout.displaySize.width,
                    height: layout.displaySize.height,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _onPanStart(d, layout),
                      onPanUpdate: (d) => _onPanUpdate(d, layout),
                      onPanEnd: _onPanEnd,
                      child: Stack(
                        children: [
                          Positioned.fill(
                              child: _EditorImage(dataUrl: widget.fullDataUrl)),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EditorPainter(
                                cropRect:
                                    layout.logicalToDisplayRect(_cropRect),
                                strokes: [
                                  ..._strokes.map(
                                    (s) => s.points
                                        .map(layout.logicalToDisplay)
                                        .toList(),
                                  ),
                                  if (_activeStroke != null)
                                    _activeStroke!
                                        .map(layout.logicalToDisplay)
                                        .toList(),
                                ],
                                showMoveHint: _mode == _EditorMode.crop,
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
    const brand = Color(0xFF22C55E);
    return Material(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SegmentedButton<_EditorMode>(
                segments: const [
                  ButtonSegment(
                    value: _EditorMode.crop,
                    label: Text('Crop'),
                    icon: Icon(Icons.crop, size: 18),
                  ),
                  ButtonSegment(
                    value: _EditorMode.highlight,
                    label: Text('Highlight'),
                    icon: Icon(Icons.draw, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged:
                    _exporting ? null : (s) => setState(() => _mode = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  side: const WidgetStatePropertyAll(BorderSide.none),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return brand;
                    return Colors.white;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return Colors.white;
                    return brand;
                  }),
                  iconColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return Colors.white;
                    return brand;
                  }),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _mode == _EditorMode.crop
                  ? 'Drag corners/edges to resize · drag inside to move · tap outside to place a new frame'
                  : 'Draw freehand marks on the selected area',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Reset crop',
                  onPressed: _exporting
                      ? null
                      : () => setState(() {
                            _cropRect = VibeBugScreenshotCapture.clampRect(
                              widget.initialCropRect,
                              widget.imageLogicalSize,
                              minSize: _minCropSize,
                            );
                          }),
                  icon: const Icon(Icons.center_focus_strong,
                      color: Colors.white70),
                ),
                if (_strokes.isNotEmpty) ...[
                  IconButton(
                    tooltip: 'Undo mark',
                    onPressed: _exporting
                        ? null
                        : () => setState(() => _strokes.removeLast()),
                    icon: const Icon(Icons.undo, color: Colors.white70),
                  ),
                  IconButton(
                    tooltip: 'Clear marks',
                    onPressed: _exporting
                        ? null
                        : () => setState(() => _strokes.clear()),
                    icon: const Icon(Icons.clear_all, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataPanel() {
    // Isolate from host app InputDecorationTheme (e.g. brand green borders).
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFF475569)),
    );
    const fieldFocused = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFF94A3B8), width: 1.2),
    );

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
            Text('Widget: ${widget.hit.widgetType}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              widget.hit.selector,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            if (widget.hit.semanticsLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Text: ${widget.hit.semanticsLabel}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Theme(
              data: ThemeData(
                brightness: Brightness.dark,
                useMaterial3: true,
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Color(0xFF0F172A),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldFocused,
                  disabledBorder: fieldBorder,
                  errorBorder: fieldBorder,
                  focusedErrorBorder: fieldFocused,
                  labelStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  floatingLabelStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                  hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ),
              child: TextField(
                controller: _noteController,
                maxLines: 2,
                cursorColor: const Color(0xFFE2E8F0),
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
                decoration: const InputDecoration(
                  labelText: 'What is wrong with this widget?',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CropHandle {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

class _ImageLayout {
  const _ImageLayout({required this.displaySize, required this.scale});

  final Size displaySize;
  final double scale;

  static _ImageLayout compute(
      {required Size imageSize, required Size maxSize}) {
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
    return math.min(sx, sy);
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
        child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white38)),
      );
    }
  }
}

class _EditorPainter extends CustomPainter {
  const _EditorPainter({
    required this.cropRect,
    required this.strokes,
    this.showMoveHint = true,
  });

  final Rect cropRect;
  final List<List<Offset>> strokes;
  final bool showMoveHint;

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
        ..strokeWidth = 2.5,
    );

    final handlePaint = Paint()..color = const Color(0xFF60A5FA);
    final handleBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final c in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight
    ]) {
      canvas.drawCircle(c, 8, handlePaint);
      canvas.drawCircle(c, 8, handleBorder);
    }

    // Edge mid-handles for easier side resizing.
    final edgeCenters = [
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left, cropRect.center.dy),
      Offset(cropRect.right, cropRect.center.dy),
    ];
    for (final c in edgeCenters) {
      canvas.drawCircle(c, 5, handlePaint);
      canvas.drawCircle(c, 5, handleBorder);
    }

    if (showMoveHint && cropRect.width > 48 && cropRect.height > 48) {
      final grip = Paint()
        ..color = const Color(0x8860A5FA)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final cx = cropRect.center.dx;
      final cy = cropRect.center.dy;
      canvas.drawLine(Offset(cx - 10, cy), Offset(cx + 10, cy), grip);
      canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), grip);
    }

    final strokePaint = Paint()
      ..color = const Color(0xCCBEF264)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.clipRect(cropRect);
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.strokes.length != strokes.length ||
        oldDelegate.showMoveHint != showMoveHint;
  }
}
