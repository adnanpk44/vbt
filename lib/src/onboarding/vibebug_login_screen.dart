import 'package:flutter/material.dart';

import '../api_client.dart';
import 'vibebug_auth_widgets.dart';

/// Full-screen sign-in shown by [VibeBugScope] on first launch, before any
/// project has been chosen.
class VibeBugLoginScreen extends StatelessWidget {
  const VibeBugLoginScreen({
    super.key,
    this.onSignedIn,
    this.title = 'Sign in to report issues',
    this.subtitle =
        'Sign in with your Vibe Bug Tracker account to start reporting issues from this app.',
  });

  /// Called after a successful sign-in. [VibeBugScope] doesn't need this —
  /// its [AnimatedBuilder] already rebuilds from [VibeBug.listenable] — but
  /// it's useful when embedding this screen directly in your own navigation.
  final ValueChanged<List<VibeBugProject>>? onSignedIn;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  VibeBugSignInForm(
                    emailLabel: 'Email',
                    onSignedIn: (projects) => onSignedIn?.call(projects),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
