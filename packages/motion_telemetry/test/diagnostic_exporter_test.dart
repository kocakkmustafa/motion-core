import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

const _policy = DiagnosticExportPolicy(
  allowedCodes: {'network_timeout'},
  fields: {
    'buildMode': DiagnosticFieldShape.buildMode,
    'code': DiagnosticFieldShape.code,
    'platform': DiagnosticFieldShape.platform,
    'version': DiagnosticFieldShape.version,
  },
);
final _bundle = SafeDiagnosticBundle(
  platform: DiagnosticPlatform.ios,
  buildMode: DiagnosticBuildMode.release,
  version: DiagnosticVersion(major: 1, minor: 0, patch: 0, build: 1),
  code: DiagnosticCodeCandidate('network_timeout'),
);

void main() {
  group('DiagnosticExporter — explicit user action only', () {
    final exporter = DiagnosticExporter();

    test('exports when the user has both previewed and confirmed', () {
      const request = DiagnosticExportRequest(
        userPreviewed: true,
        userConfirmed: true,
      );
      expect(exporter.export(request, _bundle, _policy), isNotNull);
    });

    test('fail-closed: refuses without a preview even if confirmed', () {
      const request = DiagnosticExportRequest(
        userPreviewed: false,
        userConfirmed: true,
      );
      expect(exporter.export(request, _bundle, _policy), isNull);
    });

    test(
      'fail-closed: refuses without explicit confirmation even if previewed',
      () {
        const request = DiagnosticExportRequest(
          userPreviewed: true,
          userConfirmed: false,
        );
        expect(exporter.export(request, _bundle, _policy), isNull);
      },
    );

    test('fail-closed: refuses when neither gate is present', () {
      const request = DiagnosticExportRequest(
        userPreviewed: false,
        userConfirmed: false,
      );
      expect(exporter.export(request, _bundle, _policy), isNull);
    });
  });
}
