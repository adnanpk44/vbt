import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'vibebug_exception.dart';

class VibeBugProject {
  const VibeBugProject({
    required this.id,
    required this.name,
    required this.role,
    this.businessRole = '',
  });

  final String id;
  final String name;
  final String role;
  final String businessRole;

  /// This SDK only ever reports issues as a tester, so any account that can
  /// act as a tester on this project is eligible: an explicit tester seat,
  /// a project admin, or a workspace owner/admin (who may have no per-project
  /// `tester` role row at all).
  bool get canActAsTester =>
      role == 'tester' ||
      role == 'admin' ||
      businessRole == 'owner' ||
      businessRole == 'admin';

  factory VibeBugProject.fromJson(Map<String, dynamic> json) => VibeBugProject(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled project',
        role: json['role'] as String? ?? json['project_role'] as String? ?? '',
        businessRole: json['businessRole'] as String? ?? '',
      );
}

class VibeBugBoard {
  const VibeBugBoard({
    required this.id,
    required this.name,
    this.status = 'active',
    this.starred = false,
    this.cardCount = 0,
  });

  final String id;
  final String name;
  final String status;
  final bool starred;
  final int cardCount;

  factory VibeBugBoard.fromJson(Map<String, dynamic> json) => VibeBugBoard(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled board',
        status: json['status'] as String? ?? 'active',
        starred: json['starred'] as bool? ?? false,
        cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      );
}

class VibeBugDeveloper {
  const VibeBugDeveloper({
    required this.id,
    required this.name,
    this.email = '',
  });

  final String id;
  final String name;
  final String email;

  factory VibeBugDeveloper.fromJson(Map<String, dynamic> json) =>
      VibeBugDeveloper(
        id: json['id'] as String? ?? '',
        name:
            json['name'] as String? ?? json['email'] as String? ?? 'Developer',
        email: json['email'] as String? ?? '',
      );
}

class VibeBugApiClient {
  VibeBugApiClient({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String _path(String path) => '$_baseUrl/api/extension$path';

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
      // This SDK only ever submits issues as a tester — sending this
      // explicitly (rather than relying on the backend's default) keeps
      // owner/admin accounts working even if that default ever changes.
      headers['X-VIT-Acting-Role'] = 'tester';
    }

    final uri = Uri.parse(_path(path));
    final encodedBody = body == null ? null : jsonEncode(body);
    late http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'POST':
          response =
              await _client.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          response =
              await _client.patch(uri, headers: headers, body: encodedBody);
          break;
        default:
          response = await _client.get(uri, headers: headers);
      }
    } on SocketException {
      throw VibeBugException('No internet connection.');
    } on http.ClientException catch (e) {
      throw VibeBugException('Network error: ${e.message}');
    }

    Map<String, dynamic>? json;
    final text = response.body;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (response.statusCode >= 400) {
      throw VibeBugException(
        json?['error'] as String? ?? 'Request failed (${response.statusCode})',
        status: response.statusCode,
      );
    }

    return json ?? <String, dynamic>{};
  }

  /// Signs in and returns the bearer token plus the account's assigned
  /// projects (already present in the login response, avoiding a second
  /// round-trip on the first-run path).
  Future<({String token, List<VibeBugProject> projects})> login({
    required String email,
    required String password,
  }) async {
    final data = await _request(
      '/auth/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    final projects = (data['projects'] as List<dynamic>? ?? [])
        .map((item) =>
            VibeBugProject.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((project) => project.id.isNotEmpty)
        .toList();
    return (token: data['token'] as String, projects: projects);
  }

  Future<List<VibeBugProject>> loadProjects(String token) async {
    final data = await _request('/projects', token: token);
    return (data['projects'] as List<dynamic>? ?? [])
        .map((item) =>
            VibeBugProject.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((project) => project.id.isNotEmpty)
        .toList();
  }

  Future<List<VibeBugDeveloper>> loadDevelopers(
      String token, String projectId) async {
    final data = await _request(
      '/users/developers?projectId=${Uri.encodeComponent(projectId)}',
      token: token,
    );
    return (data['developers'] as List<dynamic>? ?? [])
        .map((item) =>
            VibeBugDeveloper.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((developer) => developer.id.isNotEmpty)
        .toList();
  }

  Future<List<VibeBugBoard>> loadBoards(String token, String projectId) async {
    final data = await _request(
      '/boards?projectId=${Uri.encodeComponent(projectId)}',
      token: token,
    );
    return (data['boards'] as List<dynamic>? ?? [])
        .map((item) =>
            VibeBugBoard.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((board) => board.id.isNotEmpty)
        .toList();
  }

  Future<String> createIssue(
    String token, {
    required String projectId,
    required String boardId,
    required String description,
    required String priority,
    required String assignedTo,
    String? pageUrl,
    String? cssSelector,
    String? userAgent,
    String? browserName,
    List<Map<String, dynamic>> screenshots = const [],
  }) async {
    final data = await _request(
      '/issues',
      method: 'POST',
      token: token,
      body: {
        'projectId': projectId,
        'boardId': boardId,
        'title': description.length > 120
            ? description.substring(0, 120)
            : description,
        'description': description,
        'priority': priority,
        'assignedTo': assignedTo,
        if (pageUrl != null) 'pageUrl': pageUrl,
        if (cssSelector != null) 'cssSelector': cssSelector,
        if (userAgent != null) 'userAgent': userAgent,
        if (browserName != null) 'browserName': browserName,
        'screenshots': screenshots,
      },
    );
    final issue = data['issue'] as Map<String, dynamic>;
    return issue['id'] as String;
  }
}
