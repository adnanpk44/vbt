import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/vibebug_flutter.dart';

void main() {
  test('VibeBugOptions requires auth', () {
    expect(
      () => VibeBugOptions(projectId: 'proj_test'),
      throwsAssertionError,
    );
  });

  test('VibeBugOptions accepts token', () {
    final options = VibeBugOptions(projectId: 'proj_test', token: 'tok');
    expect(options.projectId, 'proj_test');
    expect(options.autoReportCrashes, isTrue);
  });
}
