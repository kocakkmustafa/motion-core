/// Additive provider contract v1. No model loading, downloading or training.
///
/// A manifest is a declaration, not proof of accuracy. The app supplies the
/// separately reviewed acceptance hash and verifies actual artifact bytes.
library;

enum MotionProviderMode { production, replay }

enum MotionCapabilityState { unsupported, calibrationRequired, validated }

enum MotionReadiness {
  ready,
  unsupported,
  calibrationRequired,
  incompatible,
  artifactMismatch,
  acceptanceRequired,
  replayOnly,
}

final class MotionCapability {
  const MotionCapability({
    required this.state,
    this.calibrationSha256,
    this.acceptanceSha256,
  });

  final MotionCapabilityState state;
  final String? calibrationSha256;
  final String? acceptanceSha256;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'calibrationSha256': calibrationSha256,
    'acceptanceSha256': acceptanceSha256,
  };
}

/// Exact input/model/runtime binding. Domain-specific task and phase rules
/// stay in the consumer. No unknown enum/version falls back to a known value.
final class MotionProviderManifest {
  MotionProviderManifest({
    required this.providerId,
    required this.providerVersion,
    required this.mode,
    required this.runtimeAbi,
    required this.inputSchema,
    required this.coordinateSpace,
    required this.modelSha256,
    required Map<String, MotionCapability> capabilities,
  }) : capabilities = Map.unmodifiable(capabilities) {
    for (final value in [
      providerId,
      runtimeAbi,
      inputSchema,
      coordinateSpace,
    ]) {
      if (value.trim().isEmpty) throw const FormatException('empty identity');
    }
    if (!_version.hasMatch(providerVersion)) {
      throw const FormatException('invalid provider version');
    }
    if (modelSha256 != null && !_sha.hasMatch(modelSha256!)) {
      throw const FormatException('invalid model hash');
    }
    for (final entry in this.capabilities.entries) {
      if (entry.key.trim().isEmpty) {
        throw const FormatException('empty capability');
      }
      final capability = entry.value;
      for (final hash in [
        capability.calibrationSha256,
        capability.acceptanceSha256,
      ]) {
        if (hash != null && !_sha.hasMatch(hash)) {
          throw const FormatException('invalid capability hash');
        }
      }
      if (capability.state == MotionCapabilityState.validated &&
          (modelSha256 == null ||
              capability.calibrationSha256 == null ||
              capability.acceptanceSha256 == null)) {
        throw const FormatException('validated capability lacks provenance');
      }
    }
  }

  static const int schemaVersion = 1;
  static const String contractVersion = '1.0.0';
  static final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _version = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );

  final String providerId;
  final String providerVersion;
  final MotionProviderMode mode;
  final String runtimeAbi;
  final String inputSchema;
  final String coordinateSpace;
  final String? modelSha256;
  final Map<String, MotionCapability> capabilities;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'contractVersion': contractVersion,
    'providerId': providerId,
    'providerVersion': providerVersion,
    'mode': mode.name,
    'runtimeAbi': runtimeAbi,
    'inputSchema': inputSchema,
    'coordinateSpace': coordinateSpace,
    'modelSha256': modelSha256,
    'capabilities': capabilities.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory MotionProviderManifest.fromJson(Map<String, Object?> json) {
    try {
      if (json['schemaVersion'] != schemaVersion ||
          json['contractVersion'] != contractVersion) {
        throw const FormatException('unsupported provider contract');
      }
      final rawCapabilities = json['capabilities'] as Map;
      final capabilities = <String, MotionCapability>{};
      for (final entry in rawCapabilities.entries) {
        final raw = entry.value as Map;
        capabilities[entry.key as String] = MotionCapability(
          state: MotionCapabilityState.values.byName(raw['state'] as String),
          calibrationSha256: raw['calibrationSha256'] as String?,
          acceptanceSha256: raw['acceptanceSha256'] as String?,
        );
      }
      return MotionProviderManifest(
        providerId: json['providerId'] as String,
        providerVersion: json['providerVersion'] as String,
        mode: MotionProviderMode.values.byName(json['mode'] as String),
        runtimeAbi: json['runtimeAbi'] as String,
        inputSchema: json['inputSchema'] as String,
        coordinateSpace: json['coordinateSpace'] as String,
        modelSha256: json['modelSha256'] as String?,
        capabilities: capabilities,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('malformed provider manifest');
    }
  }
}

/// Caller-owned verification receipt. Hashes must be calculated from loaded
/// bytes, never copied from the candidate's declarations. This contract does
/// not establish trust roots or certify the reviewed acceptance itself.
final class MotionProviderRequirement {
  const MotionProviderRequirement({
    required this.capability,
    required this.runtimeAbi,
    required this.inputSchema,
    required this.coordinateSpace,
    required this.actualModelSha256,
    required this.actualCalibrationSha256,
    required this.reviewedAcceptanceSha256,
    this.mode = MotionProviderMode.production,
  });

  final String capability;
  final String runtimeAbi;
  final String inputSchema;
  final String coordinateSpace;
  final MotionProviderMode mode;
  final String? actualModelSha256;
  final String? actualCalibrationSha256;
  final String? reviewedAcceptanceSha256;

  MotionReadiness inspect(MotionProviderManifest manifest) {
    if (manifest.mode != mode) return MotionReadiness.replayOnly;
    if (manifest.runtimeAbi != runtimeAbi ||
        manifest.inputSchema != inputSchema ||
        manifest.coordinateSpace != coordinateSpace) {
      return MotionReadiness.incompatible;
    }
    final capability = manifest.capabilities[this.capability];
    if (capability == null ||
        capability.state == MotionCapabilityState.unsupported) {
      return MotionReadiness.unsupported;
    }
    if (capability.state == MotionCapabilityState.calibrationRequired) {
      return MotionReadiness.calibrationRequired;
    }
    if (manifest.modelSha256 != actualModelSha256 ||
        capability.calibrationSha256 != actualCalibrationSha256) {
      return MotionReadiness.artifactMismatch;
    }
    if (capability.acceptanceSha256 != reviewedAcceptanceSha256) {
      return MotionReadiness.acceptanceRequired;
    }
    return MotionReadiness.ready;
  }
}

/// In-memory selection only; install is atomic after compatibility checks.
/// No implicit fallback, retry, downgrade or persistence of a broken candidate.
/// The caller creates fresh sessions whenever the active identity changes.
final class MotionProviderSelection {
  MotionProviderManifest? _active;
  MotionProviderManifest? _previous;

  MotionProviderManifest? get active => _active;
  MotionProviderManifest? get previous => _previous;

  MotionReadiness select(
    MotionProviderManifest candidate,
    MotionProviderRequirement requirement,
  ) {
    final result = requirement.inspect(candidate);
    if (result == MotionReadiness.ready && !identical(candidate, _active)) {
      _previous = _active;
      _active = candidate;
    }
    return result;
  }

  /// Explicit rollback, rechecked against current bytes and app acceptance.
  MotionReadiness rollback(MotionProviderRequirement requirement) {
    final candidate = _previous;
    if (candidate == null) return MotionReadiness.unsupported;
    return select(candidate, requirement);
  }

  void clear() {
    _active = null;
    _previous = null;
  }
}
