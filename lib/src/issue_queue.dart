import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PendingIssueReport {
  PendingIssueReport({
    required this.id,
    required this.description,
    required this.priority,
    required this.fingerprint,
    required this.createdAt,
    this.pageUrl,
    this.cssSelector,
    this.projectId,
    this.boardId,
    this.assignedTo,
    this.screenshotDataUrl,
    this.screenshots = const [],
    this.isFatal = true,
  });

  final String id;
  final String description;
  final String priority;
  final String fingerprint;
  final DateTime createdAt;
  final String? pageUrl;
  final String? cssSelector;
  final String? projectId;
  final String? boardId;
  final String? assignedTo;
  final String? screenshotDataUrl;
  final List<Map<String, dynamic>> screenshots;
  final bool isFatal;

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'priority': priority,
        'fingerprint': fingerprint,
        'createdAt': createdAt.toIso8601String(),
        'pageUrl': pageUrl,
        'cssSelector': cssSelector,
        'projectId': projectId,
        'boardId': boardId,
        'assignedTo': assignedTo,
        'screenshotDataUrl': screenshotDataUrl,
        'screenshots': screenshots,
        'isFatal': isFatal,
      };

  factory PendingIssueReport.fromJson(Map<String, dynamic> json) =>
      PendingIssueReport(
        id: json['id'] as String,
        description: json['description'] as String,
        priority: json['priority'] as String? ?? 'high',
        fingerprint: json['fingerprint'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        pageUrl: json['pageUrl'] as String?,
        cssSelector: json['cssSelector'] as String?,
        projectId: json['projectId'] as String?,
        boardId: json['boardId'] as String?,
        assignedTo: json['assignedTo'] as String?,
        screenshotDataUrl: json['screenshotDataUrl'] as String?,
        screenshots: (json['screenshots'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        isFatal: json['isFatal'] as bool? ?? true,
      );
}

class IssueQueue {
  IssueQueue(this._prefs);

  static const _queueKey = 'vibebug_pending_reports';
  static const _recentKey = 'vibebug_recent_fingerprints';

  final SharedPreferences _prefs;
  final _uuid = const Uuid();

  List<PendingIssueReport> readAll() {
    final raw = _prefs.getString(_queueKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PendingIssueReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<PendingIssueReport> items) => _prefs.setString(
      _queueKey, jsonEncode(items.map((e) => e.toJson()).toList()));

  Future<PendingIssueReport> enqueue({
    required String description,
    required String priority,
    required String fingerprint,
    String? pageUrl,
    String? cssSelector,
    String? projectId,
    String? boardId,
    String? assignedTo,
    String? screenshotDataUrl,
    List<Map<String, dynamic>> screenshots = const [],
    bool isFatal = true,
  }) async {
    final items = readAll();
    final report = PendingIssueReport(
      id: _uuid.v4(),
      description: description,
      priority: priority,
      fingerprint: fingerprint,
      createdAt: DateTime.now(),
      pageUrl: pageUrl,
      cssSelector: cssSelector,
      projectId: projectId,
      boardId: boardId,
      assignedTo: assignedTo,
      screenshotDataUrl: screenshotDataUrl,
      screenshots: screenshots,
      isFatal: isFatal,
    );
    items.add(report);
    await saveAll(items);
    return report;
  }

  Future<void> remove(String id) async {
    final items = readAll().where((item) => item.id != id).toList();
    await saveAll(items);
  }

  bool wasRecentlySent(String fingerprint, Duration window) {
    final raw = _prefs.getString(_recentKey);
    if (raw == null) return false;
    final map = (jsonDecode(raw) as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, DateTime.parse(v as String)),
    );
    final sentAt = map[fingerprint];
    if (sentAt == null) return false;
    return DateTime.now().difference(sentAt) < window;
  }

  Future<void> markSent(String fingerprint) async {
    final raw = _prefs.getString(_recentKey);
    final map = raw == null
        ? <String, String>{}
        : (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
    map[fingerprint] = DateTime.now().toIso8601String();
    // Keep only last 50 fingerprints
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final trimmed = Map.fromEntries(entries.take(50));
    await _prefs.setString(_recentKey, jsonEncode(trimmed));
  }
}
