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
  ];

  static final _safeTokenPattern = RegExp(r'^[A-Za-z0-9_.\-]{1,40}$');

  bool allowsKey(String key) {
    final lower = key.toLowerCase();
    return !_forbiddenKeySubstrings.any(lower.contains);
  }

  bool allowsStringValue(String value) => _safeTokenPattern.hasMatch(value);
}
