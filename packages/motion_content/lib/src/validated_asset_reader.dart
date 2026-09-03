import 'dart:typed_data';

import 'asset_reader.dart';
import 'canonical_json.dart';
import 'content_error.dart';
import 'manifest.dart';

/// The only reader consumers should retain after startup validation.
///
/// It keeps allowlist metadata only. Every read goes back to the bundled
/// source and repeats timeout, byte-length, and digest validation.
abstract interface class ValidatedContentAssetReader
    implements ContentAssetReader {
  Iterable<String> get allowedLogicalPaths;
}

void verifyAssetBytes(ContentAsset asset, Uint8List bytes) {
  if (bytes.length > maximumSingleAssetBytes) {
    throw ContentException(
      ContentError(code: ContentErrorCode.resourceLimit, contentId: asset.id),
    );
  }
  if (bytes.length != asset.byteLength) {
    throw ContentException(
      ContentError(code: ContentErrorCode.sizeMismatch, contentId: asset.id),
    );
  }
  final actual = computeSha256Hex(bytes);
  if (actual != asset.sha256) {
    throw ContentException(
      ContentError(
        code: ContentErrorCode.hashMismatch,
        contentId: asset.id,
        expectedHashPrefix: _prefix(asset.sha256),
        actualHashPrefix: _prefix(actual),
      ),
    );
  }
}

String _prefix(String digest) =>
    digest.substring(0, digest.length < 12 ? digest.length : 12);
