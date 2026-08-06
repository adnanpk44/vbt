import 'package:flutter/material.dart';

/// Sample screen for live testing with the package Report bubble (VibeBugScope).
class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Demo checkout',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the floating Report bubble from vibebug_flutter, then tap a widget '
              '(Pay now, title, etc.) to open the crop editor.',
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('pay_now'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pay tapped — no crash')),
                );
              },
              child: const Text('Pay now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('simulate_pay_crash'),
              onPressed: () => throw const FormatException('Payment gateway timeout'),
              child: const Text('Simulate pay crash'),
            ),
          ],
        ),
      ),
    );
  }
}
