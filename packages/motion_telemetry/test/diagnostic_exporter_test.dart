import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

void main() {
  group('DiagnosticExporter — explicit user action only', () {
    const exporter = DiagnosticExporter();

    test('exports when the user has both previewed and confirmed', () {
      const request = DiagnosticExportRequest(userPreviewed: true, userConfirmed: true);
      expect(exporter.export(request, 'bundle-payload'), 'bundle-payload');
    });

    test('fail-closed: refuses without a preview even if confirmed', () {
      const request = DiagnosticExportRequest(userPreviewed: false, userConfirmed: true);
      expect(exporter.export(request, 'bundle-payload'), isNull);
    });

    test('fail-closed: refuses without explicit confirmation even if previewed', () {
      const request = DiagnosticExportRequest(userPreviewed: true, userConfirmed: false);
      expect(exporter.export(request, 'bundle-payload'), isNull);
    });

    test('fail-closed: refuses when neither previewed nor confirmed — no automatic export', () {
      const request = DiagnosticExportRequest(userPreviewed: false, userConfirmed: false);
      expect(exporter.export(request, 'bundle-payload'), isNull);
    });
  });
}
