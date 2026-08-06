import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'capture/capture_models.dart';
import 'capture/capture_overlay.dart';
import 'issue_queue.dart';
import 'vibebug_exception.dart';
import 'vibebug_options.dart';

/// Crash and live-issue reporting for Vibe Bug Tracker.
class VibeBug {
  VibeBug._();

  static final VibeBug instance = VibeBug._();

  static VibeBugOptions? _options;
  static VibeBugApiClient? _api;
  static IssueQueue? _queue;
  static SharedPreferences? _prefs;
  static String? _token;
  static String? _projectId;
  static String? _boardId;
  static String? _assignedTo;
  static List<VibeBugProject> _projects = const [];
  static List<VibeBugBoard> _boards = const [];
  static List<VibeBugDeveloper> _developers = const [];
  static bool _initialized = false;
  static bool _gateEnabled = false;
  static FlutterErrorDetails? _lastFlutterError;
  static final _uuid = const Uuid();
  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'vibebug_sdk_token';
  static const _projectIdPrefsKey = 'vibebug_sdk_project_id';
  static final _revision = ValueNotifier<int>(0);

  static bool get isInitialized => _initialized;
  static bool get isAuthenticated => _token != null;
  static String? get selectedProjectId => _projectId;
  static String? get selectedBoardId => _boardId;
  static String? get selectedDeveloperId => _assignedTo;
  static List<VibeBugProject> get projects => List.unmodifiable(_projects);
  static List<VibeBugBoard> get boards => List.unmodifiable(_boards);
  static List<VibeBugDeveloper> get developers =>
      List.unmodifiable(_developers);

  /// Whether [VibeBugScope] should show the built-in sign-in/project-picker
  /// gate instead of your app content. See [VibeBugOptions.enableAuthGate].
  static bool get isGateEnabled => _gateEnabled;

  /// Whether sign-in resolved a project list but no project has been chosen
  /// yet — the signal [VibeBugScope] uses to show the project picker.
  static bool get needsProjectSelection =>
      isAuthenticated && _projectId == null;

  /// Whether the gate should auto-select the sole assigned project instead of
  /// showing a picker. See [VibeBugOptions.autoSelectSoleProject].
  static bool get autoSelectSoleProject =>
      _options?.autoSelectSoleProject ?? false;

  /// Whether the gate blocks the whole app on startup, vs. only prompting
  /// when the Report button is first tapped. See
  /// [VibeBugOptions.blockAppUntilReady].
  static bool get blockAppUntilReady => _options?.blockAppUntilReady ?? false;

  /// Whether the on-demand gate (tapping Report) still needs to run: the
  /// gate is enabled but the app isn't blocking on startup, and either
  /// sign-in or project selection hasn't happened yet.
  static bool get needsOnDemandGate =>
      _gateEnabled && !blockAppUntilReady && (!isAuthenticated || _projectId == null);

  /// Notifies listeners whenever sign-in/sign-out/project-selection state
  /// changes, so [VibeBugScope] can rebuild without a StatefulWidget of its
  /// own tracking auth state.
  static Listenable get listenable => _revision;

  static void _bump() => _revision.value++;

  /// Initialize the SDK. Call before [runGuarded] or [runApp].
  static Future<void> initialize(VibeBugOptions options) async {
    _options = options;
    _api = VibeBugApiClient(baseUrl: options.baseUrl);
    _prefs = await SharedPreferences.getInstance();
    _queue = IssueQueue(_prefs!);
    _gateEnabled = options.enableAuthGate ??
        (options.token == null &&
            options.email == null &&
            options.password == null);

    if (options.token != null) {
      _token = options.token;
    } else {
      _token = await _secure.read(key: _tokenKey);
      if (_token == null && options.email != null && options.password != null) {
        final result = await _api!
            .login(email: options.email!, password: options.password!);
        _token = result.token;
        await _secure.write(key: _tokenKey, value: _token);
      }
    }

    if (_token != null) {
      if (_gateEnabled) {
        await _hydrateProjectsForGate();
      } else {
        await _loadProjectsAndDefaults();
        await flushPendingReports();
      }
    }

    if (options.autoReportCrashes) {
      _installErrorHandlers();
    }

    _initialized = true;
    _bump();
  }

