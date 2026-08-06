import 'package:flutter/material.dart';

/// Which screen [VibeBugScope] should show for the current auth/project
/// state. A pure function of state so it's unit-testable without pumping a
/// widget tree.
enum VibeBugGateStage {
  /// The gate is disabled, or fully resolved — render the app.
  none,

  /// No cached session — show [VibeBugLoginScreen].
  signIn,

  /// Signed in but no project chosen yet — show [VibeBugProjectPickerScreen].
  projectPicker,

  /// Signed in, exactly one eligible project, and auto-select is enabled —
  /// select it and show a brief loading state instead of the picker.
  autoSelecting,
}

VibeBugGateStage resolveGateStage({
  required bool gateEnabled,
  required bool authenticated,
  required bool hasSelectedProject,
  required bool autoSelectSoleProject,
  required int projectCount,
}) {
  if (!gateEnabled) return VibeBugGateStage.none;
  if (!authenticated) return VibeBugGateStage.signIn;
  if (hasSelectedProject) return VibeBugGateStage.none;
  if (autoSelectSoleProject && projectCount == 1) {
    return VibeBugGateStage.autoSelecting;
  }
  return VibeBugGateStage.projectPicker;
}

/// Brief splash shown while [VibeBugGateStage.autoSelecting] resolves.
class VibeBugGateLoading extends StatelessWidget {
  const VibeBugGateLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
