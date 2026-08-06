import 'package:flutter/material.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

import 'app.dart';

void main() {
  // ensureInitialized + runApp must share the same zone as runGuarded.
  VibeBug.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Awaiting initialize() before runApp() (the same shape
    // `dart run vibebug_flutter:configure` generates) means VibeBugScope's
    // very first build already knows the gate's real state — no flash of
    // app content (or the report bubble) before sign-in resolves.
    await VibeBug.initialize(VibeBugOptions(
      onIssueSent: (issueId) => demoLastIssueId.value = issueId,
      onError: (error) => demoError.value = error.toString(),
    ));
    runApp(const SdkDemoApp());
  });
}
