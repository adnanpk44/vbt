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
}
