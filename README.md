# vibebug_flutter

Flutter SDK for [Vibe Bug Tracker](https://vibebugtracker.com) — crash reporting plus Chrome-extension-style visual bug capture for Flutter apps under live testing.

## Features

- Automatic crash and uncaught exception reporting
- **Draggable Report button** — testers can move the bubble anywhere on screen
- **Capture region editor** — after selecting a widget, crop/adjust the region and draw highlight marks before saving
- **Multi-screenshot issues** — up to 8 captures per issue, like the Chrome extension
- **Flutter-specific AI markdown** — issue descriptions include widget selectors, route, and Flutter fix guidance
- Offline queue with retry when connectivity returns

## Setup

```yaml
dependencies:
  vibebug_flutter:
    path: ../packages/vibebug_flutter
```

Initialize and wrap with the same zone + MaterialApp builder:

```dart
import 'package:flutter/material.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

void main() {
  // ensureInitialized and runApp must run in the same zone.
  VibeBug.runGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      // Keep VibeBugScope under MaterialApp so Directionality/Theme exist.
      builder: (context, child) => VibeBugScope(
        navigatorKey: _navKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }
}
```

```dart
await VibeBug.initialize(VibeBugOptions(
  onIssueSent: (issueId) => debugPrint('Reported $issueId'),
));
```

Call `initialize` before or after `runApp` (e.g. from your root widget after setup).

## Visual bug reporting (recommended)

Put `VibeBugScope` in `MaterialApp.builder` (not above `MaterialApp`). When using `MaterialApp.router`, pass the router navigator key:

```dart
MaterialApp.router(
  routerConfig: goRouter,
  builder: (context, child) => VibeBugScope(
    navigatorKey: goRouter.routerDelegate.navigatorKey,
    child: child ?? const SizedBox.shrink(),
  ),
)
```

1. **Drag** the bubble to reposition it (position is remembered)
2. **Tap** the bubble → tap a widget to capture it
3. **Crop / highlight** in the full-screen editor, add a per-capture note, then **Save**
4. Navigate to other screens freely, tap **Report** again to add more (up to 8)
5. Tap the **badge** on the bubble, then sign in with the tester account if needed
6. Select the project, board, developer, and priority for this issue, then **Send**

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
