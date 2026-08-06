typedef VibeBugScreenshotProvider = Future<String?> Function();

class VibeBugOptions {
  const VibeBugOptions({
    this.projectId,
    this.baseUrl = 'https://vibebugtracker.com',
    this.token,
    this.email,
    this.password,
    this.boardId,
    this.assignedTo,
    this.autoReportCrashes = true,
    this.reportInBackground = true,
    this.defaultPriority = 'high',
    this.dedupeWindow = const Duration(minutes: 5),
    this.screenshotProvider,
    this.onIssueSent,
    this.onError,
    this.enableAuthGate,
    this.autoSelectSoleProject = false,
    this.blockAppUntilReady = false,
  });

  final String baseUrl;
  final String? token;
  final String? email;
  final String? password;

  /// Optional default project. If omitted, testers choose from their assigned
  /// projects before sending an issue.
  final String? projectId;
  final String? boardId;
  final String? assignedTo;
  final bool autoReportCrashes;
  final bool reportInBackground;
  final String defaultPriority;
  final Duration dedupeWindow;
  final VibeBugScreenshotProvider? screenshotProvider;
  final void Function(String issueId)? onIssueSent;
  final void Function(Object error)? onError;

  /// Whether [VibeBugScope] should show the built-in full-screen sign-in and
  /// project-picker flow before rendering your app.
  ///
  /// Defaults to `null`, which auto-detects: the gate is enabled when none of
  /// [email], [password], or [token] were supplied (the zero-config path
  /// produced by `dart run vibebug_flutter:configure`), and disabled when any
  /// of them were (a direct-config app that manages its own credentials).
  /// Set this explicitly to override the auto-detection.
  final bool? enableAuthGate;

  /// When the gate is enabled and sign-in resolves to exactly one
  /// tester-accessible project, skip the project-picker screen and select it
  /// automatically instead of asking the user to confirm.
  final bool autoSelectSoleProject;

  /// How the gate shows itself when [enableAuthGate] is on.
  ///
  /// Defaults to `false`: the app runs normally from launch, and the SDK's
  /// sign-in/project-picker screens only appear the first time the tester
  /// taps the floating Report button — the right default when embedding
  /// this SDK into an existing app that has its own regular users, who
  /// should never see a VibeBug login screen at all.
  ///
  /// Set to `true` to block [VibeBugScope]'s `child` behind the gate until
  /// sign-in and project selection are both complete, before the app is
  /// shown at all — appropriate for a dedicated tester app whose only
  /// purpose is reporting issues.
  final bool blockAppUntilReady;
}
