# vibebug_flutter

[![pub package](https://img.shields.io/pub/v/vibebug_flutter.svg)](https://pub.dev/packages/vibebug_flutter)
[![pub points](https://img.shields.io/pub/points/vibebug_flutter)](https://pub.dev/packages/vibebug_flutter/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Crash reporting plus Chrome-extension-style **visual bug capture** for Flutter apps — sends issues to [Vibe Bug Tracker](https://vibebugtracker.com) with screenshots, widget selectors, and Flutter-specific AI markdown.

Testers in your app can capture a widget, crop and highlight the region, add screenshots, and send a fully-described issue straight to your tracker board — no Chrome extension required.

## Get started in two commands

```sh
flutter pub add vibebug_flutter
dart run vibebug_flutter:configure
```

That's it — run your app. No manual code to write: `configure` finds and rewrites `main.dart` and your `MaterialApp`/`CupertinoApp`/`GetMaterialApp` itself, whatever your existing setup looks like (localization, theming, screen-size init — it wraps what's already there instead of replacing it). It always shows you the diff and asks before writing anything. See [Installation](#installation) below for details, flags, and what to do in the rare case it can't rewrite something safely.

## Features

- **Zero-config setup** — one command wires everything into your app, no manual code required
- **Built-in sign-in + project picker** — your app runs normally from launch; the first time a tester taps the floating Report button, they see a login screen, then a project dropdown, and every report after that tracks against it automatically
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
2. Finds your app root widget — `MaterialApp`, `MaterialApp.router`, `CupertinoApp`, or GetX's `GetMaterialApp` — and wires `VibeBugScope` into its `builder:`. If you already have a `builder:` (localization, screen-size init, theming, anything), it wraps whatever it already returns instead of replacing it, so your existing setup keeps working.
3. Generates `lib/vibebug_config.dart` with your backend base URL (no credentials — sign-in happens at runtime).

It always shows a diff and asks for confirmation before writing anything. Useful flags:

| Flag | Purpose |
|------|---------|
| `--yes` | Skip the confirmation prompt |
| `--base-url <url>` | Point at a self-hosted backend instead of the default `https://vibebugtracker.com` |

It takes a `.bak` backup of every file it touches. Comments and string contents (e.g. `'https://...'` URLs) are correctly ignored while scanning — leftover commented-out code (an old `main()`, an old `MaterialApp` from a previous refactor) is never mistaken for a second real one. If your `main.dart`/app root still don't match one of the shapes it knows how to rewrite safely, it leaves a `// TODO(vibebug): ...` comment explaining exactly what to do manually and why — see [Troubleshooting](#troubleshooting-configure).

That's it — run your app. It launches straight into your normal UI, exactly as before — nothing is blocked. The first time a tester taps the floating **Report** button, they see a sign-in screen (tester/owner/admin email + password), then a project picker; back out of either and nothing happens. Once a project is selected, every report from that device tracks against it until the user signs out (`VibeBug.signOut()`), and tapping Report goes straight into capture mode.

If you'd rather block the whole app behind sign-in until it's ready — appropriate for a dedicated tester app whose only purpose is reporting — pass `VibeBugOptions(blockAppUntilReady: true)`. See [Gate behavior](#gate-behavior) below.

## Example app

A complete runnable demo app lives in [`example/`](example/README.md) — clone the repo and run it to test every SDK feature against your own Vibe Bug Tracker account:

```sh
git clone https://github.com/adnanpk44/vbt.git
cd vbt/example
flutter pub get
flutter run
```

It exercises crash reporting, caught exceptions, the draggable capture bubble, widget picker, and the offline queue.

## How it works

```
┌──────────────────────────────────────────────────────────────┐
│  Your app (main.dart)                                        │
│   VibeBug.runGuarded(() { ensureInitialized(); runApp(); })  │
│        │ catches uncaught errors                             │
│        ▼                                                     │
│  VibeBugScope (wraps MaterialApp.builder)                    │
│   │ • floating Report bubble (draggable)                     │
│   │ • sign-in + project picker gate, on first Report tap     │
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
2. **Tap** the bubble — the first time, this is where sign-in and project selection happen (see [Gate behavior](#gate-behavior)); after that it goes straight to step 3
3. **Tap a widget** to capture it
4. **Crop / highlight** in the full-screen editor, add a per-capture note, then **Save**
5. Navigate to other screens freely, tap **Report** again to add more (up to 8)
6. Tap the **badge** on the bubble to review, choose the board/developer/priority, then **Send**

Long-press the bubble to clear draft captures.

## Gate behavior

`VibeBugOptions.blockAppUntilReady` controls *when* the built-in sign-in/project-picker flow appears, for apps using the gate (i.e. not supplying `email`/`password`/`token` directly):

| | `blockAppUntilReady: false` (default) | `blockAppUntilReady: true` |
|---|---|---|
| On launch | Your app shows immediately, unchanged | Blocked behind sign-in/picker until both are done |
| Sign-in/picker appear | The first time the tester taps **Report** | Before your app is shown at all |
| Best for | Embedding into an existing app with its own regular users (most apps — this is the default for exactly that reason) | A dedicated tester app whose only purpose is reporting |

Regular users of your app who never tap Report never see a VibeBug screen at all under the default setting — nothing about your app's normal UI changes.

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
| `blockAppUntilReady` | `false` | `true` blocks the whole app behind the gate on launch instead of gating the Report button — see [Gate behavior](#gate-behavior) |

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
| Multiple/zero app root widgets (`MaterialApp`, `CupertinoApp`, `GetMaterialApp`) found | Wrap your app's `builder:` yourself, per the [Manual / advanced setup](#manual--advanced-setup) example above. |
| `builder:`'s body has a shape this tool doesn't recognize (multiple return statements, an unusual parameter list, etc.) | Wrap whatever your `builder:` currently returns with `VibeBugScope(child: ...)` yourself. |

Still stuck, or `configure` bailed for a reason not listed here? [Open an issue](https://github.com/adnanpk44/vbt/issues) with the exact message it printed — that's a gap in the tool, not something you're doing wrong, and it helps fix it for the next person too.

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
