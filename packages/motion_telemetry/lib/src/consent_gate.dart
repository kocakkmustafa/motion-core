enum ConsentPurpose { productAnalytics }

/// Fail-closed: no recorded decision for a purpose means NO consent —
/// consent is never assumed granted by default or by the absence of a
/// choice.
abstract class ConsentGate {
  bool hasConsent(ConsentPurpose purpose);
}

class InMemoryConsentGate implements ConsentGate {
  final _granted = <ConsentPurpose>{};

  @override
  bool hasConsent(ConsentPurpose purpose) => _granted.contains(purpose);

  void grant(ConsentPurpose purpose) => _granted.add(purpose);

  void revoke(ConsentPurpose purpose) => _granted.remove(purpose);
}
