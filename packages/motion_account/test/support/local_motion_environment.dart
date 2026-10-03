/// Dedicated disposable local stack only; reject external targets before I/O.
class LocalMotionEnvironment {
  const LocalMotionEnvironment(this.apiUrl, this.anonKey, this.mailpitUrl);

  final String apiUrl;
  final String anonKey;
  final String mailpitUrl;

  static LocalMotionEnvironment? from(Map<String, String> environment) {
    const names = [
      'MOTION_LOCAL_API_URL',
      'MOTION_LOCAL_ANON_KEY',
      'MOTION_LOCAL_MAILPIT_URL',
    ];
    if (names.every((name) => !environment.containsKey(name))) return null;
    if (names.any((name) => environment[name]?.trim().isNotEmpty != true)) {
      throw ArgumentError('All three local Motion variables are required');
    }
    final api = environment[names[0]]!;
    final mailpit = environment[names[2]]!;
    _validateUrl(api, 55321);
    _validateUrl(mailpit, 55324);
    return LocalMotionEnvironment(api, environment[names[1]]!, mailpit);
  }

  static void _validateUrl(String raw, int port) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'http' ||
        (uri.host != '127.0.0.1' && uri.host != 'localhost') ||
        uri.port != port ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (raw != 'http://127.0.0.1:$port' && raw != 'http://localhost:$port')) {
      throw ArgumentError('Requires an exact dedicated loopback URL');
    }
  }
}
