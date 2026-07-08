# vibebug_flutter

Flutter SDK for [Vibe Bug Tracker](https://vibebugtracker.com) — Crashlytics-style crash and exception reporting for mobile apps under live testing.

## Features

- Automatic crash and uncaught exception reporting
- Offline queue — reports are retried when connectivity returns
- Live testing: manual issue reports with `VibeBugReportButton`
- Assigns issues to developers via the Vibe Bug Tracker API
- Deduplication to avoid spam from repeated errors

## Setup

Add to `pubspec.yaml`:

```yaml
dependencies:
  vibebug_flutter:
    git:
      url: https://github.com/adnanpk44/visualIssueTracker.git
      path: packages/vibebug_flutter
      ref: main
```

Or use a local path while developing in the monorepo:

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
    // Optional: pin board/developer instead of auto-picking first
    // boardId: 'brd_...',
    // assignedTo: 'usr_...',
    autoReportCrashes: true,
    reportInBackground: true,
    onIssueSent: (issueId) => debugPrint('Reported $issueId'),
  ));

  VibeBug.runGuarded(() => runApp(const MyApp()));
}
```

## Live testing — manual report

```dart
Scaffold(
  floatingActionButton: VibeBugReportButton(
    pageUrl: '/checkout',
    widgetKey: 'pay_button',
  ),
)
```

## Caught exceptions

```dart
try {
  await riskyOperation();
} catch (e, stack) {
  await VibeBug.reportException(e, stack, description: 'Checkout failed');
}
```

## Token-based auth

```dart
await VibeBug.initialize(VibeBugOptions(
  projectId: 'proj_...',
  token: 'your-bearer-token',
));
```

## API

Uses the same `/api/extension` endpoints as the Chrome extension and flutter-tester-app:

- `POST /api/extension/auth/login`
- `POST /api/extension/issues`
- `GET /api/extension/boards`
- `GET /api/extension/users/developers`

Issues are created with stack traces in the description. Screenshots are optional (include via `screenshotProvider` in options).

## Notes

- Requires a tester account with access to the target project
- Project must have an active paid plan on Vibe Bug Tracker
- For screenshot capture, provide a `screenshotProvider` callback that returns a base64 data URL
