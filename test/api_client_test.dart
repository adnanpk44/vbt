import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibebug_flutter/src/api_client.dart';

void main() {
  group('VibeBugProject.canActAsTester', () {
    test('explicit tester role', () {
      expect(const VibeBugProject(id: 'p1', name: 'P1', role: 'tester').canActAsTester, isTrue);
    });

    test('project admin role', () {
      expect(const VibeBugProject(id: 'p1', name: 'P1', role: 'admin').canActAsTester, isTrue);
    });

    test('workspace owner with no project role', () {
      expect(
        const VibeBugProject(id: 'p1', name: 'P1', role: '', businessRole: 'owner')
            .canActAsTester,
        isTrue,
      );
    });

    test('workspace admin with no project role', () {
      expect(
        const VibeBugProject(id: 'p1', name: 'P1', role: '', businessRole: 'admin')
            .canActAsTester,
        isTrue,
      );
    });

    test('plain developer with no business role is not eligible', () {
      expect(
        const VibeBugProject(id: 'p1', name: 'P1', role: 'developer', businessRole: '')
            .canActAsTester,
        isFalse,
      );
    });
  });

  group('VibeBugApiClient', () {
    test('login() parses token and projects from the response', () async {
      final client = VibeBugApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/extension/auth/login');
          return http.Response(
            jsonEncode({
              'token': 'tok_123',
              'projects': [
                {'id': 'proj_1', 'name': 'Project One', 'role': 'tester'},
              ],
            }),
            200,
          );
        }),
      );

      final result = await client.login(email: 'a@b.com', password: 'secret');
      expect(result.token, 'tok_123');
      expect(result.projects, hasLength(1));
      expect(result.projects.first.id, 'proj_1');
    });

    test('login() tolerates a missing projects field', () async {
      final client = VibeBugApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          return http.Response(jsonEncode({'token': 'tok_1'}), 200);
        }),
      );

      final result = await client.login(email: 'a@b.com', password: 'secret');
      expect(result.token, 'tok_1');
      expect(result.projects, isEmpty);
    });

    test('sends X-VIT-Acting-Role: tester on authenticated requests', () async {
      String? actingRole;
      final client = VibeBugApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          actingRole = request.headers['X-VIT-Acting-Role'];
          return http.Response(jsonEncode({'projects': <dynamic>[]}), 200);
        }),
      );

      await client.loadProjects('tok_123');
      expect(actingRole, 'tester');
    });

    test('does not send an acting-role header on the unauthenticated login request', () async {
      String? actingRole;
      final client = VibeBugApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          actingRole = request.headers['X-VIT-Acting-Role'];
          return http.Response(jsonEncode({'token': 'tok_1'}), 200);
        }),
      );

      await client.login(email: 'a@b.com', password: 'secret');
      expect(actingRole, isNull);
    });
  });
}
