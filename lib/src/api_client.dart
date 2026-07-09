import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'vibebug_exception.dart';

class VibeBugProject {
  const VibeBugProject({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final String role;

  factory VibeBugProject.fromJson(Map<String, dynamic> json) => VibeBugProject(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled project',
        role: json['role'] as String? ?? json['project_role'] as String? ?? '',
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
  VibeBugApiClient({required String baseUrl})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _baseUrl;

  String _path(String path) => '$_baseUrl/api/extension$path';

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse(_path(path));
    final encodedBody = body == null ? null : jsonEncode(body);
    late http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'POST':
          response = await http.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: encodedBody);
          break;
        default:
          response = await http.get(uri, headers: headers);
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

  Future<String> login(
      {required String email, required String password}) async {
    final data = await _request(
      '/auth/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    return data['token'] as String;
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
