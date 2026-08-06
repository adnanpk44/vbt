# vibebug_flutter

[![pub package](https://img.shields.io/pub/v/vibebug_flutter.svg)](https://pub.dev/packages/vibebug_flutter)
[![pub points](https://img.shields.io/pub/points/vibebug_flutter)](https://pub.dev/packages/vibebug_flutter/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Crash reporting plus Chrome-extension-style **visual bug capture** for Flutter apps — sends issues to [Vibe Bug Tracker](https://vibebugtracker.com) with screenshots, widget selectors, and Flutter-specific AI markdown.

Testers in your app can capture a widget, crop and highlight the region, add screenshots, and send a fully-described issue straight to your tracker board — no Chrome extension required.

## Features

- **Zero-config setup** — one command wires everything into your app, no manual code required
- **Built-in sign-in + project picker** — first launch shows a login screen, then a project dropdown; from then on issues are tracked against that project automatically
- **Automatic crash reporting** — uncaught exceptions, `FlutterError.onError`, and platform errors are reported with stack traces
- **Offline queue** — reports are queued and retried when connectivity returns, with de-duplication
- **Draggable Report button** — testers can move the bubble anywhere on screen
- **Widget picker + capture region editor** — tap a widget to capture it, then crop/adjust the region and draw highlight marks
- **Multi-screenshot issues** — up to 8 captures per issue, like the Chrome extension
- **Flutter-specific AI markdown** — issue descriptions include widget selectors, route, and Flutter fix guidance
- **Caught-exception API** — report handled errors from anywhere in your code

## Requirements

- Flutter `>=3.16.0`
- Dart SDK `>=3.2.0 <4.0.0`
- A [Vibe Bug Tracker](https://vibebugtracker.com) account, and a tester / owner / admin account with access to a project

## Installation

```sh
flutter pub add vibebug_flutter
```

Then run the setup wizard:

```sh
dart run vibebug_flutter:configure
```

The `configure` command:

1. Rewrites `main.dart` so `runApp()` runs inside `VibeBug.runGuarded()`, with `VibeBug.initialize()` awaited just before it.
2. Finds your `MaterialApp`/`MaterialApp.router` and wires `VibeBugScope` into its `builder:`.
3. Generates `lib/vibebug_config.dart` with your backend base URL (no credentials — sign-in happens at runtime).

It always shows a diff and asks for confirmation before writing anything. Useful flags:

| Flag | Purpose |
|------|---------|
| `--yes` | Skip the confirmation prompt |
| `--base-url <url>` | Point at a self-hosted backend instead of the default `https://vibebugtracker.com` |

It takes a `.bak` backup of every file it touches. If your `main.dart`/`MaterialApp` don't match one of the simple shapes it knows how to rewrite safely, it leaves a `// TODO(vibebug): ...` comment explaining what to do manually — see [Troubleshooting](#troubleshooting-configure).

That's it — run your app. First launch shows a sign-in screen (tester/owner/admin email + password), then a project picker. Once a project is selected, every report from that device tracks against it until the user signs out (`VibeBug.signOut()`).

## How it works

```
┌──────────────────────────────────────────────────────────────┐
│  Your app (main.dart)                                        │
│   VibeBug.runGuarded(() { ensureInitialized(); runApp(); })  │
│        │ catches uncaught errors                             │
│        ▼                                                     │
│  VibeBugScope (wraps MaterialApp.builder)                    │
│   │ • floating Report bubble (draggable)                     │
│   │ • sign-in gate + project picker on first launch          │
│   │ • widget hit-testing for selectors                       │
│        ▼                                                     │
│  VibeBug.initialize(VibeBugOptions(...))                     │
│   │ • authenticates (token / email+password)                 │
│   │ • offline queue (SharedPreferences)                      │
│   │ • de-duplication window                                  │
│        ▼                                                     │
│  Vibe Bug Tracker API (/api/extension/issues)                │
└──────────────────────────────────────────────────────────────┘
```

Every report (crash, caught exception, or visual capture) goes through the same pipeline: authenticate → resolve target project/board/developer → enqueue → send immediately (or queue for offline retry).

## Manual / advanced setup

Skip `configure` and wire things up yourself if you want full control, or if you're integrating into a headless/CI/kiosk build. Supplying `email`/`password`/`token` to `VibeBugOptions` (or setting `enableAuthGate: false`) bypasses the built-in sign-in/picker screens entirely — this is the path used by this repo's own `flutter-vibebug-demo` app.

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

Call `initialize` before or after `runApp` (e.g. from your root widget after setup). If you want the built-in sign-in/picker gate (rather than supplying `email`/`password`/`token` yourself) and are wiring things up by hand instead of via `configure`, `await` `initialize()` before `runApp()` — otherwise your app's first frame can flash before the gate takes over. The generated `configure` output always does this for you.

## Visual bug reporting

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

## Options

`VibeBugOptions` fields:

| Field | Default | Purpose |
|-------|---------|---------|
| `baseUrl` | `https://vibebugtracker.com` | Backend base URL (self-hosting) |
| `token` | `null` | API token (bypasses sign-in) |
| `email` / `password` | `null` | Direct credentials (bypasses sign-in) |
| `projectId` / `boardId` / `assignedTo` | `null` | Default target project/board/developer |
| `autoReportCrashes` | `true` | Report uncaught exceptions automatically |
| `reportInBackground` | `true` | Send immediately; `false` = queue only |
| `defaultPriority` | `high` | Priority for auto-reported crashes |
| `dedupeWindow` | `5 min` | Suppress duplicate reports within this window |
| `screenshotProvider` | `null` | `Future<String?> Function()` for extra screenshots |
| `onIssueSent` | `null` | Callback with the created issue id |
| `onError` | `null` | Callback for send/queue errors |
| `enableAuthGate` | `null` | Auto-detect: on when no creds supplied, off otherwise |
| `autoSelectSoleProject` | `false` | Skip picker when sign-in resolves to exactly one project |

## API

### `VibeBug` (static)

| Method | Purpose |
|--------|---------|
| `initialize(options)` | Configure the SDK before `runApp` |
| `runGuarded(runner)` | Wrap `runApp` to catch async zone errors |
| `signIn(email:, password:)` | Authenticate a tester/owner/admin account |
| `signOut()` | Clear session + project selection |
| `selectProject(id)` / `selectBoard(id)` / `selectDeveloper(id)` | Change the active target |
| `reportException(error, stack, ...)` | Report a caught exception |
| `reportIssue(description:, ...)` | Report a text issue (optional screenshot) |
| `reportIssueWithCaptures(summary:, captures:, ...)` | Report a multi-screenshot visual issue |
| `flushPendingReports()` | Retry queued reports |

### Widgets

| Widget | Purpose |
|--------|---------|
| `VibeBugScope` | Draggable capture bubble + gate; wrap `MaterialApp.builder` |
| `VibeBugReportButton` | Legacy text-only report button |
| `VibeBugErrorBoundary` | Report subtree framework errors with a custom fallback |

### Models

- `VibeBugScreenshotShot` — one visual capture (selected + full screenshots, selector, semantics)
- `VibeBugProject` / `VibeBugBoard` / `VibeBugDeveloper` — target selection metadata

## Caught exceptions

```dart
try {
  await riskyOperation();
} catch (e, stack) {
  await VibeBug.reportException(e, stack, description: 'Checkout failed');
}
```

## Programmatic multi-capture submit

```dart
await VibeBug.reportIssueWithCaptures(
  summary: 'Checkout CTA overlaps total on small screens',
  captures: shots, // List<VibeBugScreenshotShot>
);
```

## Troubleshooting `configure`

`configure` refuses to guess when your `main.dart` or `MaterialApp` don't match a shape it can rewrite safely. Each reason it can print, and the manual fix:

| Reason | Manual fix |
|---|---|
| Multiple/zero `main()` or `runApp()` | Wrap your existing `runApp(...)` call in `VibeBug.runGuarded(() async { ...; await VibeBug.initialize(VibeBugOptions(baseUrl: ...)); runApp(...); });` yourself. |
| `runApp()` nested inside another callback, or has trailing code (e.g. `.then(...)`) | Same as above — move the `VibeBug.initialize()` call to just before wherever `runApp()` actually runs. |
| `VibeBug.runGuarded()` present but no `VibeBug.initialize()` inside it | Add `await VibeBug.initialize(VibeBugOptions(baseUrl: ...));` inside the `runGuarded` closure, before `runApp()`. |
| Multiple/zero `MaterialApp(...)` usages, or an existing non-trivial `builder:` | Wrap your `MaterialApp`'s `builder:` yourself, per the [Manual / advanced setup](#manual--advanced-setup) example above. |

## Notes

- Widget inspection works best in **debug/profile** builds where Flutter exposes widget creators
- Screenshot capture requires `VibeBugScope` (uses an internal `RepaintBoundary`)
- Requires a tester, project admin, or workspace owner/admin account with access to the target project — the SDK always reports as a tester (`X-VIT-Acting-Role: tester`), so owner/admin accounts with no dedicated tester seat are included automatically
- Reports use the same `/api/extension/issues` endpoint with a `screenshots[]` payload as the Chrome extension

## Development

```sh
cd packages/vibebug_flutter
flutter pub get
flutter analyze
flutter test
```

## License

MIT — see [LICENSE](LICENSE). Part of the [Vibe Bug Tracker](https://vibebugtracker.com) ecosystem.
