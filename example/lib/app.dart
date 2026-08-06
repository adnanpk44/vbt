import 'package:flutter/material.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

import 'screens/home_screen.dart';

/// Set by [VibeBugOptions.onIssueSent]/[onError] callbacks in `main.dart`,
/// which run before this widget tree exists (VibeBug.initialize() is
/// awaited before runApp()) — a ValueNotifier lets HomeScreen react to them
/// without needing a State to call setState on from outside the tree.
final ValueNotifier<String?> demoLastIssueId = ValueNotifier(null);
final ValueNotifier<String?> demoError = ValueNotifier(null);

class SdkDemoApp extends StatefulWidget {
  const SdkDemoApp({super.key});

  @override
  State<SdkDemoApp> createState() => _SdkDemoAppState();
}

class _SdkDemoAppState extends State<SdkDemoApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _clearStatus() {
    demoLastIssueId.value = null;
    demoError.value = null;
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp must wrap VibeBugScope so Directionality/Theme exist for the
    // package overlay. Use builder so the capture shell — and, before sign-in,
    // the built-in login/project-picker gate — sits above routes.
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'VibeBug SDK Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return VibeBugScope(
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AnimatedBuilder(
        animation: Listenable.merge([demoLastIssueId, demoError]),
        builder: (context, _) => HomeScreen(
          lastIssueId: demoLastIssueId.value,
          error: demoError.value,
          onClearStatus: _clearStatus,
        ),
      ),
    );
  }
}
