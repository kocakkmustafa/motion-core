import 'content_error.dart';

abstract final class PathPolicy {
  static final _segment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');

  static void validate(String logicalPath) {
    if (logicalPath.isEmpty ||
        logicalPath.startsWith('/') ||
        logicalPath.endsWith('/') ||
        logicalPath.contains('\\') ||
        logicalPath.contains('\u0000') ||
        logicalPath.trim() != logicalPath ||
        _scheme.hasMatch(logicalPath)) {
      failContent(ContentErrorCode.unsafePath);
    }
    final segments = logicalPath.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          !_segment.hasMatch(segment),
    )) {
      failContent(ContentErrorCode.unsafePath);
    }
  }
}