  /// Restores gate state on cold start: which projects the account can act as
  /// tester on, and whether a previously-selected project is still valid.
  ///
  /// Trusts a cached project id when the network is unavailable (a flaky
  /// connection should never bounce a returning user back to the picker),
  /// but drops it if the server no longer lists it among the account's
  /// projects.
  static Future<void> _hydrateProjectsForGate() async {
    final cachedProjectId = _prefs?.getString(_projectIdPrefsKey);
    List<VibeBugProject>? loaded;
    try {
      loaded = (await _api!.loadProjects(_token!))
          .where((project) => project.canActAsTester)
          .toList();
    } catch (_) {
      loaded = null;
    }

    if (loaded != null) {
      _projects = loaded;
      if (cachedProjectId != null &&
          _projects.any((project) => project.id == cachedProjectId)) {
        _projectId = cachedProjectId;
      } else {
        _projectId = null;
        if (cachedProjectId != null) {
          await _prefs?.remove(_projectIdPrefsKey);
        }
      }
    } else if (cachedProjectId != null) {
      _projectId = cachedProjectId;
    }

    if (_projectId != null) {
      try {
        await _loadProjectOptions(_projectId!);
      } catch (_) {
        // Boards/developers refresh lazily via _resolveTarget() below.
      }
      await flushPendingReports();
    }
  }

