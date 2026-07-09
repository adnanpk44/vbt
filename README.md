# vibebug_flutter

Flutter SDK for [Vibe Bug Tracker](https://vibebugtracker.com) — crash reporting plus Chrome-extension-style visual bug capture for Flutter apps under live testing.

## Features

- Automatic crash and uncaught exception reporting
- **Draggable Report button** — testers can move the bubble anywhere on screen
- **Widget selection** — tap a widget to capture it (selected crop + full screen context)
- **Multi-screenshot issues** — up to 8 captures per issue, like the Chrome extension
- **Flutter-specific AI markdown** — issue descriptions include widget selectors, route, and Flutter fix guidance
- Offline queue with retry when connectivity returns

## Setup

```yaml
dependencies:
  vibebug_flutter:
    path: ../packages/vibebug_flutter
```

Initialize before `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await VibeBug.initialize(VibeBugOptions(
    projectId: 'proj_your_project_id',
    email: 'tester@example.com',
    password: 'your-password',
    onIssueSent: (issueId) => debugPrint('Reported $issueId'),
  ));

  VibeBug.runGuarded(() {
    runApp(
      const VibeBugScope(
        child: MyApp(),
      ),
    );
  });
}
```

## Visual bug reporting (recommended)

Wrap your app with `VibeBugScope`. When using `MaterialApp.router`, pass the router navigator key:

```dart
VibeBugScope(
  navigatorKey: goRouter.routerDelegate.navigatorKey,
  child: MyApp(),
)
```

1. **Drag** the bubble to reposition it (position is remembered)
2. **Tap** the bubble → hover highlights widgets → **tap a widget** to capture it
3. Add a note for that capture
4. **Add another** widget capture (up to 8) or **Review & send**
5. Submit the issue — developers receive Flutter markdown + all screenshots

Long-press the bubble to clear draft captures.

## Legacy text-only report button

`VibeBugReportButton` still works for quick text-only reports, but does not include widget selection or multi-capture.

## Programmatic multi-capture submit

```dart
await VibeBug.reportIssueWithCaptures(
  summary: 'Checkout CTA overlaps total on small screens',
  captures: shots, // List<VibeBugScreenshotShot>
);
```

## Caught exceptions

```dart
try {
  await riskyOperation();
} catch (e, stack) {
  await VibeBug.reportException(e, stack, description: 'Checkout failed');
}
```

## API

Uses `/api/extension/issues` with a `screenshots[]` payload matching the Chrome extension:

- `selectedScreenshotDataUrl` — cropped widget shot
- `fullScreenshotDataUrl` — full screen context
- `cssSelector` — Flutter widget selector trail (e.g. `flutter:ElevatedButton[key=payBtn]>Column>Scaffold`)
- `domText` / `htmlSnippet` — semantics + widget context for AI markdown

## Notes

- Widget inspection works best in **debug/profile** builds where Flutter exposes widget creators
- Screenshot capture requires `VibeBugScope` (uses an internal `RepaintBoundary`)
- Requires a tester account with access to the target project
