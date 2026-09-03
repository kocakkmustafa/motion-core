import 'content_error.dart';
import 'manifest.dart';
import 'validated_asset_reader.dart';

final class ContentCatalog {
  const ContentCatalog(this.manifest);

  final ContentManifest manifest;
}

sealed class ContentLoadResult {
  const ContentLoadResult();
}

final class ContentReady extends ContentLoadResult {
  const ContentReady({required this.catalog, required this.assets});

  final ContentCatalog catalog;
  final ValidatedContentAssetReader assets;
}

final class ContentDegraded extends ContentLoadResult {
  ContentDegraded({
    required this.catalog,
    required this.assets,
    required List<String> unavailableCapabilities,
  }) : unavailableCapabilities = List.unmodifiable(unavailableCapabilities);

  final ContentCatalog catalog;
  final ValidatedContentAssetReader assets;
  final List<String> unavailableCapabilities;
}

final class ContentBlocked extends ContentLoadResult {
  const ContentBlocked(this.error);

  final ContentError error;
}
