import 'dart:convert';

class DiagnosticExportRequest {
  const DiagnosticExportRequest({
    required this.userPreviewed,
    required this.userConfirmed,
  });

  final bool userPreviewed;
  final bool userConfirmed;
}

enum DiagnosticPlatform { ios, android, macos }

enum DiagnosticBuildMode { debug, profile, release }

class DiagnosticVersion {
  DiagnosticVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  }) {
    _requireBounded('major', major, 999);
    _requireBounded('minor', minor, 999);
    _requireBounded('patch', patch, 999);
    _requireBounded('build', build, 999999);
  }

  final int major;
  final int minor;
  final int patch;
  final int build;

  static void _requireBounded(String name, int value, int maximum) {
    if (value < 0 || value > maximum) {
      throw ArgumentError.value(value, name, 'must be between 0 and $maximum');
    }
  }
}

class DiagnosticCodeCandidate {
  /// A shaped candidate only; [DiagnosticExportPolicy] authorizes exact codes.
  const DiagnosticCodeCandidate(this.value);

  final String value;
}

class SafeDiagnosticBundle {
  SafeDiagnosticBundle({
    required this.platform,
    required this.buildMode,
    required this.version,
    required this.code,
  }) {
    if (!_safeCodePattern.hasMatch(code.value)) {
      throw ArgumentError('code must be a safe code token');
    }
  }

  final DiagnosticPlatform platform;
  final DiagnosticBuildMode buildMode;
  final DiagnosticVersion version;
  final DiagnosticCodeCandidate code;

  static final _safeCodePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$');
}

enum DiagnosticFieldShape { buildMode, code, platform, version }

class DiagnosticExportPolicy {
  const DiagnosticExportPolicy({
    required this.allowedCodes,
    required this.fields,
  });

  final Set<String> allowedCodes;
  final Map<String, DiagnosticFieldShape> fields;
}

enum DiagnosticExportRejectReason {
  disallowedPolicyValue,
  invalidVersion,
  encodedSizeExceeded,
}

class DiagnosticExportException implements Exception {
  const DiagnosticExportException(this.reason);

  final DiagnosticExportRejectReason reason;

  @override
  String toString() => 'DiagnosticExportException(${reason.name})';
}

/// Diagnostic bundles leave the device only after explicit user action and
/// exact policy validation. The API has no arbitrary-string payload path.
class DiagnosticExporter {
  static const hardMaxEncodedBytes = 4 * 1024;
  static const hardMaxFields = 16;

  /// Configuration limit for exact diagnostic-code policy enumeration.
  static const hardMaxPolicyCodes = 64;
  static const _canonicalFieldShapes = <String, DiagnosticFieldShape>{
    'buildMode': DiagnosticFieldShape.buildMode,
    'code': DiagnosticFieldShape.code,
    'platform': DiagnosticFieldShape.platform,
    'version': DiagnosticFieldShape.version,
  };

  DiagnosticExporter({int maxEncodedBytes = hardMaxEncodedBytes})
    : _maxEncodedBytes = maxEncodedBytes {
    if (maxEncodedBytes < 0 || maxEncodedBytes > hardMaxEncodedBytes) {
      throw ArgumentError.value(
        maxEncodedBytes,
        'maxEncodedBytes',
        'must be between 0 and $hardMaxEncodedBytes',
      );
    }
  }

  final int _maxEncodedBytes;
  int get maxEncodedBytes => _maxEncodedBytes;

  String? export(
    DiagnosticExportRequest request,
    SafeDiagnosticBundle bundle,
    DiagnosticExportPolicy policy,
  ) {
    if (!request.userPreviewed || !request.userConfirmed) return null;
    // Validation and serialization must use the same primitive snapshots,
    // even if callers provide subclasses with stateful getters.
    final code = bundle.code.value;
    final platform = bundle.platform;
    final buildMode = bundle.buildMode;
    final version = bundle.version;
    final major = version.major;
    final minor = version.minor;
    final patch = version.patch;
    final build = version.build;
    if ([major, minor, patch].any((part) => part < 0 || part > 999) ||
        build < 0 ||
        build > 999999) {
      throw const DiagnosticExportException(
        DiagnosticExportRejectReason.invalidVersion,
      );
    }
    if (!SafeDiagnosticBundle._safeCodePattern.hasMatch(code) ||
        !_allowsPolicy(policy, code)) {
      throw const DiagnosticExportException(
        DiagnosticExportRejectReason.disallowedPolicyValue,
      );
    }

    final encoded = jsonEncode({
      'buildMode': buildMode.name,
      'code': code,
      'platform': platform.name,
      'version': {
        'build': build,
        'major': major,
        'minor': minor,
        'patch': patch,
      },
    });
    if (utf8.encode(encoded).length > _maxEncodedBytes) {
      throw const DiagnosticExportException(
        DiagnosticExportRejectReason.encodedSizeExceeded,
      );
    }
    return encoded;
  }

  bool _allowsPolicy(DiagnosticExportPolicy policy, String code) {
    try {
      // Shape checks visit only the four fixed keys after checking length.
      // Copying the input first defeats the memory cap on arbitrary maps.
      return _allowsCanonicalFields(policy.fields) &&
          _allowsEnumeratedCode(policy.allowedCodes, code);
    } catch (_) {
      return false;
    }
  }

  bool _allowsEnumeratedCode(Set<String> codes, String code) {
    final declaredCount = codes.length;
    if (declaredCount < 0 || declaredCount > hardMaxPolicyCodes) return false;
    var visited = 0;
    var found = false;
    // Caller-owned contains() can claim membership absent from the policy.
    // Count iteration independently, including when length is dishonest.
    for (final approved in codes) {
      if (++visited > hardMaxPolicyCodes) return false;
      if (approved == code) found = true;
    }
    return visited == declaredCount && found;
  }

  bool _allowsCanonicalFields(Map<String, DiagnosticFieldShape> fields) {
    if (fields.length > hardMaxFields ||
        fields.length != _canonicalFieldShapes.length) {
      return false;
    }
    for (final canonical in _canonicalFieldShapes.entries) {
      if (fields[canonical.key] != canonical.value) return false;
    }
    return true;
  }
}
