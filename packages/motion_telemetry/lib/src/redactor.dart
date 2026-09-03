/// Defense-in-depth content gate. Two independent checks:
///
/// - [allowsKey] denies any attribute key that names a forbidden content
///   category (angle, landmark, audio, video, injury, song, choreography,
///   free text) by case-insensitive substring match.
/// - [allowsStringValue] is an ALLOW-shape check, not a denylist: a value
///   only passes if it looks like a short safe token. This catches free
///   text (and anything else denylist keywords miss) by construction,
///   because free text is not shaped like `network_timeout` or `v2.3.1`.
class Redactor {
  static const _forbiddenKeySubstrings = [
    'angle',
    'landmark',
    'audio',
    'video',
    'injury',
    'song',
    'choreography',
    'freetext',
    'free_text',
    'note',
    'comment',
    'pose',
    'sensor',
    'health',
    'score',
    'performance',
    'accuracy',
    'repetition',
    'velocity',
  ];

  static final _safeTokenPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,40}$');
  static final _durationBucketPattern = RegExp(
    r'^(?:[0-9]{1,6}-[0-9]{1,6}s|[0-9]{1,6}s\+)$',
  );
  static final _jwtPattern = RegExp(
    r'^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$',
  );
  static final _credentialMarkerPattern = RegExp(
    r'(bearer|token|secret|api[_-]?key|github_pat_|gh[pousr]_|sk-(?:proj-)?)',
    caseSensitive: false,
  );
  static final _awsAccessKeyPattern = RegExp(r'^AKIA[0-9A-Z]{16}$');
  static final _firebaseApiKeyPattern = RegExp(r'^AIza[0-9A-Za-z_-]{35}$');

  bool allowsKey(String key) {
    final lower = key.toLowerCase();
    return !_forbiddenKeySubstrings.any(lower.contains);
  }

  bool allowsStringValue(String value) {
    if (!_safeTokenPattern.hasMatch(value)) return false;
    if (_credentialMarkerPattern.hasMatch(value) ||
        _jwtPattern.hasMatch(value) ||
        _awsAccessKeyPattern.hasMatch(value) ||
        _firebaseApiKeyPattern.hasMatch(value)) {
      return false;
    }
    return true;
  }

  bool allowsDurationBucket(String value) =>
      _durationBucketPattern.hasMatch(value);
}
