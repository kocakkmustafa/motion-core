import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

void main() {
  group('AtomicEraser — honest multi-component erase report', () {
    test('reports allSucceeded true when every component erases cleanly', () async {
      final erased = <String>[];
      final eraser = AtomicEraser({
        'journal': () async => erased.add('journal'),
        'projection': () async => erased.add('projection'),
        'diagnostics': () async => erased.add('diagnostics'),
      });
      final report = await eraser.eraseAll();
      expect(report.allSucceeded, isTrue);
      expect(erased, unorderedEquals(['journal', 'projection', 'diagnostics']));
    });

    test('fail-closed: one failing component is reported honestly, and does '
        'not stop the others from still being erased', () async {
      final erased = <String>[];
      final eraser = AtomicEraser({
        'journal': () async => erased.add('journal'),
        'projection': () async => throw StateError('locked'),
        'diagnostics': () async => erased.add('diagnostics'),
      });
      final report = await eraser.eraseAll();
      expect(report.allSucceeded, isFalse,
          reason: 'a partial delete must never be reported as full success');
      expect(erased, unorderedEquals(['journal', 'diagnostics']),
          reason: 'one component failing must not block the others from erasing');
      final projectionResult =
          report.results.firstWhere((r) => r.component == 'projection');
      expect(projectionResult.succeeded, isFalse);
      expect(projectionResult.error, isNotNull);
    });
  });
}
