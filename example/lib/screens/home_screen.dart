import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

import 'checkout_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onClearStatus,
    this.lastIssueId,
    this.error,
  });

  final VoidCallback onClearStatus;
  final String? lastIssueId;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VibeBug SDK Demo'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => unawaited(VibeBug.signOut()),
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lastIssueId != null || error != null) _StatusCard(
            lastIssueId: lastIssueId,
            error: error,
            onDismiss: onClearStatus,
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.bug_report_outlined, color: Color(0xFF10B981)),
              title: Text('Use the floating Report bubble'),
              subtitle: Text(
                'From vibebug_flutter (VibeBugScope): tap Report → tap a widget → crop/move/resize the frame → Save.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Trigger scenarios below to verify the SDK sends issues to your project.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Manual reports',
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Report issue (text only)'),
                subtitle: const Text('Quick text report without widget capture'),
                onTap: () => _showManualReport(context),
              ),
              ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: const Text('Open checkout screen'),
                subtitle: const Text('Use the Report bubble to capture widgets here'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                ),
              ),
            ],
          ),
          _Section(
            title: 'Caught exceptions',
            children: [
              ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('Report caught exception'),
                subtitle: const Text('try/catch → VibeBug.reportException'),
                onTap: () => _reportCaught(context),
              ),
            ],
          ),
          _Section(
            title: 'Uncaught crashes (auto-report)',
            children: [
              ListTile(
                leading: const Icon(Icons.bolt_outlined, color: Colors.orange),
                title: const Text('Sync throw'),
                subtitle: const Text('Throws in button handler'),
                onTap: () => _throwSync(),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined, color: Colors.orange),
                title: const Text('Async Future.error'),
                subtitle: const Text('Zone error via runGuarded'),
                onTap: _throwAsync,
              ),
              ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('Flutter framework error'),
                subtitle: const Text('Invalid assertion — may show red screen in debug'),
                onTap: () => _throwFlutterError(),
              ),
            ],
          ),
          _Section(
            title: 'Queue',
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Flush pending reports'),
                subtitle: const Text('Retry offline-queued issues'),
                onTap: () async {
                  await VibeBug.flushPendingReports();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Flush completed')),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showManualReport(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual issue'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Describe the bug…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().length >= 3) {
      final id = await VibeBug.reportIssue(
        description: controller.text.trim(),
        pageUrl: '/demo-home',
        widgetKey: 'manual_dialog',
        priority: 'medium',
      );
      controller.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(id != null ? 'Sent $id' : 'Queued or deduplicated')),
        );
      }
    } else {
      controller.dispose();
    }
  }

  Future<void> _reportCaught(BuildContext context) async {
    try {
      throw StateError('Demo caught exception from checkout validation');
    } catch (e, stack) {
      final id = await VibeBug.reportException(
        e,
        stack,
        description: 'Checkout validation failed in demo app',
        pageUrl: '/demo-home',
        widgetKey: 'validate_checkout',
        priority: 'high',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(id != null ? 'Reported $id' : 'Queued or deduplicated')),
        );
      }
    }
  }

  void _throwSync() {
    throw Exception('Demo sync crash — tap handler');
  }

  void _throwAsync() {
    Future<void>.delayed(Duration.zero, () {
      throw Exception('Demo async zone crash');
    });
  }

  void _throwFlutterError() {
    assert(false, 'Demo Flutter framework error');
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.lastIssueId,
    required this.error,
    required this.onDismiss,
  });

  final String? lastIssueId;
  final String? error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: error != null ? colorScheme.errorContainer : colorScheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        title: Text(error != null ? 'SDK error' : 'Last issue sent'),
        subtitle: Text(error ?? lastIssueId ?? ''),
        trailing: IconButton(icon: const Icon(Icons.close), onPressed: onDismiss),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(
          child: Column(children: children),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
