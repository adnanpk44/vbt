import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/api_client.dart';
import 'package:vibebug_flutter/src/onboarding/vibebug_project_picker_screen.dart';

// VibeBugScope's gate screens fully replace MaterialApp's `child` — the
// widget MaterialApp normally builds from `home:`, which is where the app's
// real Navigator (and the Overlay it hosts) lives. Without a Navigator of
// their own, anything the screen needs from one — the project dropdown's
// popup menu, a TextField's selection toolbar — throws in production
// ("No Overlay widget found" / no Navigator found), even though the same
// screen renders and looks fine when wrapped in a normal MaterialApp(home:).
// See _isolatedGateScreen in capture_overlay.dart for the fix this guards.
const _projects = [
  VibeBugProject(id: 'p1', name: 'Project One', role: 'tester'),
  VibeBugProject(id: 'p2', name: 'Project Two', role: 'tester'),
];

void main() {
  testWidgets(
    'reproduces the bug: a gate screen used directly as MaterialApp.builder\'s '
    'return value has no Navigator, so opening the dropdown throws',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const Placeholder(),
        builder: (context, child) => VibeBugProjectPickerScreen(
          projects: _projects,
          onProjectSelected: (_) async {},
        ),
      ));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNotNull);
    },
  );

  testWidgets(
    'fix: wrapping the gate screen in its own Navigator (as VibeBugScope does) '
    'lets the dropdown open and select without error',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const Placeholder(),
        builder: (context, child) => Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => VibeBugProjectPickerScreen(
              projects: _projects,
              onProjectSelected: (_) async {},
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Project Two'), findsWidgets);

      await tester.tap(find.text('Project Two').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final nextButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(nextButton.onPressed, isNotNull);
    },
  );
}
