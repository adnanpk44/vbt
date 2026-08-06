import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import 'vibebug_auth_widgets.dart';

/// Full-screen project picker shown by [VibeBugScope] after sign-in, when the
/// account has more than one tester-accessible project (or always, unless
/// [VibeBugOptions.autoSelectSoleProject] is set).
class VibeBugProjectPickerScreen extends StatefulWidget {
  const VibeBugProjectPickerScreen({
    super.key,
    required this.projects,
    required this.onProjectSelected,
    this.onSignOut,
    this.title = 'Choose a project',
    this.subtitle = 'Issues you report will be tracked on this project\'s board.',
  });

  final List<VibeBugProject> projects;

  /// Called with the chosen project id when "Next" is pressed.
  final Future<void> Function(String projectId) onProjectSelected;

  /// Called when "Sign out" is pressed. Omit to hide the action.
  final Future<void> Function()? onSignOut;
  final String title;
  final String subtitle;

  @override
  State<VibeBugProjectPickerScreen> createState() =>
      _VibeBugProjectPickerScreenState();
}

class _VibeBugProjectPickerScreenState
    extends State<VibeBugProjectPickerScreen> {
  String? _selected;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.projects.length == 1) {
      _selected = widget.projects.first.id;
    }
  }

  Future<void> _next() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onProjectSelected(selected);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not select this project: $e';
      });
      return;
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.onSignOut == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              actions: [
                TextButton(
                  onPressed:
                      _submitting ? null : () => unawaited(widget.onSignOut!()),
                  child: const Text('Sign out'),
                ),
              ],
            ),
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
                  Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  if (widget.projects.isEmpty)
                    Text(
                      'No tester-accessible projects are assigned to this account yet. '
                      'Ask a project owner to add you as a tester, then sign in again.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  else
                    VibeBugProjectDropdown(
                      projects: widget.projects,
                      value: _selected,
                      enabled: !_submitting,
                      onChanged: (value) => setState(() => _selected = value),
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
                    onPressed: _submitting || _selected == null
                        ? null
                        : () => unawaited(_next()),
                    child: Text(_submitting ? 'Loading...' : 'Next'),
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
