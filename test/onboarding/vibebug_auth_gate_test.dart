import 'package:flutter_test/flutter_test.dart';
import 'package:vibebug_flutter/src/onboarding/vibebug_auth_gate.dart';

void main() {
  test('gate disabled always resolves to none, regardless of other state', () {
    expect(
      resolveGateStage(
        gateEnabled: false,
        authenticated: false,
        hasSelectedProject: false,
        autoSelectSoleProject: true,
        projectCount: 5,
      ),
      VibeBugGateStage.none,
    );
  });

  test('gate enabled and unauthenticated shows sign-in', () {
    expect(
      resolveGateStage(
        gateEnabled: true,
        authenticated: false,
        hasSelectedProject: false,
        autoSelectSoleProject: false,
        projectCount: 0,
      ),
      VibeBugGateStage.signIn,
    );
  });

  test('authenticated with a selected project resolves to none', () {
    expect(
      resolveGateStage(
        gateEnabled: true,
        authenticated: true,
        hasSelectedProject: true,
        autoSelectSoleProject: false,
        projectCount: 3,
      ),
      VibeBugGateStage.none,
    );
  });

  test('authenticated, no project, multiple projects shows the picker', () {
    expect(
      resolveGateStage(
        gateEnabled: true,
        authenticated: true,
        hasSelectedProject: false,
        autoSelectSoleProject: true,
        projectCount: 2,
      ),
      VibeBugGateStage.projectPicker,
    );
  });

  test('authenticated, no project, exactly one project, auto-select on auto-selects', () {
    expect(
      resolveGateStage(
        gateEnabled: true,
        authenticated: true,
        hasSelectedProject: false,
        autoSelectSoleProject: true,
        projectCount: 1,
      ),
      VibeBugGateStage.autoSelecting,
    );
  });

  test('authenticated, no project, exactly one project, auto-select off shows the picker', () {
    expect(
      resolveGateStage(
        gateEnabled: true,
        authenticated: true,
        hasSelectedProject: false,
        autoSelectSoleProject: false,
        projectCount: 1,
      ),
      VibeBugGateStage.projectPicker,
    );
  });
}
