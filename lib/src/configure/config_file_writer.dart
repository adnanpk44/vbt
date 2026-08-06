/// Contents of the generated `lib/vibebug_config.dart` written by
/// `dart run vibebug_flutter:configure`. Deliberately contains no
/// credentials — sign-in happens interactively at runtime via the SDK's
/// built-in login screen.
String buildConfigFileContents({required String baseUrl}) => '''
// GENERATED CODE — safe to hand-edit, but not required.
// Regenerate anytime with `dart run vibebug_flutter:configure`.
//
// Intentionally contains no credentials — VibeBug sign-in happens
// interactively at runtime via the SDK's built-in login screen.

/// Non-secret VibeBug SDK defaults for this app.
abstract final class VibeBugConfig {
  static const baseUrl = '$baseUrl';
}
''';
