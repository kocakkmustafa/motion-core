/// Outcome of a secure-key lookup. Deliberately not a nullable return: a
/// bare `List<int>?` return would let a caller treat "failed" and "empty
/// key" the same way. A sealed result type makes the two states impossible
/// to confuse.
sealed class SecureKeyResult {
  const SecureKeyResult();
}

class SecureKeySuccess extends SecureKeyResult {
  const SecureKeySuccess(this.keyBytes);

  final List<int> keyBytes;
}

class SecureKeyFailure extends SecureKeyResult {
  const SecureKeyFailure(this.reason);

  final String reason;
}

/// Abstracts platform Keychain/Keystore access. Fail-closed by contract:
/// an implementation MUST return [SecureKeyFailure] on any error rather
/// than a fallback/default key — a predictable fallback key would silently
/// downgrade encrypted local storage to effectively unencrypted.
abstract class SecureKeyAdapter {
  Future<SecureKeyResult> getOrCreateKey(String alias);
}
