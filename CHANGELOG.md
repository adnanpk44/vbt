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
