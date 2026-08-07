## 0.4.9

### Fixed
- README screenshots and the `LICENSE`/`example/` links didn't render on pub.dev: its README sanitizer strips any `<img src>`/`<a href>` that isn't an absolute `https://` URL, regardless of whether the file actually exists. All of them now point at absolute `github.com/adnanpk44/vbt` URLs instead of relative repo paths. (0.4.8's README is unaffected by this fix — pub.dev versions are immutable — but 0.4.9 and on display correctly.)

## 0.4.8

### Added
- `dart run vibebug_flutter:configure --hide-report-button` / `--show-report-button` toggle the floating Report button in an already-configured app without a manual code edit — finds the file with `VibeBugScope(...)`, shows a diff, and takes a `.bak` backup, same as the main `configure` command. Equivalent to setting `VibeBugScope.showReportButton` (already existed, default `true`) by hand.

### Changed
- README documents the Report/capture/send flow with screenshots from the example app, and links them to the new show/hide command.

## 0.4.7

### Fixed
- `dart run vibebug_flutter:configure` now wires `VibeBugScope` into apps with multiple `MaterialApp`/`CupertinoApp` roots (e.g. a main app plus a Picture-in-Picture widget): it picks the root that threads a `navigatorKey` instead of bailing out as "ambiguous".
- The configure tool no longer mistakes a `builder:` nested inside `routes:` / `onGenerateRoute:` for the app root's own `builder:` — the real app builder is found and wrapped, and nested route builders are left untouched.
- `navigatorKey: SomeService.navigatorKey` property chains are threaded into `VibeBugScope` correctly (previously only the first identifier was captured, producing `navigatorKey: SomeService`).

## 0.4.6

### Changed
- **The gate's default behavior changed**: it no longer blocks your whole app behind a sign-in screen on launch. Your app now shows immediately as normal, and the sign-in + project-picker flow appears the first time a tester taps the floating Report button — the right default for embedding into an existing app that has its own regular users (who should never see a VibeBug screen at all). The old block-the-whole-app behavior is still available via the new `VibeBugOptions.blockAppUntilReady: true`, for dedicated tester apps.

## 0.4.5

### Fixed
- `dart run vibebug_flutter:configure` no longer gets confused by commented-out code or URL strings: detection now runs against a comment/string-aware scan of the file, so a leftover commented-out `main()` or `MaterialApp(...)` (e.g. from an earlier refactor) is never mistaken for a second real occurrence and no longer triggers a false "found 2" / "ambiguous" bail-out. `'https://...'` strings are also no longer mistaken for the start of a `//` comment.

### Changed
- README leads with the two-command quick start and documents that `configure` correctly ignores comments/strings while scanning.

## 0.4.4

### Fixed
- `dart run vibebug_flutter:configure` now handles real-world apps automatically instead of bailing out and requiring manual edits: it wraps whatever your existing `MaterialApp`/`CupertinoApp` `builder:` already returns with `VibeBugScope` (instead of only handling a bare pass-through), preserving any existing wrapping (localization, screen-size init, theming, etc.) unchanged. Also now recognizes `GetMaterialApp`/`GetCupertinoApp` (GetX) as app-root widgets, not just `MaterialApp`.

## 0.4.3

### Fixed
- The built-in sign-in and project-picker screens now work correctly: they were rendered as a direct replacement of `MaterialApp`'s `child` (via `builder:`), which discarded the app's real `Navigator`/`Overlay`. This broke anything needing one — the project dropdown's popup menu wouldn't open, and tapping into the email/password fields could throw `No Overlay widget found`. The gate now wraps its screens in their own `Navigator`, so they work self-contained regardless of the host app's structure.

## 0.4.2

### Changed
- Upgrade `flutter_secure_storage` from `^9.2.4` to `^10.0.0` (resolves version conflicts in apps already on the v10 API, e.g. `flutter_secure_storage ^10.0.0-beta.5`). Token read/write/delete API is unchanged.

## 0.4.1

### Added
- Complete runnable example app in `example/` — clone the repo, `flutter pub get && flutter run`, and test crash reporting, the capture bubble, and the offline queue against your own account.

## 0.4.0

### Added
- Zero-config setup: `dart run vibebug_flutter:configure` rewrites `main.dart` and `MaterialApp` to wire everything in automatically — no manual code required beyond adding the dependency.
- Built-in full-screen sign-in and project-picker screens (`VibeBugLoginScreen`, `VibeBugProjectPickerScreen`), shown automatically by `VibeBugScope` on first launch when no `email`/`password`/`token` are configured.
- `VibeBug.signOut()`.
- `VibeBugOptions.enableAuthGate` / `autoSelectSoleProject`.

### Fixed
- Owner/admin accounts without an explicit `tester` project seat are now correctly offered their projects (`VibeBugProject.canActAsTester`), and the SDK now sends `X-VIT-Acting-Role: tester` on authenticated requests.

### Changed
- `VibeBug.signIn()` no longer silently auto-picks a project — callers (the new gate, or the existing capture-bubble sign-in) must call `VibeBug.selectProject()` explicitly. `VibeBug.initialize()`'s direct-config path (email/password/token supplied programmatically) keeps its existing auto-pick-first-project behavior unchanged.

## 0.3.3

Initial capture-bubble release: draggable report button, widget picker, capture region editor, multi-screenshot issues, Flutter-specific AI markdown, and offline queue.