  /// Signs in a tester/owner/admin account after SDK initialization.
  ///
  /// Only authenticates and populates [projects] — it does not pick one.
  /// Callers (the built-in gate, or your own UI) must call [selectProject]
  /// once the account's project is known.
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    if (_api == null || _queue == null) {
      throw VibeBugException('VibeBug.initialize() must be called first.');
    }
    final result = await _api!.login(email: email, password: password);
    _token = result.token;
    await _secure.write(key: _tokenKey, value: _token);
    _projects = result.projects.where((project) => project.canActAsTester).toList();
    _projectId = null;
    _boardId = null;
    _assignedTo = null;
    _boards = const [];
    _developers = const [];
    _bump();
    if (_projects.isEmpty) {
      throw VibeBugException(
        'No tester-accessible projects are assigned to this account. Ask a project owner to add you as a tester.',
      );
    }
  }

  /// Signs out and clears the cached project selection, so [VibeBugScope]
  /// returns to the sign-in screen when the gate is enabled.
  static Future<void> signOut() async {
    await _secure.delete(key: _tokenKey);
    await _prefs?.remove(_projectIdPrefsKey);
    _token = null;
    _projectId = null;
    _boardId = null;
    _assignedTo = null;
    _projects = const [];
    _boards = const [];
    _developers = const [];
    _bump();
  }

  /// Changes the active target used by crash reports and default issue submits.
  ///
  /// Manual visual reports can still override board/developer per issue.
  /// Persists the choice so it survives app restarts.
  static Future<void> selectProject(String projectId) async {
    await _ensureAuth();
    _projectId = projectId;
    _boardId = null;
    _assignedTo = null;
    await _loadProjectOptions(projectId);
    await _prefs?.setString(_projectIdPrefsKey, projectId);
    await flushPendingReports();
    _bump();
  }

  static void selectBoard(String boardId) {
    _boardId = boardId;
  }

  static void selectDeveloper(String developerId) {
    _assignedTo = developerId;
  }

  /// Wrap [runApp] to catch async zone errors.
  static void runGuarded(FutureOr<void> Function() appRunner) {
    runZonedGuarded(
      () {
        final result = appRunner();
        if (result is Future) {
          result.catchError((error, stack) {
            _handleUncaught(error, stack, fatal: true);
          });
        }
      },
      (error, stack) => _handleUncaught(error, stack, fatal: true),
    );
  }

  /// Report a caught exception during live testing.
  static Future<String?> reportException(
    Object error,
    StackTrace stack, {
    String? description,
    String? pageUrl,
    String? widgetKey,
    String priority = 'high',
    bool fatal = false,
  }) {
    final body = _formatReport(
      title: description ?? error.toString(),
      error: error,
      stack: stack,
      fatal: fatal,
    );
    return _sendOrQueue(
      description: body,
      priority: priority,
      pageUrl: pageUrl,
      cssSelector: widgetKey,
      fingerprint: _fingerprint(error, stack),
      isFatal: fatal,
      captureScreenshot: true,
    );
  }

  /// Report a user-described issue during live testing (optional screenshot).
  static Future<String?> reportIssue({
    required String description,
    String priority = 'medium',
    String? projectId,
    String? boardId,
    String? assignedTo,
    String? pageUrl,
    String? widgetKey,
    String? screenshotDataUrl,
  }) {
    return _sendOrQueue(
      description: description,
      priority: priority,
      projectId: projectId ?? _projectId,
      boardId: boardId ?? _boardId,
      assignedTo: assignedTo ?? _assignedTo,
      pageUrl: pageUrl,
      cssSelector: widgetKey,
      fingerprint: _fingerprint(description, StackTrace.current),
      isFatal: false,
      captureScreenshot: screenshotDataUrl == null,
      screenshotDataUrl: screenshotDataUrl,
    );
  }

  /// Report a multi-capture Flutter UI issue with widget selectors and Flutter markdown.
  static Future<String?> reportIssueWithCaptures({
    required String summary,
    required List<VibeBugScreenshotShot> captures,
    String priority = 'medium',
    String? projectId,
    String? boardId,
    String? assignedTo,
    String? routeName,
  }) {
    if (captures.isEmpty) {
      throw VibeBugException('At least one capture is required.');
    }
    return _sendOrQueue(
      description: summary.trim(),
      priority: priority,
      projectId: projectId,
      boardId: boardId,
      assignedTo: assignedTo,
      pageUrl: captures.first.pageUrl,
      cssSelector: captures.first.cssSelector,
      fingerprint: _fingerprint(summary, StackTrace.current),
      isFatal: false,
      captureScreenshot: false,
      screenshots: captures.map((shot) => shot.toApiJson()).toList(),
    );
  }

  /// Retry queued reports (e.g. after connectivity returns).
  static Future<void> flushPendingReports() async {
    if (_queue == null || _api == null || _options == null) return;
    final pending = _queue!.readAll();
    for (final report in pending) {
      try {
        final issueId = await _submitReport(report);
        await _queue!.remove(report.id);
        _options!.onIssueSent?.call(issueId);
        await _queue!.markSent(report.fingerprint);
      } catch (e) {
        _options!.onError?.call(e);
        break;
      }
    }
  }

  static void _installErrorHandlers() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      _lastFlutterError = details;
      previousFlutterHandler?.call(details);
      _handleUncaught(details.exception, details.stack ?? StackTrace.current,
          fatal: true);
    };

    final platformDispatcher = PlatformDispatcher.instance;
    final previousPlatformHandler = platformDispatcher.onError;
    platformDispatcher.onError = (error, stack) {
      _handleUncaught(error, stack, fatal: true);
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  static void _handleUncaught(Object error, StackTrace stack,
      {required bool fatal}) {
    if (!_initialized || _options == null || !_options!.autoReportCrashes) {
      return;
    }

    final fingerprint = _fingerprint(error, stack);
    if (_queue!.wasRecentlySent(fingerprint, _options!.dedupeWindow)) return;

    final body = _formatReport(
      title: error.toString(),
      error: error,
      stack: stack,
      fatal: fatal,
      flutterDetails: _lastFlutterError,
    );

    unawaited(_sendOrQueue(
      description: body,
      priority: fatal ? 'immediate' : _options!.defaultPriority,
      fingerprint: fingerprint,
      isFatal: fatal,
      captureScreenshot: _options!.screenshotProvider != null,
      pageUrl: _lastFlutterError?.library,
    ));
  }

  static String _formatReport({
    required String title,
    required Object error,
    required StackTrace stack,
    required bool fatal,
    FlutterErrorDetails? flutterDetails,
  }) {
    final buffer = StringBuffer()
      ..writeln(fatal ? '[CRASH] $title' : '[Exception] $title')
      ..writeln()
      ..writeln('Type: ${error.runtimeType}')
      ..writeln(
          'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Flutter: $fatal')
      ..writeln()
      ..writeln('Stack trace:')
      ..writeln(stack.toString());

    if (flutterDetails != null) {
      buffer
        ..writeln()
        ..writeln('Context: ${flutterDetails.context}')
        ..writeln('Library: ${flutterDetails.library}')
        ..writeln(
            'Information: ${flutterDetails.informationCollector?.call()}');
    }

    return buffer.toString().trim();
  }

  static String _fingerprint(Object error, StackTrace stack) {
    final lines = stack
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3)
        .join('|');
    return base64Url
        .encode(utf8.encode('${error.runtimeType}:$lines'))
        .substring(0, 24);
  }

  static Future<String?> _sendOrQueue({
    required String description,
    required String priority,
    required String fingerprint,
    required bool isFatal,
    required bool captureScreenshot,
    String? projectId,
    String? boardId,
    String? assignedTo,
    String? pageUrl,
    String? cssSelector,
    String? screenshotDataUrl,
    List<Map<String, dynamic>> screenshots = const [],
  }) async {
    if (_queue == null || _options == null) {
      throw VibeBugException('VibeBug.initialize() must be called first.');
    }

    if (_queue!.wasRecentlySent(fingerprint, _options!.dedupeWindow)) {
      return null;
    }

    String? screenshot = screenshotDataUrl;
    if (screenshot == null &&
        captureScreenshot &&
        _options!.screenshotProvider != null) {
      try {
        screenshot = await _options!.screenshotProvider!();
      } catch (_) {}
    }

    final pending = await _queue!.enqueue(
      description: description,
      priority: priority,
      fingerprint: fingerprint,
      projectId: projectId,
      boardId: boardId,
      assignedTo: assignedTo,
      pageUrl: pageUrl,
      cssSelector: cssSelector,
      screenshotDataUrl: screenshot,
      screenshots: screenshots,
      isFatal: isFatal,
    );

    if (!_options!.reportInBackground) {
      return null;
    }

    try {
      final issueId = await _submitReport(pending);
      await _queue!.remove(pending.id);
      await _queue!.markSent(fingerprint);
      _options!.onIssueSent?.call(issueId);
      return issueId;
    } catch (e) {
      _options!.onError?.call(e);
      return null;
    }
  }

  static Future<String> _submitReport(PendingIssueReport report) async {
    await _ensureAuth();
    final target = await _resolveTarget(
      projectId: report.projectId,
      boardId: report.boardId,
      assignedTo: report.assignedTo,
    );

    final screenshots = <Map<String, dynamic>>[];
    if (report.screenshots.isNotEmpty) {
      screenshots.addAll(report.screenshots);
    } else if (report.screenshotDataUrl != null &&
        report.screenshotDataUrl!.isNotEmpty) {
      screenshots.add({
        'id': _uuid.v4(),
        'description': report.description.length > 200
            ? report.description.substring(0, 200)
            : report.description,
        'selectedScreenshotDataUrl': report.screenshotDataUrl,
        'fullScreenshotDataUrl': report.screenshotDataUrl,
        'screenshotDataUrl': report.screenshotDataUrl,
        'pageUrl': report.pageUrl ?? '',
        'cssSelector': report.cssSelector ?? '',
        'attachments': <dynamic>[],
      });
    }

    return _api!.createIssue(
      _token!,
      projectId: target.projectId,
      boardId: target.boardId,
      description: report.description,
      priority: report.priority,
      assignedTo: target.assignedTo,
      pageUrl: report.pageUrl,
      cssSelector: report.cssSelector,
      userAgent:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      browserName: 'Flutter',
      screenshots: screenshots,
    );
  }

  static Future<void> _ensureAuth() async {
    if (_token != null) return;
    final options = _options!;
    if (options.email == null || options.password == null) {
      throw VibeBugException('No auth token. Provide token or email/password.');
    }
    final result =
        await _api!.login(email: options.email!, password: options.password!);
    _token = result.token;
    await _secure.write(key: _tokenKey, value: _token);
  }

  static Future<void> _loadProjectsAndDefaults() async {
    final options = _options!;
    if (_token == null) await _ensureAuth();

    _projects = await _api!.loadProjects(_token!);
    final available = _projects.where((project) => project.canActAsTester).toList();
    if (available.isEmpty) {
      throw VibeBugException(
          'No tester-accessible projects are assigned to this account.');
    }

    _projectId = options.projectId != null &&
            available.any((project) => project.id == options.projectId)
        ? options.projectId
        : available.first.id;
    await _loadProjectOptions(_projectId!);

    if (options.boardId != null &&
        _boards.any((board) => board.id == options.boardId)) {
      _boardId = options.boardId;
    }
    if (options.assignedTo != null &&
        _developers.any((developer) => developer.id == options.assignedTo)) {
      _assignedTo = options.assignedTo;
    }
  }

  static Future<void> _loadProjectOptions(String projectId) async {
    _boards = (await _api!.loadBoards(_token!, projectId))
        .where((board) => board.status != 'archived')
        .toList();
    _developers = await _api!.loadDevelopers(_token!, projectId);
    _boardId = _defaultBoardId(projectId, _boards);
    _assignedTo = _developers.isNotEmpty ? _developers.first.id : null;
  }

  static String? _defaultBoardId(String projectId, List<VibeBugBoard> boards) {
    if (boards.isEmpty) return null;
    final main = boards.where((board) =>
        board.id == 'brd_${projectId}_main' || board.id.endsWith('_main'));
    if (main.isNotEmpty) return main.first.id;
    final starred = boards.where((board) => board.starred);
    if (starred.isNotEmpty) return starred.first.id;
    return boards.first.id;
  }

  static Future<_IssueTarget> _resolveTarget({
    String? projectId,
    String? boardId,
    String? assignedTo,
  }) async {
    if (_projectId == null) await _loadProjectsAndDefaults();
    final resolvedProject = projectId ?? _projectId;
    if (resolvedProject == null || resolvedProject.isEmpty) {
      throw VibeBugException(
          'Select a tester project before sending an issue.');
    }

    if (resolvedProject != _projectId ||
        _boards.isEmpty ||
        _developers.isEmpty) {
      _projectId = resolvedProject;
      await _loadProjectOptions(resolvedProject);
    }

    final resolvedBoard = boardId ?? _boardId;
    if (resolvedBoard == null || resolvedBoard.isEmpty) {
      throw VibeBugException('Select a board before sending an issue.');
    }

    final resolvedDeveloper = assignedTo ?? _assignedTo;
    if (resolvedDeveloper == null || resolvedDeveloper.isEmpty) {
      throw VibeBugException('Select a developer before sending an issue.');
    }

    return _IssueTarget(
      projectId: resolvedProject,
      boardId: resolvedBoard,
      assignedTo: resolvedDeveloper,
    );
  }
}

