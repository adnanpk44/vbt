# vibebug_sdk_demo

Demo Flutter app for testing [`vibebug_flutter`](https://pub.dev/packages/vibebug_flutter) — crash reporting, caught exceptions, and live visual bug submission.

## Run

```bash
cd example
flutter pub get
flutter run
```

Or clone the package repo and run from the `example/` folder:

```bash
git clone https://github.com/adnanpk44/vbt.git
cd vbt/example
flutter pub get
flutter run
```

## First launch

1. Enter your **tester** email/password from Vibe Bug Tracker (the built-in sign-in gate shows automatically)
2. Pick your project from the project picker
3. Start tapping the floating Report bubble to capture widgets, crop, and send issues

## Test scenarios

| Action | What it tests |
|--------|----------------|
| Report issue (dialog) | `VibeBug.reportIssue()` |
| Checkout screen FAB | `VibeBugReportButton` widget |
| Report caught exception | `VibeBug.reportException()` |
| Sync throw | Uncaught sync error → auto-report |
| Async Future.error | Zone error via `VibeBug.runGuarded()` |
| Flutter framework error | `FlutterError.onError` handler |
| Flush pending reports | Offline queue retry |

Verify issues appear in the Vibe Bug Tracker dashboard for your project (Ongoing tab).

## Package dependency

```yaml
dependencies:
  vibebug_flutter:
    path: ../
```

Edit the SDK in the parent `lib/` folder, then hot restart this app to retest.
