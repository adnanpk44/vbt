import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/api_client.dart';
import 'package:vibebug_flutter/src/onboarding/vibebug_project_picker_screen.dart';

void main() {
  testWidgets('with one project, Next is enabled immediately and pre-selected', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: VibeBugProjectPickerScreen(
        projects: const [VibeBugProject(id: 'p1', name: 'Solo Project', role: 'tester')],
        onProjectSelected: (id) async => selected = id,
      ),
    ));

    expect(find.text('Solo Project'), findsOneWidget);
    final nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextButton.onPressed, isNotNull);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(selected, 'p1');
  });

  testWidgets('with multiple projects, Next starts disabled until a selection is made',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: VibeBugProjectPickerScreen(
        projects: const [
          VibeBugProject(id: 'p1', name: 'Project One', role: 'tester'),
          VibeBugProject(id: 'p2', name: 'Project Two', role: 'tester'),
        ],
        onProjectSelected: (_) async {},
      ),
    ));

    var nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextButton.onPressed, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project One').last);
    await tester.pumpAndSettle();

    nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextButton.onPressed, isNotNull);
  });

  testWidgets('Sign out calls the injected callback', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: VibeBugProjectPickerScreen(
        projects: const [VibeBugProject(id: 'p1', name: 'Solo Project', role: 'tester')],
        onProjectSelected: (_) async {},
        onSignOut: () async => signedOut = true,
      ),
    ));

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  testWidgets('shows a message instead of a dropdown when there are no projects',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: VibeBugProjectPickerScreen(
        projects: const [],
        onProjectSelected: (_) async {},
      ),
    ));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('No tester-accessible projects'), findsOneWidget);
  });
}
