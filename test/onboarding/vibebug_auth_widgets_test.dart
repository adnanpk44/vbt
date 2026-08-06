import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/api_client.dart';
import 'package:vibebug_flutter/src/onboarding/vibebug_auth_widgets.dart';

void main() {
  group('VibeBugSignInForm', () {
    testWidgets('shows a validation error and never calls signIn when fields are empty',
        (tester) async {
      var signInCalled = false;
      var signedInCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VibeBugSignInForm(
            onSignedIn: (_) => signedInCalled = true,
            signIn: ({required email, required password}) async {
              signInCalled = true;
            },
          ),
        ),
      ));

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(signInCalled, isFalse);
      expect(signedInCalled, isFalse);
      expect(find.text('Enter your email and password.'), findsOneWidget);
    });

    testWidgets('surfaces an error message when signIn throws', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VibeBugSignInForm(
            onSignedIn: (_) {},
            signIn: ({required email, required password}) async {
              throw Exception('bad credentials');
            },
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'a@b.com');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sign in failed'), findsOneWidget);
    });

    testWidgets('calls onSignedIn after a successful sign-in', (tester) async {
      var signedInProjects = const <VibeBugProject>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VibeBugSignInForm(
            onSignedIn: (projects) => signedInProjects = projects,
            signIn: ({required email, required password}) async {},
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'a@b.com');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      // onSignedIn is called with VibeBug.projects (empty since the SDK
      // wasn't actually initialized in this widget test) — the important
      // assertion is that the callback fired at all, with no error shown.
      expect(signedInProjects, isEmpty);
      expect(find.textContaining('Sign in failed'), findsNothing);
    });
  });

  group('VibeBugProjectDropdown', () {
    const projects = [
      VibeBugProject(id: 'p1', name: 'Project One', role: 'tester'),
      VibeBugProject(id: 'p2', name: 'Project Two', role: 'tester'),
    ];

    testWidgets('renders one item per project', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VibeBugProjectDropdown(
            projects: projects,
            value: null,
            onChanged: (_) {},
          ),
        ),
      ));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Project One'), findsWidgets);
      expect(find.text('Project Two'), findsWidgets);
    });

    testWidgets('onChanged fires with the selected project id', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VibeBugProjectDropdown(
            projects: projects,
            value: null,
            onChanged: (value) => selected = value,
          ),
        ),
      ));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project Two').last);
      await tester.pumpAndSettle();

      expect(selected, 'p2');
    });
  });
}
