enum ContentErrorCode {
  parse,
  duplicateJsonKey,
  resourceLimit,
  schema,
  appIdentity,
  compatibility,
  duplicateId,
  orphanReference,
  unsafePath,
  missingAsset,
  sizeMismatch,
  hashMismatch,
  catalogDigestMismatch,
  timeout,
  locale,
  capability,
  io,
}

/// A deliberately small diagnostic value. It never retains an exception,
/// stack trace, physical path, source payload, or credential-bearing string.
class ContentError {
  const ContentError({
    required this.code,
    this.contentId,
    this.expectedHashPrefix,
    this.actualHashPrefix,
  });

  final ContentErrorCode code;
  final String? contentId;
  final String? expectedHashPrefix;
  final String? actualHashPrefix;

  @override
  String toString() {
    final fields = <String>['code=${code.name}'];
    if (contentId != null) fields.add('contentId=$contentId');
    if (expectedHashPrefix != null) {
      fields.add('expectedHashPrefix=$expectedHashPrefix');
    }
    if (actualHashPrefix != null) {
      fields.add('actualHashPrefix=$actualHashPrefix');
    }
    return 'ContentError(${fields.join(', ')})';
  }
}

class ContentException implements Exception {
  const ContentException(this.error);

  final ContentError error;

  @override
  String toString() => error.toString();
}

Never failContent(ContentErrorCode code, {String? contentId}) {
  throw ContentException(ContentError(code: code, contentId: contentId));
}
