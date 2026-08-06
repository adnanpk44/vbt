import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../vibebug.dart';
import '../api_client.dart';
import '../onboarding/vibebug_auth_gate.dart';
import '../onboarding/vibebug_auth_widgets.dart';
import '../onboarding/vibebug_login_screen.dart';
import '../onboarding/vibebug_project_picker_screen.dart';
import 'capture_models.dart';
import 'capture_region_editor.dart';
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
  bool _capturing = false;
  FlutterWidgetHit? _hoverHit;
  final List<VibeBugScreenshotShot> _draftShots = [];
  bool _submitting = false;
  OverlayEntry? _pickerOverlay;
  RenderObject? _pickerExcludeRoot;

  @override
  void initState() {
    super.initState();
    // Defer prefs until after the first frame so platform plugins are registered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadBubbleOffset());
    });
  }

  BuildContext? get _navContext =>
      widget.navigatorKey?.currentContext ?? context;

  OverlayState? get _navigatorOverlay {
    final fromKey = widget.navigatorKey?.currentState?.overlay;
    if (fromKey != null) return fromKey;

    final nav = _navContext;
    if (nav != null) {
      final fromNav = Overlay.maybeOf(nav, rootOverlay: true);
      if (fromNav != null) return fromNav;
    }

    return Overlay.maybeOf(context, rootOverlay: true);
  }

  @override
  void dispose() {
    _removePickerOverlay();
    super.dispose();
  }

  void _removePickerOverlay() {
    _pickerOverlay?.remove();
    _pickerOverlay = null;
    _pickerExcludeRoot = null;
  }

  Future<void> _loadBubbleOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble('${_bubblePositionKey}_x');
      final y = prefs.getDouble('${_bubblePositionKey}_y');
      if (x == null || y == null || !mounted) return;
      // Ignore corrupt / absurd persisted values.
      if (!x.isFinite || !y.isFinite) return;
      setState(() => _bubbleOffset = Offset(x, y));
    } catch (_) {
      // Keep default bubble position if prefs are unavailable (plugin not ready, etc.).
    }
  }

  Future<void> _saveBubbleOffset(Offset offset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${_bubblePositionKey}_x', offset.dx);
      await prefs.setDouble('${_bubblePositionKey}_y', offset.dy);
    } catch (_) {
      // Persistence is best-effort; drag still works in-session.
    }
  }

  void _onBubbleMoved(Offset offset) {
    if (_bubbleOffset == offset) return;
    setState(() => _bubbleOffset = offset);
  }

  void _onBubbleDragEnded(Offset offset) {
    _onBubbleMoved(offset);
    unawaited(_saveBubbleOffset(offset));
  }

  Future<void> _startPicking() async {
    if (!widget.enabled || !VibeBug.isInitialized || _capturing || _picking) {
      return;
    }

    if (VibeBug.needsOnDemandGate) {
      final ready = await _ensureReadyToReport();
      if (!ready || !mounted) return;
    }

    final overlay = _navigatorOverlay;
    if (overlay == null) {
      _showSnack(
          'Could not open widget picker. Pass navigatorKey to VibeBugScope.');
      return;
    }

    setState(() {
      _picking = true;
      _hoverHit = null;
    });

    _pickerOverlay = OverlayEntry(
      builder: (overlayContext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pickerExcludeRoot = overlayContext.findRenderObject();
        });
        return _buildPickerOverlay(overlayContext);
      },
    );
    overlay.insert(_pickerOverlay!);
  }

  /// Runs the on-demand sign-in/project-picker flow the first time the
  /// Report button is tapped (see [VibeBugOptions.blockAppUntilReady]),
  /// pushing full-screen routes on the host app's own Navigator — unlike
  /// [VibeBugScope]'s startup gate, there's a real Navigator/Overlay here
  /// already, since the app is already running normally.
  ///
  /// Returns false if the user backs out of either screen (cancelled sign-in,
  /// or signed out from the picker) without completing it.
  Future<bool> _ensureReadyToReport() async {
    final navState = widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navState == null) {
      _showSnack('Could not open sign-in. Pass navigatorKey to VibeBugScope.');
      return false;
    }

    if (!VibeBug.isAuthenticated) {
      final signedIn = await navState.push<bool>(
        MaterialPageRoute(
          builder: (routeContext) => VibeBugLoginScreen(
            onSignedIn: (_) => Navigator.of(routeContext).pop(true),
          ),
        ),
      );
      if (signedIn != true || !mounted) return false;
    }

    if (VibeBug.selectedProjectId == null) {
      final selected = await navState.push<bool>(
        MaterialPageRoute(
          builder: (routeContext) => VibeBugProjectPickerScreen(
            projects: VibeBug.projects,
            onProjectSelected: (id) async {
              await VibeBug.selectProject(id);
              if (routeContext.mounted) Navigator.of(routeContext).pop(true);
            },
            onSignOut: () async {
              await VibeBug.signOut();
              if (routeContext.mounted) Navigator.of(routeContext).pop(false);
            },
          ),
        ),
      );
      if (selected != true || !mounted) return false;
    }

    return true;
  }

  void _stopPicking() {
    _removePickerOverlay();
    if (!mounted) return;
    setState(() {
      _picking = false;
      _hoverHit = null;
    });
  }

  void _updateHover(Offset globalPosition) {
    final hit = _inspector.hitTestAt(
      globalPosition,
      routeContext: _navContext,
      boundaryKey: widget.boundaryKey,
      excludeSubtreeRoot: _pickerExcludeRoot,
    );
    if (!mounted) return;
    if (hit?.selector != _hoverHit?.selector ||
        hit?.globalRect != _hoverHit?.globalRect) {
      _hoverHit = hit;
      _pickerOverlay?.markNeedsBuild();
    }
  }

  Future<void> _captureAt(Offset globalPosition) async {
    if (_capturing) return;

    final hit = _hoverHit ??
        _inspector.hitTestAt(
          globalPosition,
          routeContext: _navContext,
          boundaryKey: widget.boundaryKey,
          excludeSubtreeRoot: _pickerExcludeRoot,
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

    final navContext = _navContext;
    if (navContext == null) return;

    setState(() => _capturing = true);
    final ratio = MediaQuery.devicePixelRatioOf(navContext);

    final full = await _screenshots.captureFull(
      boundaryKey: widget.boundaryKey,
      pixelRatio: ratio,
    );
    if (!mounted) return;
    setState(() => _capturing = false);

    if (full == null || full.fullDataUrl.isEmpty) {
      _showSnack(
          'Screenshot capture failed. Try again after the screen settles.');
      return;
    }

    final initialCrop = _screenshots.globalRectToBoundaryLocal(
      boundaryKey: widget.boundaryKey,
      globalRect: hit.globalRect,
    );

    final editorNav = _navContext;
    if (editorNav == null || !editorNav.mounted) return;

    final editorResult = await CaptureRegionEditor.open(
      context: editorNav,
      fullDataUrl: full.fullDataUrl,
      imageLogicalSize: full.logicalSize,
      initialCropRect: initialCrop,
      pixelRatio: full.pixelRatio,
      hit: hit,
      captureIndex: _draftShots.length + 1,
    );

    if (!mounted || editorResult == null) return;

    final globalCropRect = _screenshots.boundaryLocalToGlobal(
      boundaryKey: widget.boundaryKey,
      localRect: editorResult.elementRect,
    );

    setState(() {
      _draftShots.add(
        VibeBugScreenshotShot(
          id: _uuid.v4(),
          description: editorResult.description,
          selectedScreenshotDataUrl: editorResult.selectedScreenshotDataUrl,
          fullScreenshotDataUrl: editorResult.fullScreenshotDataUrl,
          pageUrl: hit.routeName.isNotEmpty
              ? 'flutter://${hit.routeName}'
              : 'flutter://screen',
          cssSelector: hit.selector,
          domText: hit.semanticsLabel,
          htmlSnippet: hit.widgetSnippet,
          elementTag: hit.widgetType,
          elementClasses: hit.ancestorTrail.join(' '),
          elementId: hit.widgetKey ?? '',
          viewportWidth: MediaQuery.sizeOf(navContext).width.round(),
          viewportHeight: MediaQuery.sizeOf(navContext).height.round(),
          elementRect: globalCropRect,
        ),
      );
    });

    if (_draftShots.length < _maxCaptures) {
      _showCaptureSavedSnack();
    } else {
      await _openSubmitSheet();
    }
  }

  void _showCaptureSavedSnack() {
    final navContext = _navContext;
    if (navContext == null || !navContext.mounted) return;
    ScaffoldMessenger.of(navContext).hideCurrentSnackBar();
    ScaffoldMessenger.of(navContext).showSnackBar(
      SnackBar(
        content: Text(
          '${_draftShots.length}/$_maxCaptures captured. Navigate freely, tap Report to add more.',
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Review & send',
          onPressed: () => unawaited(_openSubmitSheet()),
        ),
      ),
    );
  }

  Future<void> _openSubmitSheet() async {
    if (_draftShots.isEmpty) return;
    final navContext = _navContext;
    if (navContext == null) return;

    final result = await showModalBottomSheet<_SubmitSheetResult>(
      context: navContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _SubmitIssueSheet(
        shots: List<VibeBugScreenshotShot>.from(_draftShots),
        submitting: _submitting,
      ),
    );

    if (!mounted || result == null) return;

    if (result.shots.isEmpty) {
      setState(() => _draftShots.clear());
      return;
    }

    setState(() => _draftShots
      ..clear()
      ..addAll(result.shots));

    if (result.send && result.summary.trim().length >= 3) {
      await _submitIssue(result.summary.trim(), result.shots, result);
    }
  }

  Future<void> _submitIssue(String summary, List<VibeBugScreenshotShot> shots,
      _SubmitSheetResult target) async {
    if (shots.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final issueId = await VibeBug.reportIssueWithCaptures(
        summary: summary,
        captures: shots,
        priority: target.priority,
        projectId: target.projectId,
        boardId: target.boardId,
        assignedTo: target.assignedTo,
      );
      if (!mounted) return;
      setState(() {
        _draftShots.clear();
        _submitting = false;
      });
      _showSnack(issueId == null
          ? 'Issue queued for retry.'
          : 'Issue sent ($issueId).');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      _showSnack('Failed to send issue: $e');
    }
  }

  void _showSnack(String message) {
    final navContext = _navContext;
    if (navContext == null || !navContext.mounted) return;
    ScaffoldMessenger.of(navContext)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Rect? _highlightRectInOverlay(RenderBox overlayBox) {
    final hit = _hoverHit;
    if (hit == null) return null;
    return Rect.fromPoints(
      overlayBox.globalToLocal(hit.globalRect.topLeft),
      overlayBox.globalToLocal(hit.globalRect.bottomRight),
    );
  }

  Widget _buildPickerOverlay(BuildContext overlayContext) {
    final overlayBox = overlayContext.findRenderObject() as RenderBox?;
    final highlightRect =
        overlayBox == null ? null : _highlightRectInOverlay(overlayBox);
    final topPadding = MediaQuery.paddingOf(overlayContext).top;

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x55000000)),
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                // PointerEvent.position is already in global logical coordinates.
                _updateHover(event.position);
              },
              onPointerMove: (event) {
                _updateHover(event.position);
              },
              onPointerUp: (event) {
                unawaited(_captureAt(event.position));
              },
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
              top: topPadding + 8,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _draftShots.isEmpty
                              ? 'Tap the widget that looks wrong'
                              : 'Tap widget (${_draftShots.length}/$_maxCaptures captured)',
                        ),
                      ),
                      TextButton(
                          onPressed: _stopPicking, child: const Text('Cancel')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
              onTap: _startPicking,
              onReview: () => unawaited(_openSubmitSheet()),
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

class _SubmitSheetResult {
  const _SubmitSheetResult({
    required this.shots,
    required this.summary,
    required this.send,
    this.projectId,
    this.boardId,
    this.assignedTo,
    this.priority = 'medium',
  });

  final List<VibeBugScreenshotShot> shots;
  final String summary;
  final bool send;
  final String? projectId;
  final String? boardId;
  final String? assignedTo;
  final String priority;
}

class _SubmitIssueSheet extends StatefulWidget {
  const _SubmitIssueSheet({
    required this.shots,
    required this.submitting,
  });

  final List<VibeBugScreenshotShot> shots;
  final bool submitting;

  @override
  State<_SubmitIssueSheet> createState() => _SubmitIssueSheetState();
}

class _SubmitIssueSheetState extends State<_SubmitIssueSheet> {
  late List<VibeBugScreenshotShot> _shots;
  late final TextEditingController _summaryController;
  final Map<String, TextEditingController> _descControllers = {};
  List<VibeBugProject> _projects = const [];
  List<VibeBugBoard> _boards = const [];
  List<VibeBugDeveloper> _developers = const [];
  String? _projectId;
  String? _boardId;
  String? _developerId;
  String _priority = 'medium';
  bool _loadingTarget = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _shots = List.from(widget.shots);
    _summaryController = TextEditingController(
      text: _shots.isNotEmpty ? _shots.first.description : '',
    );
    for (final shot in _shots) {
      _descControllers[shot.id] = TextEditingController(text: shot.description);
    }
    _hydrateTargetOptions();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    for (final c in _descControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeShot(String id) {
    final controller = _descControllers.remove(id);
    controller?.dispose();
    setState(() {
      _shots.removeWhere((s) => s.id == id);
      if (_shots.isEmpty) {
        Navigator.of(context)
            .pop(const _SubmitSheetResult(shots: [], summary: '', send: false));
      }
    });
  }

  void _updateShotDescription(String id, String text) {
    final index = _shots.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _shots[index] = VibeBugScreenshotShot(
      id: _shots[index].id,
      description: text,
      selectedScreenshotDataUrl: _shots[index].selectedScreenshotDataUrl,
      fullScreenshotDataUrl: _shots[index].fullScreenshotDataUrl,
      pageUrl: _shots[index].pageUrl,
      cssSelector: _shots[index].cssSelector,
      domText: _shots[index].domText,
      htmlSnippet: _shots[index].htmlSnippet,
      elementTag: _shots[index].elementTag,
      elementClasses: _shots[index].elementClasses,
      elementId: _shots[index].elementId,
      viewportWidth: _shots[index].viewportWidth,
      viewportHeight: _shots[index].viewportHeight,
      elementRect: _shots[index].elementRect,
      attachments: _shots[index].attachments,
    );
  }

  List<VibeBugScreenshotShot> _collectShots() {
    return _shots.map((shot) {
      final desc = _descControllers[shot.id]?.text.trim() ?? shot.description;
      return VibeBugScreenshotShot(
        id: shot.id,
        description: desc,
        selectedScreenshotDataUrl: shot.selectedScreenshotDataUrl,
        fullScreenshotDataUrl: shot.fullScreenshotDataUrl,
        pageUrl: shot.pageUrl,
        cssSelector: shot.cssSelector,
        domText: shot.domText,
        htmlSnippet: shot.htmlSnippet,
        elementTag: shot.elementTag,
        elementClasses: shot.elementClasses,
        elementId: shot.elementId,
        viewportWidth: shot.viewportWidth,
        viewportHeight: shot.viewportHeight,
        elementRect: shot.elementRect,
        attachments: shot.attachments,
      );
    }).toList();
  }

  void _trySend() {
    final summary = _summaryController.text.trim();
    final collected = _collectShots();

    if (summary.length < 3) {
      setState(() => _error = 'Issue summary must be at least 3 characters.');
      return;
    }
    for (var i = 0; i < collected.length; i++) {
      if (collected[i].description.trim().isEmpty) {
        setState(() => _error = 'Add a description for screenshot ${i + 1}.');
        return;
      }
    }
    if (_projectId == null || _projectId!.isEmpty) {
      setState(() => _error = VibeBug.isAuthenticated
          ? 'Select a tester project.'
          : 'Sign in before sending an issue.');
      return;
    }
    if (_boardId == null || _boardId!.isEmpty) {
      setState(() => _error = 'Select a board for this issue.');
      return;
    }
    if (_developerId == null || _developerId!.isEmpty) {
      setState(() => _error = 'Select a developer for this issue.');
      return;
    }

    Navigator.of(context).pop(
      _SubmitSheetResult(
        shots: collected,
        summary: summary,
        send: true,
        projectId: _projectId,
        boardId: _boardId,
        assignedTo: _developerId,
        priority: _priority,
      ),
    );
  }

  Future<void> _hydrateTargetOptions() async {
    setState(() {
      // VibeBug.projects is already canActAsTester-filtered at the source.
      _projects = VibeBug.projects;
      _projectId = VibeBug.selectedProjectId ??
          (_projects.isNotEmpty ? _projects.first.id : null);
      _boards = VibeBug.boards;
      _developers = VibeBug.developers;
      _boardId = VibeBug.selectedBoardId ??
          (_boards.isNotEmpty ? _boards.first.id : null);
      _developerId = VibeBug.selectedDeveloperId ??
          (_developers.isNotEmpty ? _developers.first.id : null);
    });
    if (_projectId != null &&
        _projects.any((project) => project.id == _projectId)) {
      await _changeProject(_projectId!, showLoading: false);
    }
  }

  Future<void> _changeProject(String projectId,
      {bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loadingTarget = true;
        _error = null;
        _projectId = projectId;
      });
    }
    try {
      await VibeBug.selectProject(projectId);
      if (!mounted) return;
      setState(() {
        _projectId = projectId;
        _boards = VibeBug.boards;
        _developers = VibeBug.developers;
        _boardId = VibeBug.selectedBoardId ??
            (_boards.isNotEmpty ? _boards.first.id : null);
        _developerId = VibeBug.selectedDeveloperId ??
            (_developers.isNotEmpty ? _developers.first.id : null);
        _loadingTarget = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTarget = false;
        _error = 'Could not load project options: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send issue (${_shots.length} captures)',
                  style: Theme.of(ctx).textTheme.titleLarge),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              if (VibeBug.isAuthenticated)
                _buildTargetControls(ctx)
              else
                _buildSignInControls(ctx),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _shots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final shot = _shots[index];
                    return _DraftShotCard(
                      index: index,
                      shot: shot,
                      descController: _descControllers[shot.id]!,
                      onDescriptionChanged: (text) =>
                          _updateShotDescription(shot.id, text),
                      onRemove: () => _removeShot(shot.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _summaryController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Issue summary',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.submitting ||
                        _loadingTarget ||
                        !VibeBug.isAuthenticated
                    ? null
                    : _trySend,
                child:
                    Text(widget.submitting ? 'Sending…' : 'Send to developer'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTargetControls(BuildContext context) {
    const decoration = InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _targetDropdown<String>(
          key: ValueKey('project-$_projectId-${_projects.length}'),
          value: _projects.any((project) => project.id == _projectId)
              ? _projectId
              : null,
          labels: _projects.map((project) => project.name).toList(),
          values: _projects.map((project) => project.id).toList(),
          onChanged: _loadingTarget
              ? null
              : (value) {
                  if (value != null) unawaited(_changeProject(value));
                },
          decoration: decoration.copyWith(labelText: 'Project'),
        ),
        const SizedBox(height: 8),
        _targetDropdown<String>(
          key: ValueKey('board-$_projectId-$_boardId-${_boards.length}'),
          value: _boards.any((board) => board.id == _boardId) ? _boardId : null,
          labels: _boards
              .map((board) => board.cardCount > 0
                  ? '${board.name} (${board.cardCount})'
                  : board.name)
              .toList(),
          values: _boards.map((board) => board.id).toList(),
          onChanged: _loadingTarget
              ? null
              : (value) => setState(() {
                    _boardId = value;
                    if (value != null) VibeBug.selectBoard(value);
                  }),
          decoration: decoration.copyWith(labelText: 'Board'),
        ),
        const SizedBox(height: 8),
        _targetDropdown<String>(
          key: ValueKey(
              'developer-$_projectId-$_developerId-${_developers.length}'),
          value: _developers.any((developer) => developer.id == _developerId)
              ? _developerId
              : null,
          labels: _developers.map((developer) => developer.name).toList(),
          values: _developers.map((developer) => developer.id).toList(),
          onChanged: _loadingTarget
              ? null
              : (value) => setState(() {
                    _developerId = value;
                    if (value != null) VibeBug.selectDeveloper(value);
                  }),
          decoration: decoration.copyWith(labelText: 'Developer'),
        ),
        const SizedBox(height: 8),
        _targetDropdown<String>(
          key: ValueKey('priority-$_priority'),
          value: _priority,
          labels: const ['Low', 'Medium', 'High', 'Immediate'],
          values: const ['low', 'medium', 'high', 'immediate'],
          onChanged: _loadingTarget
              ? null
              : (value) => setState(() => _priority = value ?? 'medium'),
          decoration: decoration.copyWith(labelText: 'Priority'),
        ),
        if (_loadingTarget) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }

  Widget _targetDropdown<T>({
    required Key key,
    required T? value,
    required List<String> labels,
    required List<T> values,
    required ValueChanged<T?>? onChanged,
    required InputDecoration decoration,
  }) {
    assert(labels.length == values.length);
    return DropdownButtonFormField<T>(
      key: key,
      isExpanded: true,
      initialValue: value,
      items: List<DropdownMenuItem<T>>.generate(
        values.length,
        (index) => DropdownMenuItem<T>(
          value: values[index],
          child: Text(
            labels[index],
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
      selectedItemBuilder: (context) => List<Widget>.generate(
        values.length,
        (index) => Align(
          alignment: Alignment.centerLeft,
          child: Text(
            labels[index],
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
      onChanged: onChanged,
      decoration: decoration,
    );
  }

  Widget _buildSignInControls(BuildContext context) {
    return VibeBugSignInForm(
      emailLabel: 'Tester email',
      onSignedIn: (_) => unawaited(_hydrateTargetOptions()),
    );
  }
}

class _DraftShotCard extends StatelessWidget {
  const _DraftShotCard({
    required this.index,
    required this.shot,
    required this.descController,
    required this.onDescriptionChanged,
    required this.onRemove,
  });

  final int index;
  final VibeBugScreenshotShot shot;
  final TextEditingController descController;
  final ValueChanged<String> onDescriptionChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Screenshot ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _CaptureThumbnail(
                            dataUrl: shot.selectedScreenshotDataUrl,
                            height: 72),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Full context',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _CaptureThumbnail(
                            dataUrl: shot.fullScreenshotDataUrl, height: 72),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              shot.pageUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              shot.cssSelector,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              maxLines: 2,
              onChanged: onDescriptionChanged,
              decoration: const InputDecoration(
                labelText: 'Description for this screenshot',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
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
    required this.onReview,
    required this.onLongPress,
  });

  final Offset offset;
  final int draftCount;
  final ValueChanged<Offset> onOffsetChanged;
  final ValueChanged<Offset> onDragEnd;
  final VoidCallback onTap;
  final VoidCallback onReview;
  final VoidCallback onLongPress;

  @override
  State<_DraggableReportBubble> createState() => _DraggableReportBubbleState();
}

class _DraggableReportBubbleState extends State<_DraggableReportBubble> {
  int? _activePointer;
  Offset? _dragOrigin;
  Offset _panTotal = Offset.zero;
  Offset? _lastDragOffset;
  bool _dragging = false;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _resetPointer() {
    _activePointer = null;
    _dragOrigin = null;
    _panTotal = Offset.zero;
    _lastDragOffset = null;
    _dragging = false;
    _longPressFired = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    // MediaQuery briefly reports a zero/near-zero size on the very first
    // frame on some devices, which would otherwise make maxX/maxY smaller
    // than clamp()'s lower bound and throw. Never let the upper bound drop
    // below the lower one.
    final maxX = math.max(8.0, size.width - 120);
    final maxY = math.max(padding.top + 8, size.height - padding.bottom - 56);
    final dx = widget.offset.dx.clamp(8.0, maxX);
    final dy = widget.offset.dy.clamp(padding.top + 8, maxY);

    return Positioned(
      left: dx,
      top: dy,
      child: Material(
        elevation: 6,
        color: const Color(0xFF111827),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _activePointer = event.pointer;
                  _dragOrigin = widget.offset;
                  _panTotal = Offset.zero;
                  _lastDragOffset = widget.offset;
                  _dragging = false;
                  _longPressFired = false;
                  _longPressTimer?.cancel();
                  _longPressTimer =
                      Timer(const Duration(milliseconds: 500), () {
                    if (_activePointer != null && !_dragging) {
                      _longPressFired = true;
                      widget.onLongPress();
                    }
                  });
                },
                onPointerMove: (event) {
                  if (event.pointer != _activePointer || _dragOrigin == null) {
                    return;
                  }
                  _panTotal += event.delta;
                  if (!_dragging && _panTotal.distance < _bubbleDragSlop) {
                    return;
                  }
                  if (!_dragging) {
                    _longPressTimer?.cancel();
                    _dragging = true;
                  }
                  final next = Offset(
                    (_dragOrigin!.dx + _panTotal.dx).clamp(8.0, maxX),
                    (_dragOrigin!.dy + _panTotal.dy)
                        .clamp(padding.top + 8, maxY),
                  );
                  _lastDragOffset = next;
                  widget.onOffsetChanged(next);
                },
                onPointerUp: (event) {
                  if (event.pointer != _activePointer) return;
                  _longPressTimer?.cancel();
                  if (!_longPressFired) {
                    if (!_dragging) {
                      widget.onTap();
                    } else if (_lastDragOffset != null) {
                      widget.onDragEnd(_lastDragOffset!);
                    }
                  }
                  _resetPointer();
                },
                onPointerCancel: (event) {
                  if (event.pointer != _activePointer) return;
                  _longPressTimer?.cancel();
                  _resetPointer();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bug_report_outlined,
                        color: Color(0xFFBEF264), size: 18),
                    SizedBox(width: 8),
                    Text('Report',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (widget.draftCount > 0) ...[
                const SizedBox(width: 8),
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerUp: (_) => widget.onReview(),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFFBEF264),
                    child: Text(
                      '${widget.draftCount}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureThumbnail extends StatelessWidget {
  const _CaptureThumbnail({
    required this.dataUrl,
    this.height = 72,
  });

  final String dataUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (dataUrl.isEmpty) {
      return _placeholder(height);
    }
    try {
      final encoded = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return _placeholder(height);
      return Image.memory(
        bytes,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(height),
      );
    } catch (_) {
      return _placeholder(height);
    }
  }

  Widget _placeholder(double h) {
    return Container(
      width: double.infinity,
      height: h,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, size: 18),
    );
  }
}

/// Wraps your app with screenshot capture and the draggable VibeBug report
/// button.
///
/// When the SDK's built-in gate is enabled (see [VibeBugOptions.enableAuthGate]
/// — on by default for the zero-config setup produced by
/// `dart run vibebug_flutter:configure`), this also shows a full-screen
/// sign-in screen and project picker before your [child] is ever built, and
/// automatically switches back to sign-in after [VibeBug.signOut].
class VibeBugScope extends StatefulWidget {
  const VibeBugScope({
    super.key,
    required this.child,
    this.showReportButton = true,
    this.navigatorKey,
    this.loadingBuilder,
  });

  final Widget child;
  final bool showReportButton;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Overrides the brief splash shown while [VibeBugGateStage.autoSelecting]
  /// resolves. Defaults to [VibeBugGateLoading].
  final WidgetBuilder? loadingBuilder;

  @override
  State<VibeBugScope> createState() => _VibeBugScopeState();
}

class _VibeBugScopeState extends State<VibeBugScope> {
  final _boundaryKey = GlobalKey();
  bool _autoSelecting = false;

  /// Gate screens fully replace [VibeBugScope.child] — the widget MaterialApp
  /// normally builds from `home:`/`routes:`, which is where the app's real
  /// Navigator (and the Overlay it hosts) lives. Without that, anything the
  /// screen needs from an Overlay/Navigator ancestor — a TextField's
  /// selection toolbar, the project dropdown's popup menu — throws
  /// "No Overlay widget found". Wrapping in our own Navigator makes the
  /// gate self-contained: it works the same regardless of how the host
  /// app is structured.
  Widget _isolatedGateScreen(Widget screen) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VibeBug.listenable,
      builder: (context, _) {
        if (VibeBug.isGateEnabled && VibeBug.blockAppUntilReady) {
          final stage = resolveGateStage(
            gateEnabled: true,
            authenticated: VibeBug.isAuthenticated,
            hasSelectedProject: VibeBug.selectedProjectId != null,
            autoSelectSoleProject: VibeBug.autoSelectSoleProject,
            projectCount: VibeBug.projects.length,
          );
          switch (stage) {
            case VibeBugGateStage.signIn:
              return _isolatedGateScreen(const VibeBugLoginScreen());
            case VibeBugGateStage.projectPicker:
              return _isolatedGateScreen(VibeBugProjectPickerScreen(
                projects: VibeBug.projects,
                onProjectSelected: VibeBug.selectProject,
                onSignOut: VibeBug.signOut,
              ));
            case VibeBugGateStage.autoSelecting:
              if (!_autoSelecting) {
                _autoSelecting = true;
                unawaited(
                  VibeBug.selectProject(VibeBug.projects.first.id)
                      .whenComplete(() => _autoSelecting = false),
                );
              }
              return _isolatedGateScreen(
                widget.loadingBuilder?.call(context) ?? const VibeBugGateLoading(),
              );
            case VibeBugGateStage.none:
              break;
          }
        }
        return VibeBugCaptureOverlay(
          boundaryKey: _boundaryKey,
          enabled: widget.showReportButton,
          navigatorKey: widget.navigatorKey,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: widget.child,
          ),
        );
      },
    );
  }
}
