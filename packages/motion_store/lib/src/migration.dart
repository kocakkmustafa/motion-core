typedef MigrationStep = Future<void> Function();

class MigrationPlan {
  const MigrationPlan({
    required this.fromVersion,
    required this.toVersion,
    required this.steps,
  });

  final int fromVersion;
  final int toVersion;
  final List<MigrationStep> steps;
}

/// Runs a [MigrationPlan]'s steps strictly in order. Fail-closed: if any
/// step throws, the exception propagates immediately and no later step
/// runs — a partially-applied schema migration must never be reported as
/// complete.
class MigrationRunner {
  Future<void> run(MigrationPlan plan) async {
    for (final step in plan.steps) {
      await step();
    }
  }
}
