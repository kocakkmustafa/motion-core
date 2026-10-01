/// The sole public production entry point for a v2l media catalog.
///
/// No application-supplied key, host, manifest hash, source index, or readiness
/// flag is accepted. The approved binary registry and independent reviewer
/// attestation verifier are deliberately absent for this preproduction cut.
final class ReleaseProductionGate {
  ReleaseProductionGate._();

  // A real entry requires reviewed source and a new application binary.
  static const Map<String, Never> _approvedProductionRoots = <String, Never>{};
  static const bool _reviewerAttestationVerifierReady = false;

  /// Returns a closed decision before reading assets while production roots,
  /// independent reviewer verification, or a binary-pinned source projection
  /// are unavailable. This must not fall back to structural test fixtures.
  static Future<ReleaseGateDecision> verifyBundled({
    required String appId,
    required Future<List<int>> Function(String assetPath) readAsset,
  }) async {
    if (appId.isEmpty) {
      return const ReleaseGateDecision._('APP_ID');
    }
    if (!_approvedProductionRoots.containsKey(appId)) {
      return const ReleaseGateDecision._('NO_APPROVED_PRODUCTION_ROOT');
    }
    if (!_reviewerAttestationVerifierReady) {
      return const ReleaseGateDecision._('REVIEW_ATTESTATIONS_NOT_IMPLEMENTED');
    }
    // This production path remains closed until a per-app source projection
    // and evidence-backed root are compiled into a reviewed application.
    return const ReleaseGateDecision._('SOURCE_PROJECTION_UNAVAILABLE');
  }
}

final class ReleaseGateDecision {
  const ReleaseGateDecision._(this.code);

  /// A false result keeps media unavailable while written lessons remain.
  bool get mediaAvailable => false;
  final String code;
}
