import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

const _canonicalDiagnosticFields = {
  'buildMode': DiagnosticFieldShape.buildMode,
  'code': DiagnosticFieldShape.code,
  'platform': DiagnosticFieldShape.platform,
  'version': DiagnosticFieldShape.version,
};
const _approved = DiagnosticExportPolicy(
  allowedCodes: {'network_timeout'},
  fields: _canonicalDiagnosticFields,
);
const _request = DiagnosticExportRequest(
  userPreviewed: true,
  userConfirmed: true,
);
final _bundle = SafeDiagnosticBundle(
  platform: DiagnosticPlatform.ios,
  buildMode: DiagnosticBuildMode.release,
  version: DiagnosticVersion(major: 1, minor: 2, patch: 3, build: 4),
  code: DiagnosticCodeCandidate('network_timeout'),
);

void main() {
  group('DiagnosticExporter typed policy gate', () {
    test('typed errors expose only their closed reason', () {
      expect(
        const DiagnosticExportException(
          DiagnosticExportRejectReason.disallowedPolicyValue,
        ).toString(),
        'DiagnosticExportException(disallowedPolicyValue)',
      );
    });

    test('exports deterministic canonical JSON after both user gates', () {
      final exporter = DiagnosticExporter();

      final first = exporter.export(_request, _bundle, _approved);
      final second = exporter.export(_request, _bundle, _approved);

      expect(first, second);
      expect(jsonDecode(first!), {
        'buildMode': 'release',
        'code': 'network_timeout',
        'platform': 'ios',
        'version': {'build': 4, 'major': 1, 'minor': 2, 'patch': 3},
      });
    });

    test('regex-valid but non-member diagnostic code is rejected', () {
      final bundle = SafeDiagnosticBundle(
        platform: DiagnosticPlatform.android,
        buildMode: DiagnosticBuildMode.profile,
        version: DiagnosticVersion(major: 1, minor: 0, patch: 0, build: 0),
        code: DiagnosticCodeCandidate('QUJDREVGRw'),
      );

      expect(
        () => DiagnosticExporter().export(_request, bundle, _approved),
        throwsA(
          isA<DiagnosticExportException>().having(
            (error) => error.reason,
            'reason',
            DiagnosticExportRejectReason.disallowedPolicyValue,
          ),
        ),
      );
    });

    test('unknown diagnostic policy key fails closed', () {
      const policy = DiagnosticExportPolicy(
        allowedCodes: {'network_timeout'},
        fields: {
          ..._canonicalDiagnosticFields,
          'other': DiagnosticFieldShape.code,
        },
      );

      expect(
        () => DiagnosticExporter().export(_request, _bundle, policy),
        throwsA(
          isA<DiagnosticExportException>().having(
            (error) => error.reason,
            'reason',
            DiagnosticExportRejectReason.disallowedPolicyValue,
          ),
        ),
      );
    });

    test('missing or mismatched diagnostic field shape fails closed', () {
      const missing = DiagnosticExportPolicy(
        allowedCodes: {'network_timeout'},
        fields: {
          'buildMode': DiagnosticFieldShape.buildMode,
          'code': DiagnosticFieldShape.code,
          'platform': DiagnosticFieldShape.platform,
        },
      );
      const mismatched = DiagnosticExportPolicy(
        allowedCodes: {'network_timeout'},
        fields: {
          'buildMode': DiagnosticFieldShape.buildMode,
          'code': DiagnosticFieldShape.code,
          'platform': DiagnosticFieldShape.code,
          'version': DiagnosticFieldShape.version,
        },
      );

      for (final policy in [missing, mismatched]) {
        expect(
          () => DiagnosticExporter().export(_request, _bundle, policy),
          throwsA(
            isA<DiagnosticExportException>().having(
              (error) => error.reason,
              'reason',
              DiagnosticExportRejectReason.disallowedPolicyValue,
            ),
          ),
        );
      }
    });

    test('seventeen diagnostic policy fields exceed the hard cap', () {
      final fields = <String, DiagnosticFieldShape>{
        ..._canonicalDiagnosticFields,
      };
      for (var index = 0; index < 13; index++) {
        fields['extra_$index'] = DiagnosticFieldShape.code;
      }
      final policy = DiagnosticExportPolicy(
        allowedCodes: const {'network_timeout'},
        fields: fields,
      );

      expect(DiagnosticExporter.hardMaxFields, 16);
      expect(
        () => DiagnosticExporter().export(_request, _bundle, policy),
        throwsA(
          isA<DiagnosticExportException>().having(
            (error) => error.reason,
            'reason',
            DiagnosticExportRejectReason.disallowedPolicyValue,
          ),
        ),
      );
    });

    test('missing preview or confirmation returns null before export', () {
      final exporter = DiagnosticExporter();
      expect(
        exporter.export(
          const DiagnosticExportRequest(
            userPreviewed: false,
            userConfirmed: true,
          ),
          _bundle,
          _approved,
        ),
        isNull,
      );
      expect(
        exporter.export(
          const DiagnosticExportRequest(
            userPreviewed: true,
            userConfirmed: false,
          ),
          _bundle,
          _approved,
        ),
        isNull,
      );
    });

    test('version bounds are enforced at construction before export gates', () {
      expect(
        () =>
            DiagnosticVersion(major: 0, minor: 999, patch: 999, build: 999999),
        returnsNormally,
      );
      expect(
        () => DiagnosticVersion(major: -1, minor: 0, patch: 0, build: 0),
        throwsArgumentError,
      );
      expect(
        () => DiagnosticVersion(major: 1000, minor: 0, patch: 0, build: 0),
        throwsArgumentError,
      );
      expect(
        () => DiagnosticVersion(major: 0, minor: 0, patch: 0, build: 1000000),
        throwsArgumentError,
      );
    });

    test(
      'bundle code shape is enforced at construction before export gates',
      () {
        for (final invalidCode in ['', 'free text', 'line\nbreak', 'a' * 41]) {
          expect(
            () => SafeDiagnosticBundle(
              platform: DiagnosticPlatform.ios,
              buildMode: DiagnosticBuildMode.release,
              version: DiagnosticVersion(
                major: 1,
                minor: 0,
                patch: 0,
                build: 0,
              ),
              code: DiagnosticCodeCandidate(invalidCode),
            ),
            throwsArgumentError,
          );
        }
      },
    );

    test('diagnostic enums remain closed to their canonical values', () {
      expect(DiagnosticPlatform.values.map((value) => value.name), [
        'ios',
        'android',
        'macos',
      ]);
      expect(DiagnosticBuildMode.values.map((value) => value.name), [
        'debug',
        'profile',
        'release',
      ]);
    });

    test('4 KiB is the hard diagnostic cap and cannot be raised', () {
      expect(DiagnosticExporter.hardMaxEncodedBytes, 4 * 1024);
      expect(DiagnosticExporter().maxEncodedBytes, 4 * 1024);
      expect(
        () => DiagnosticExporter(maxEncodedBytes: 4 * 1024),
        returnsNormally,
      );
      expect(
        () => DiagnosticExporter(maxEncodedBytes: 4 * 1024 + 1),
        throwsArgumentError,
      );
    });

    test('encoded byte limit fails without returning a string', () {
      expect(
        () => DiagnosticExporter(
          maxEncodedBytes: 1,
        ).export(_request, _bundle, _approved),
        throwsA(
          isA<DiagnosticExportException>().having(
            (error) => error.reason,
            'reason',
            DiagnosticExportRejectReason.encodedSizeExceeded,
          ),
        ),
      );
    });
  });
}