class _IssueTarget {
  const _IssueTarget({
    required this.projectId,
    required this.boardId,
    required this.assignedTo,
  });

  final String projectId;
  final String boardId;
  final String assignedTo;
}

/// Widget wrapper that reports Flutter framework errors in this subtree.
class VibeBugErrorBoundary extends StatefulWidget {
  const VibeBugErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
  });

  final Widget child;
  final Widget Function(FlutterErrorDetails details)? fallback;

  @override
  State<VibeBugErrorBoundary> createState() => _VibeBugErrorBoundaryState();
}

class _VibeBugErrorBoundaryState extends State<VibeBugErrorBoundary> {
  FlutterErrorDetails? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.fallback != null) {
      return widget.fallback!(_error!);
    }
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (mounted) setState(() => _error = details);
      unawaited(VibeBug.reportException(
        details.exception,
        details.stack ?? StackTrace.current,
        description: details.summary.toString(),
        fatal: false,
      ));
      previous?.call(details);
    };
  }
}

/// Legacy floating action button. Prefer [VibeBugScope] for draggable capture + widget selection.
class VibeBugReportButton extends StatelessWidget {
  const VibeBugReportButton({
    super.key,
    this.pageUrl,
    this.widgetKey,
  });

  final String? pageUrl;
  final String? widgetKey;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showReportSheet(context),
      label: const Text('Report bug'),
      icon: const Icon(Icons.bug_report_outlined),
      tooltip: 'Use VibeBugScope for draggable capture and widget selection',
    );
  }

  Future<void> _showReportSheet(BuildContext context) async {
    final controller = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
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
              const Text('Report issue to developer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'What went wrong?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send to developer'),
              ),
            ],
          ),
        );
      },
    );

    if (sent == true && controller.text.trim().length >= 3) {
      await VibeBug.reportIssue(
        description: controller.text.trim(),
        pageUrl: pageUrl,
        widgetKey: widgetKey,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue sent to developer')),
        );
      }
    }
    controller.dispose();
  }
}
