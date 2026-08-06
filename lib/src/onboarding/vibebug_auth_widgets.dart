import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../vibebug.dart';

/// Email/password sign-in form used by both [VibeBugLoginScreen] and the
/// capture-bubble's bottom sheet.
///
/// [signIn] defaults to [VibeBug.signIn] but is injectable so this widget can
/// be tested without a network call.
class VibeBugSignInForm extends StatefulWidget {
  const VibeBugSignInForm({
    super.key,
    required this.onSignedIn,
    this.signIn = VibeBug.signIn,
    this.emailLabel = 'Email',
    this.passwordLabel = 'Password',
    this.submitLabel = 'Sign in',
  });

  /// Called after a successful sign-in with the account's eligible projects.
  final ValueChanged<List<VibeBugProject>> onSignedIn;
  final Future<void> Function({required String email, required String password})
      signIn;
  final String emailLabel;
  final String passwordLabel;
  final String submitLabel;

  @override
  State<VibeBugSignInForm> createState() => _VibeBugSignInFormState();
}

class _VibeBugSignInFormState extends State<VibeBugSignInForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _signingIn = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await widget.signIn(email: email, password: password);
      if (!mounted) return;
      setState(() => _signingIn = false);
      widget.onSignedIn(VibeBug.projects);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn = false;
        _error = 'Sign in failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.emailLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_signingIn) unawaited(_submit());
          },
          decoration: InputDecoration(
            labelText: widget.passwordLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _signingIn ? null : () => unawaited(_submit()),
          child: Text(_signingIn ? 'Signing in...' : widget.submitLabel),
        ),
      ],
    );
  }
}

/// Dropdown for choosing a [VibeBugProject].
class VibeBugProjectDropdown extends StatelessWidget {
  const VibeBugProjectDropdown({
    super.key,
    required this.projects,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.decoration = const InputDecoration(
      border: OutlineInputBorder(),
      labelText: 'Project',
    ),
  });

  final List<VibeBugProject> projects;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) {
    final resolvedValue =
        projects.any((project) => project.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: resolvedValue,
      items: [
        for (final project in projects)
          DropdownMenuItem(
            value: project.id,
            child: Text(
              project.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      decoration: decoration,
    );
  }
}
