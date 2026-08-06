# vibebug_flutter

Flutter SDK for [Vibe Bug Tracker](https://vibebugtracker.com) — crash reporting plus Chrome-extension-style visual bug capture for Flutter apps under live testing.

## Features

- **Zero-config setup** — one command wires everything into your app, no manual code required
- **Built-in sign-in + project picker** — first launch shows a login screen, then a project dropdown; from then on issues are tracked against that project automatically
- Automatic crash and uncaught exception reporting
- **Draggable Report button** — testers can move the bubble anywhere on screen
- **Capture region editor** — after selecting a widget, crop/adjust the region and draw highlight marks before saving
- **Multi-screenshot issues** — up to 8 captures per issue, like the Chrome extension
- **Flutter-specific AI markdown** — issue descriptions include widget selectors, route, and Flutter fix guidance
- Offline queue with retry when connectivity returns

## Quick start (recommended)

```
flutter pub add vibebug_flutter
dart run vibebug_flutter:configure
```

The `configure` command:

1. Rewrites `main.dart` so `runApp()` runs inside `VibeBug.runGuarded()`, with `VibeBug.initialize()` awaited just before it.
2. Finds your `MaterialApp`/`MaterialApp.router` and wires `VibeBugScope` into its `builder:`.
3. Generates `lib/vibebug_config.dart` with your backend base URL (no credentials — sign-in happens at runtime).

It always shows a diff and asks for confirmation before writing anything (pass `--yes` to skip the prompt, and `--base-url <url>` to point at a self-hosted backend), and takes a `.bak` backup of every file it touches. If your `main.dart`/`MaterialApp` don't match one of the simple shapes it knows how to rewrite safely, it leaves a `// TODO(vibebug): ...` comment explaining what to do manually instead of guessing — see [Troubleshooting](#troubleshooting-configure) below.

That's it — run your app. First launch shows a sign-in screen (tester/owner/admin email + password), then a project picker. Once a project is selected, every report from that device tracks against it until the user signs out (`VibeBug.signOut()`).

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

## Gate options

- `VibeBugOptions.enableAuthGate` — defaults to `null` (auto-detect: enabled when none of `email`/`password`/`token` are supplied, disabled otherwise). Set explicitly to override.
- `VibeBugOptions.autoSelectSoleProject` — when the gate is enabled and sign-in resolves to exactly one eligible project, skip the picker and select it automatically. Defaults to `false` (always confirm, even with one project).
- `VibeBug.signOut()` — clears the cached session and project selection; `VibeBugScope` returns to the sign-in screen.

## Troubleshooting `configure`

`configure` refuses to guess when your `main.dart` or `MaterialApp` don't match a shape it can rewrite safely. Each reason it can print, and the manual fix:

| Reason | Manual fix |
|---|---|
| Multiple/zero `main()` or `runApp()` | Wrap your existing `runApp(...)` call in `VibeBug.runGuarded(() async { ...; await VibeBug.initialize(VibeBugOptions(baseUrl: ...)); runApp(...); });` yourself. |
| `runApp()` nested inside another callback, or has trailing code (e.g. `.then(...)`) | Same as above — move the `VibeBug.initialize()` call to just before wherever `runApp()` actually runs. |
| `VibeBug.runGuarded()` present but no `VibeBug.initialize()` inside it | Add `await VibeBug.initialize(VibeBugOptions(baseUrl: ...));` inside the `runGuarded` closure, before `runApp()`. |
| Multiple/zero `MaterialApp(...)` usages, or an existing non-trivial `builder:` | Wrap your `MaterialApp`'s `builder:` yourself, per the [Manual / advanced setup](#manual--advanced-setup) example above. |

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
- Requires a tester, project admin, or workspace owner/admin account with access to the target project — the SDK always reports as a tester (`X-VIT-Acting-Role: tester`), so owner/admin accounts with no dedicated tester seat are included automatically
