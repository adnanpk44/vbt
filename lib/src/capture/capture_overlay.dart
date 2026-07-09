import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../vibebug.dart';
import 'capture_models.dart';
import 'screenshot_capture.dart';
import 'widget_inspector.dart';

const _maxCaptures = 8;
const _bubblePositionKey = 'vibebug_bubble_offset';

/// Draggable report button + widget picker + multi-screenshot issue composer.
class VibeBugCaptureOverlay extends StatefulWidget {
  const VibeBugCaptureOverlay({
    super.key,
    required this.child,
    required this.boundaryKey,
    this.enabled = true,
  });

  final Widget child;
  final GlobalKey boundaryKey;
  final bool enabled;

  @override
  State<VibeBugCaptureOverlay> createState() => _VibeBugCaptureOverlayState();
}

class _VibeBugCaptureOverlayState extends State<VibeBugCaptureOverlay> {
  final _inspector = const FlutterWidgetInspector();
  final _screenshots = const VibeBugScreenshotCapture();
  final _uuid = const Uuid();

  Offset _bubbleOffset = const Offset(20, 120);
  bool _picking = false;
  FlutterWidgetHit? _hoverHit;
  final List<VibeBugScreenshotShot> _draftShots = [];
  bool _submitting = false;
  PointerRoute? _pointerRoute;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBubbleOffset());
  }

  @override
  void dispose() {
    _stopPicking();
    super.dispose();
  }

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

  void _startPicking() {
    if (!widget.enabled || !VibeBug.isInitialized) return;
    setState(() {
      _picking = true;
      _hoverHit = null;
    });
    _pointerRoute = _handlePointerEvent;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerRoute!);
  }

  void _stopPicking() {
    if (_pointerRoute != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerRoute!);
      _pointerRoute = null;
    }
    if (mounted) {
      setState(() {
        _picking = false;
        _hoverHit = null;
      });
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (!_picking) return;
    if (event is PointerHoverEvent || (event is PointerMoveEvent && event.down)) {
      final hit = _inspector.hitTestAt(event.position, routeContext: context);
      if (mounted) setState(() => _hoverHit = hit);
    } else if (event is PointerUpEvent) {
      unawaited(_captureAt(event.position));
    }
  }

  Future<void> _captureAt(Offset position) async {
    final hit = _inspector.hitTestAt(position, routeContext: context);
    _stopPicking();
    if (hit == null) {
      _showSnack('Could not identify a widget at that position.');
      return;
    }
    if (_draftShots.length >= _maxCaptures) {
      _showSnack('Maximum $_maxCaptures screenshots per issue.');
      return;
    }

    final ratio = MediaQuery.devicePixelRatioOf(context);
    final pair = await _screenshots.capturePair(
      boundaryKey: widget.boundaryKey,
      globalRect: hit.globalRect,
      pixelRatio: ratio,
    );
    if (pair == null || pair.fullDataUrl.isEmpty) {
      _showSnack('Screenshot capture failed. Wrap your app with VibeBugScope.');
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
          viewportWidth: MediaQuery.sizeOf(context).width.round(),
          viewportHeight: MediaQuery.sizeOf(context).height.round(),
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

  Future<String?> _promptCaptureNote(FlutterWidgetHit hit) {
    final controller = TextEditingController(
      text: hit.semanticsLabel.isNotEmpty ? hit.semanticsLabel : '',
    );
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
              Text('Capture ${ _draftShots.length + 1 }', style: Theme.of(ctx).textTheme.titleMedium),
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
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save capture'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _askAddAnother() {
    return showDialog<bool>(
      context: context,
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
    final summaryController = TextEditingController(
      text: _draftShots.first.description,
    );
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_picking) ...[
          const ModalBarrier(dismissible: false, color: Color(0x33000000)),
          if (_hoverHit != null)
            Positioned.fromRect(
              rect: _hoverHit!.globalRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF60A5FA), width: 2),
                    color: const Color(0x2260A5FA),
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
                    const Expanded(child: Text('Tap a widget to capture it. Esc cancel not available on mobile — use Cancel.')),
                    TextButton(onPressed: _stopPicking, child: const Text('Cancel')),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (widget.enabled && !_picking)
          _DraggableReportBubble(
            offset: _bubbleOffset,
            draftCount: _draftShots.length,
            onOffsetChanged: (offset) {
              setState(() => _bubbleOffset = offset);
              unawaited(_saveBubbleOffset(offset));
            },
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
    );
  }
}

class _DraggableReportBubble extends StatefulWidget {
  const _DraggableReportBubble({
    required this.offset,
    required this.draftCount,
    required this.onOffsetChanged,
    required this.onTap,
    required this.onLongPress,
  });

  final Offset offset;
  final int draftCount;
  final ValueChanged<Offset> onOffsetChanged;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_DraggableReportBubble> createState() => _DraggableReportBubbleState();
}

class _DraggableReportBubbleState extends State<_DraggableReportBubble> {
  Offset? _dragOrigin;
  bool _moved = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final maxX = size.width - 72;
    final maxY = size.height - padding.bottom - 72;
    final dx = widget.offset.dx.clamp(8.0, maxX);
    final dy = widget.offset.dy.clamp(padding.top + 8, maxY);

    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        onPanStart: (details) {
          _dragOrigin = widget.offset;
          _moved = false;
        },
        onPanUpdate: (details) {
          if (_dragOrigin == null) return;
          _moved = true;
          final next = Offset(
            (_dragOrigin!.dx + details.delta.dx).clamp(8.0, maxX),
            (_dragOrigin!.dy + details.delta.dy).clamp(padding.top + 8, maxY),
          );
          widget.onOffsetChanged(next);
        },
        onPanEnd: (_) {
          if (!_moved) {
            widget.onTap();
          }
          _dragOrigin = null;
        },
        onLongPress: widget.onLongPress,
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
  });

  final Widget child;
  final bool showReportButton;

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
      child: RepaintBoundary(
        key: _boundaryKey,
        child: widget.child,
      ),
    );
  }
}
