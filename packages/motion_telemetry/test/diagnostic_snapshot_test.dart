import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

class _ChangingCode extends DiagnosticCodeCandidate {
  _ChangingCode() : super('network_timeout');
  int reads = 0;
  @override
  String get value => reads++ == 0 ? 'network_timeout' : 'unapproved-marker';
}

class _MutableVersion extends DiagnosticVersion {
  _MutableVersion() : super(major: 1, minor: 0, patch: 0, build: 1);
  int currentMajor = 1;
  @override
  int get major => currentMajor;
}

const _request = DiagnosticExportRequest(
  userPreviewed: true,
  userConfirmed: true,
);
const _policy = DiagnosticExportPolicy(
  allowedCodes: {'network_timeout'},
  fields: {
    'buildMode': DiagnosticFieldShape.buildMode,
    'code': DiagnosticFieldShape.code,
    'platform': DiagnosticFieldShape.platform,
    'version': DiagnosticFieldShape.version,
  },
);
void main() {
  test('diagnostic code is snapshotted before membership validation', () {
    final code = _ChangingCode();
    final bundle = SafeDiagnosticBundle(
      platform: DiagnosticPlatform.ios,
      buildMode: DiagnosticBuildMode.release,
      version: DiagnosticVersion(major: 1, minor: 0, patch: 0, build: 1),
      code: code,
    );
    code.reads = 0;
    final result = DiagnosticExporter().export(_request, bundle, _policy)!;
    expect((jsonDecode(result) as Map)['code'], 'network_timeout');
    expect(code.reads, 1);
  });

  test('version is revalidated at the export boundary', () {
    final version = _MutableVersion();
    final bundle = SafeDiagnosticBundle(
      platform: DiagnosticPlatform.android,
      buildMode: DiagnosticBuildMode.release,
      version: version,
      code: const DiagnosticCodeCandidate('network_timeout'),
    );
    version.currentMajor = 1000;
    expect(
      () => DiagnosticExporter().export(_request, bundle, _policy),
      throwsA(
        isA<DiagnosticExportException>().having(
          (e) => e.reason,
          'reason',
          DiagnosticExportRejectReason.invalidVersion,
        ),
      ),
    );
  });
}
