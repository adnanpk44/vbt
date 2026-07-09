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
import 'capture/flutter_issue_markdown.dart';
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
  static String? _token;
  static String? _boardId;
  static String? _assignedTo;
  static bool _initialized = false;
  static FlutterErrorDetails? _lastFlutterError;
  static final _uuid = const Uuid();
  static const _secure = FlutterSecureStorage();
  static const _tokenKey = 'vibebug_sdk_token';

  static bool get isInitialized => _initialized;

  /// Initialize the SDK. Call before [runGuarded] or [runApp].
  static Future<void> initialize(VibeBugOptions options) async {
    _options = options;
    _api = VibeBugApiClient(baseUrl: options.baseUrl);
    final prefs = await SharedPreferences.getInstance();
    _queue = IssueQueue(prefs);

    if (options.token != null) {
      _token = options.token;
    } else {
      _token = await _secure.read(key: _tokenKey);
      if (_token == null && options.email != null && options.password != null) {
        _token = await _api!.login(email: options.email!, password: options.password!);
        await _secure.write(key: _tokenKey, value: _token);
      }
    }

    await _resolveDefaults();
    await flushPendingReports();

    if (options.autoReportCrashes) {
      _installErrorHandlers();
    }

    _initialized = true;
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
    String? pageUrl,
    String? widgetKey,
    String? screenshotDataUrl,
  }) {
    return _sendOrQueue(
      description: description,
      priority: priority,
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
    String? routeName,
  }) {
    if (captures.isEmpty) {
      throw VibeBugException('At least one capture is required.');
    }
    final markdown = const FlutterIssueMarkdown().build(
      summary: summary,
      captures: captures,
      routeName: routeName ?? captures.first.pageUrl,
    );
    return _sendOrQueue(
      description: markdown,
      priority: priority,
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
      _handleUncaught(details.exception, details.stack ?? StackTrace.current, fatal: true);
    };

    final platformDispatcher = PlatformDispatcher.instance;
    final previousPlatformHandler = platformDispatcher.onError;
    platformDispatcher.onError = (error, stack) {
      _handleUncaught(error, stack, fatal: true);
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  static void _handleUncaught(Object error, StackTrace stack, {required bool fatal}) {
    if (!_initialized || _options == null || !_options!.autoReportCrashes) return;

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
      ..writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Flutter: $fatal')
      ..writeln()
      ..writeln('Stack trace:')
      ..writeln(stack.toString());

    if (flutterDetails != null) {
      buffer
        ..writeln()
        ..writeln('Context: ${flutterDetails.context}')
        ..writeln('Library: ${flutterDetails.library}')
        ..writeln('Information: ${flutterDetails.informationCollector?.call()}');
    }

    return buffer.toString().trim();
  }

  static String _fingerprint(Object error, StackTrace stack) {
    final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(3).join('|');
    return base64Url.encode(utf8.encode('${error.runtimeType}:$lines')).substring(0, 24);
  }

  static Future<String?> _sendOrQueue({
    required String description,
    required String priority,
    required String fingerprint,
    required bool isFatal,
    required bool captureScreenshot,
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
    if (screenshot == null && captureScreenshot && _options!.screenshotProvider != null) {
      try {
        screenshot = await _options!.screenshotProvider!();
      } catch (_) {}
    }

    final pending = await _queue!.enqueue(
      description: description,
      priority: priority,
      fingerprint: fingerprint,
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
    await _resolveDefaults();

    final screenshots = <Map<String, dynamic>>[];
    if (report.screenshots.isNotEmpty) {
      screenshots.addAll(report.screenshots);
    } else if (report.screenshotDataUrl != null && report.screenshotDataUrl!.isNotEmpty) {
      screenshots.add({
        'id': _uuid.v4(),
        'description': report.description.length > 200 ? report.description.substring(0, 200) : report.description,
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
      projectId: _options!.projectId,
      boardId: _boardId!,
      description: report.description,
      priority: report.priority,
      assignedTo: _assignedTo!,
      pageUrl: report.pageUrl,
      cssSelector: report.cssSelector,
      userAgent: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
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
    _token = await _api!.login(email: options.email!, password: options.password!);
    await _secure.write(key: _tokenKey, value: _token);
  }

  static Future<void> _resolveDefaults() async {
    final options = _options!;
    if (_token == null) await _ensureAuth();

    if (_boardId == null) {
      if (options.boardId != null) {
        _boardId = options.boardId;
      } else {
        final boards = await _api!.loadBoards(_token!, options.projectId);
        if (boards.isEmpty) throw VibeBugException('No board found for project.');
        _boardId = boards.first['id'] as String;
      }
    }

    if (_assignedTo == null) {
      if (options.assignedTo != null) {
        _assignedTo = options.assignedTo;
      } else {
        final developers = await _api!.loadDevelopers(_token!, options.projectId);
        if (developers.isEmpty) throw VibeBugException('No active developer found for project.');
        _assignedTo = developers.first['id'] as String;
      }
    }
  }
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
              const Text('Report issue to developer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
