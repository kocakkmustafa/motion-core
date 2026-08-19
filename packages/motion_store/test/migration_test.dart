import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

void main() {
  group('MigrationRunner — fail-closed, ordered', () {
    test('runs every step in order on a healthy plan', () async {
      final log = <int>[];
      final plan = MigrationPlan(
        fromVersion: 1,
        toVersion: 4,
        steps: [
          () async => log.add(1),
          () async => log.add(2),
          () async => log.add(3),
        ],
      );
      await MigrationRunner().run(plan);
      expect(log, [1, 2, 3]);
    });

    test('fail-closed: a throwing step stops the plan and later steps never run', () async {
      final log = <int>[];
      final plan = MigrationPlan(
        fromVersion: 1,
        toVersion: 3,
        steps: [
          () async => log.add(1),
          () async => throw StateError('step 2 failed'),
          () async => log.add(3),
        ],
      );
      await expectLater(() => MigrationRunner().run(plan), throwsStateError);
      expect(log, [1], reason: 'step 3 must never run once step 2 has thrown');
    });
  });
}
