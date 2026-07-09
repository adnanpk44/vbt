import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../vibebug.dart';
import 'capture_models.dart';
import 'screenshot_capture.dart';
import 'widget_inspector.dart';

const _maxCaptures = 8;
const _bubblePositionKey = 'vibebug_bubble_offset';
const _bubbleDragSlop = 10.0;

/// Draggable report button + widget picker + multi-screenshot issue composer.
class VibeBugCaptureOverlay extends StatefulWidget {
  const VibeBugCaptureOverlay({
    super.key,
    required this.child,
    required this.boundaryKey,
    this.enabled = true,
    this.navigatorKey,
  });

  final Widget child;
  final GlobalKey boundaryKey;
  final bool enabled;
  /// Pass [GoRouter]'s `routerDelegate.navigatorKey` when using `MaterialApp.router` builder.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<VibeBugCaptureOverlay> createState() => _VibeBugCaptureOverlayState();
}

class _VibeBugCaptureOverlayState extends State<VibeBugCaptureOverlay> {
  final _inspector = const FlutterWidgetInspector();
  final _screenshots = const VibeBugScreenshotCapture();
  final _uuid = const Uuid();

  Offset _bubbleOffset = const Offset(20, 120);
  bool _picking = false;
  bool _pickingReady = false;
  bool _capturing = false;
  FlutterWidgetHit? _hoverHit;
  final List<VibeBugScreenshotShot> _draftShots = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBubbleOffset());
  }

  BuildContext? get _sheetContext =>
      widget.navigatorKey?.currentContext ?? context;

  Future<void> _loadBubbleOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('${_bubblePositionKey}_x');
    final y = prefs.getDouble('${_bubblePositionKey}_y');
    if (x != null && y != null && mounted) {
      setState(() => _bubbleOffset = Offset(x, y));
    }
  }

  Future<void> _saveBubbleOffset(Offset offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('${_bubblePositionKey}_x', offset.dx);
    await prefs.setDouble('${_bubblePositionKey}_y', offset.dy);
  }

  void _onBubbleMoved(Offset offset) {
    if (_bubbleOffset == offset) return;
    setState(() => _bubbleOffset = offset);
  }

  void _onBubbleDragEnded(Offset offset) {
    _onBubbleMoved(offset);
    unawaited(_saveBubbleOffset(offset));
  }

  void _startPicking() {
    if (!widget.enabled || !VibeBug.isInitialized || _capturing || _picking) return;
    setState(() {
      _picking = true;
      _pickingReady = false;
      _hoverHit = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_picking) return;
      setState(() => _pickingReady = true);
    });
  }

  void _stopPicking() {
    if (!mounted) return;
    setState(() {
      _picking = false;
      _pickingReady = false;
      _hoverHit = null;
    });
  }

  void _updateHover(Offset globalPosition) {
    final hit = _inspector.hitTestAt(
      globalPosition,
      routeContext: _sheetContext,
      boundaryKey: widget.boundaryKey,
    );
    if (!mounted) return;
    if (hit?.selector != _hoverHit?.selector ||
        hit?.globalRect != _hoverHit?.globalRect) {
      setState(() => _hoverHit = hit);
    }
  }

  Future<void> _captureAt(Offset globalPosition) async {
    if (_capturing) return;
    final hit = _inspector.hitTestAt(
      globalPosition,
      routeContext: _sheetContext,
      boundaryKey: widget.boundaryKey,
    );
    _stopPicking();
    if (hit == null) {
      _showSnack('Could not identify a widget at that position.');
      return;
    }
    if (_draftShots.length >= _maxCaptures) {
      _showSnack('Maximum $_maxCaptures screenshots per issue.');
      return;
    }

    setState(() => _capturing = true);
    final sheetContext = _sheetContext;
    final ratio = sheetContext != null
        ? MediaQuery.devicePixelRatioOf(sheetContext)
        : MediaQuery.devicePixelRatioOf(context);

    final pair = await _screenshots.capturePair(
      boundaryKey: widget.boundaryKey,
      globalRect: hit.globalRect,
      pixelRatio: ratio,
    );
    if (!mounted) return;
    setState(() => _capturing = false);

    if (pair == null || pair.fullDataUrl.isEmpty) {
      _showSnack('Screenshot capture failed. Try again after the screen settles.');
      return;
    }

    final note = await _promptCaptureNote(hit);
    if (!mounted) return;
    if (note == null) return;

    setState(() {
      _draftShots.add(
        VibeBugScreenshotShot(
          id: _uuid.v4(),
          description: note,
          selectedScreenshotDataUrl: pair.selectedDataUrl,
          fullScreenshotDataUrl: pair.fullDataUrl,
          pageUrl: hit.routeName.isNotEmpty ? 'flutter://${hit.routeName}' : 'flutter://screen',
          cssSelector: hit.selector,
          domText: hit.semanticsLabel,
          htmlSnippet: hit.widgetSnippet,
          elementTag: hit.widgetType,
          elementId: hit.widgetKey ?? '',
          viewportWidth: sheetContext != null
              ? MediaQuery.sizeOf(sheetContext).width.round()
              : 0,
          viewportHeight: sheetContext != null
              ? MediaQuery.sizeOf(sheetContext).height.round()
              : 0,
          elementRect: hit.globalRect,
        ),
      );
    });

    if (_draftShots.length < _maxCaptures) {
      final addAnother = await _askAddAnother();
      if (addAnother == true && mounted) {
        _startPicking();
      } else if (mounted) {
        await _openSubmitSheet();
      }
    } else {
      await _openSubmitSheet();
    }
  }

  Future<String?> _promptCaptureNote(FlutterWidgetHit hit) async {
    final navContext = _sheetContext;
    if (navContext == null) return null;

    final controller = TextEditingController(
      text: hit.semanticsLabel.isNotEmpty ? hit.semanticsLabel : '',
    );
    return showModalBottomSheet<String>(
      context: navContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Capture ${_draftShots.length + 1}', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Widget: ${hit.widgetType}', style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What is wrong with this widget?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  Navigator.pop(ctx, text.isEmpty ? hit.semanticsLabel : text);
                },
                child: const Text('Save capture'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _askAddAnother() async {
    final navContext = _sheetContext;
    if (navContext == null) return false;
    return showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Capture saved'),
        content: Text('${_draftShots.length}/$_maxCaptures screenshots added. Select another widget?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review & send')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add another')),
        ],
      ),
    );
  }

  Future<void> _openSubmitSheet() async {
    if (_draftShots.isEmpty) return;
    final navContext = _sheetContext;
    if (navContext == null) return;

    final summaryController = TextEditingController(
      text: _draftShots.first.description,
    );
    final sent = await showModalBottomSheet<bool>(
      context: navContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Send issue (${_draftShots.length} captures)', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _draftShots.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final shot = _draftShots[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _CaptureThumbnail(dataUrl: shot.selectedScreenshotDataUrl),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  setState(() => _draftShots.removeAt(index));
                                  setLocalState(() {});
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: summaryController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Issue summary',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _submitting ? null : () => Navigator.pop(ctx, true),
                    child: Text(_submitting ? 'Sending…' : 'Send to developer'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (sent == true && summaryController.text.trim().length >= 3) {
      await _submitIssue(summaryController.text.trim());
    }
    summaryController.dispose();
  }

  Future<void> _submitIssue(String summary) async {
    if (_draftShots.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final issueId = await VibeBug.reportIssueWithCaptures(
        summary: summary,
        captures: List<VibeBugScreenshotShot>.from(_draftShots),
      );
      if (!mounted) return;
      setState(() {
        _draftShots.clear();
        _submitting = false;
      });
      _showSnack(issueId == null ? 'Issue queued for retry.' : 'Issue sent ($issueId).');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      _showSnack('Failed to send issue: $e');
    }
  }

  void _showSnack(String message) {
    final navContext = _sheetContext;
    if (navContext == null || !navContext.mounted) return;
    ScaffoldMessenger.of(navContext).showSnackBar(SnackBar(content: Text(message)));
  }

  Rect? _highlightRectInOverlay(RenderBox overlayBox) {
    final hit = _hoverHit;
    if (hit == null) return null;
    return Rect.fromPoints(
      overlayBox.globalToLocal(hit.globalRect.topLeft),
      overlayBox.globalToLocal(hit.globalRect.bottomRight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_picking)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, _) {
                  final overlayBox = context.findRenderObject() as RenderBox?;
                  final highlightRect =
                      overlayBox == null ? null : _highlightRectInOverlay(overlayBox);

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            if (!_pickingReady) return;
                            final global = overlayBox?.localToGlobal(event.position) ?? event.position;
                            _updateHover(global);
                          },
                          onPointerMove: (event) {
                            if (!_pickingReady) return;
                            final global = overlayBox?.localToGlobal(event.position) ?? event.position;
                            _updateHover(global);
                          },
                          onPointerUp: (event) {
                            if (!_pickingReady) return;
                            final global = overlayBox?.localToGlobal(event.position) ?? event.position;
                            unawaited(_captureAt(global));
                          },
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(color: Color(0x33000000)),
                        ),
                      ),
                      if (highlightRect != null)
                        Positioned.fromRect(
                          rect: highlightRect,
                          child: const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.fromBorderSide(
                                  BorderSide(color: Color(0xFF60A5FA), width: 2),
                                ),
                                color: Color(0x2260A5FA),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        left: 16,
                        right: 16,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text('Tap the widget that looks wrong'),
                                ),
                                TextButton(onPressed: _stopPicking, child: const Text('Cancel')),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        if (_capturing)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (widget.enabled && !_picking && !_capturing)
          _DraggableReportBubble(
            offset: _bubbleOffset,
            draftCount: _draftShots.length,
            onOffsetChanged: _onBubbleMoved,
            onDragEnd: _onBubbleDragEnded,
            onTap: () {
              if (_draftShots.isNotEmpty) {
                unawaited(_openSubmitSheet());
              } else {
                _startPicking();
              }
            },
            onLongPress: () {
              if (_draftShots.isNotEmpty) {
                setState(() => _draftShots.clear());
                _showSnack('Draft captures cleared.');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _DraggableReportBubble extends StatefulWidget {
  const _DraggableReportBubble({
    required this.offset,
    required this.draftCount,
    required this.onOffsetChanged,
    required this.onDragEnd,
    required this.onTap,
    required this.onLongPress,
  });

  final Offset offset;
  final int draftCount;
  final ValueChanged<Offset> onOffsetChanged;
  final ValueChanged<Offset> onDragEnd;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_DraggableReportBubble> createState() => _DraggableReportBubbleState();
}

class _DraggableReportBubbleState extends State<_DraggableReportBubble> {
  Offset? _dragOrigin;
  Offset _panTotal = Offset.zero;
  Offset? _lastDragOffset;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final maxX = size.width - 120;
    final maxY = size.height - padding.bottom - 56;
    final dx = widget.offset.dx.clamp(8.0, maxX);
    final dy = widget.offset.dy.clamp(padding.top + 8, maxY);

    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress,
        onPanStart: (_) {
          _dragOrigin = widget.offset;
          _panTotal = Offset.zero;
          _lastDragOffset = widget.offset;
          _dragging = false;
        },
        onPanUpdate: (details) {
          if (_dragOrigin == null) return;
          _panTotal += details.delta;
          if (!_dragging && _panTotal.distance < _bubbleDragSlop) return;
          _dragging = true;
          final next = Offset(
            (_dragOrigin!.dx + _panTotal.dx).clamp(8.0, maxX),
            (_dragOrigin!.dy + _panTotal.dy).clamp(padding.top + 8, maxY),
          );
          _lastDragOffset = next;
          widget.onOffsetChanged(next);
        },
        onPanEnd: (_) {
          if (!_dragging) {
            widget.onTap();
          } else if (_lastDragOffset != null) {
            widget.onDragEnd(_lastDragOffset!);
          }
          _dragOrigin = null;
          _lastDragOffset = null;
          _panTotal = Offset.zero;
          _dragging = false;
        },
        onPanCancel: () {
          _dragOrigin = null;
          _lastDragOffset = null;
          _panTotal = Offset.zero;
          _dragging = false;
        },
        child: Material(
          elevation: 6,
          color: const Color(0xFF111827),
          shape: const StadiumBorder(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bug_report_outlined, color: Color(0xFFBEF264), size: 18),
                const SizedBox(width: 8),
                const Text('Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (widget.draftCount > 0) ...[
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFBEF264),
                    child: Text(
                      '${widget.draftCount}',
                      style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureThumbnail extends StatelessWidget {
  const _CaptureThumbnail({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    try {
      final encoded = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
      final bytes = base64Decode(encoded);
      return Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover);
    } catch (_) {
      return Container(
        width: 72,
        height: 72,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined, size: 18),
      );
    }
  }
}

/// Wraps your app with screenshot capture and the draggable VibeBug report button.
class VibeBugScope extends StatefulWidget {
  const VibeBugScope({
    super.key,
    required this.child,
    this.showReportButton = true,
    this.navigatorKey,
  });

  final Widget child;
  final bool showReportButton;
  /// Required for modals when [VibeBugScope] is used inside `MaterialApp.router` builder.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<VibeBugScope> createState() => _VibeBugScopeState();
}

class _VibeBugScopeState extends State<VibeBugScope> {
  final _boundaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return VibeBugCaptureOverlay(
      boundaryKey: _boundaryKey,
      enabled: widget.showReportButton,
      navigatorKey: widget.navigatorKey,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: widget.child,
      ),
    );
  }
}
