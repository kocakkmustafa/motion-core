import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'asset_reader.dart';
import 'content_catalog.dart';
import 'content_error.dart';
import 'manifest.dart';
import 'manifest_validator.dart';
import 'path_policy.dart';
import 'semantic_version.dart';
import 'strict_json.dart';
import 'validated_asset_reader.dart';

final class ContentBundleLoader {
  ContentBundleLoader({
    required ContentAssetReader reader,
    required this.expectedAppId,
    required this.currentCoreContract,
    Set<String> availableCapabilities = const {},
    ContentLoadPolicy? policy,
    this.manifestPath = 'assets/motion_content/manifest.json',
  }) : _reader = reader,
       availableCapabilities = Set.unmodifiable(availableCapabilities),
       policy = policy ?? const ContentLoadPolicy() {
    PathPolicy.validate(manifestPath);
  }

  final ContentAssetReader _reader;
  final String expectedAppId;
  final SemanticVersion currentCoreContract;
  final Set<String> availableCapabilities;
  final ContentLoadPolicy policy;
  final String manifestPath;

  Future<ContentLoadResult>? _inFlight;

  Future<ContentLoadResult> load() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final attempt = _loadAndClear();
    _inFlight = attempt;
    return attempt;
  }

  Future<ContentLoadResult> _loadAndClear() async {
    try {
      return await _loadAttempt();
    } finally {
      _inFlight = null;
    }
  }

  Future<ContentLoadResult> _loadAttempt() async {
    late final Uint8List manifestBytes;
    try {
      final rawManifestBytes = await runBounded(
        () => _reader.read(manifestPath),
        policy,
      );
      if (rawManifestBytes.length > const StrictJsonLimits().maxBytes) {
        return const ContentBlocked(
          ContentError(code: ContentErrorCode.resourceLimit),
        );
      }
      manifestBytes = Uint8List.fromList(rawManifestBytes);
    } on TimeoutException {
      return const ContentBlocked(ContentError(code: ContentErrorCode.timeout));
    } on ContentException catch (error) {
      return ContentBlocked(ContentError(code: error.error.code));
    } catch (_) {
      return const ContentBlocked(
        ContentError(code: ContentErrorCode.missingAsset),
      );
    }

    late final ContentManifest manifest;
    try {
      manifest = ContentManifestParser().parse(manifestBytes);
    } on ContentException catch (error) {
      return ContentBlocked(error.error);
    }

    final report = ManifestValidator(
      expectedAppId: expectedAppId,
      currentCoreContract: currentCoreContract,
      availableCapabilities: availableCapabilities,
    ).validate(manifest);
    if (report.error case final error?) return ContentBlocked(error);

    for (final asset in manifest.assets) {
      late final Uint8List rawBytes;
      try {
        rawBytes = await runBounded(() => _reader.read(asset.path), policy);
      } on TimeoutException {
        return ContentBlocked(
          ContentError(code: ContentErrorCode.timeout, contentId: asset.id),
        );
      } on ContentException catch (error) {
        return ContentBlocked(
          ContentError(code: error.error.code, contentId: asset.id),
        );
      } catch (_) {
        return ContentBlocked(
          ContentError(
            code: ContentErrorCode.missingAsset,
            contentId: asset.id,
          ),
        );
      }
      try {
        verifyAssetBytes(asset, rawBytes);
      } on ContentException catch (error) {
        return ContentBlocked(error.error);
      }
    }

    final catalog = ContentCatalog(manifest);
    final validatedReader = _ValidatedContentAssetReader(
      reader: _reader,
      assets: manifest.assets,
      policy: policy,
    );
    if (report.degradedCapabilities.isNotEmpty) {
      return ContentDegraded(
        catalog: catalog,
        assets: validatedReader,
        unavailableCapabilities: report.degradedCapabilities,
      );
    }
    return ContentReady(catalog: catalog, assets: validatedReader);
  }
}

final class _ValidatedContentAssetReader
    implements ValidatedContentAssetReader {
  _ValidatedContentAssetReader({
    required ContentAssetReader reader,
    required Iterable<ContentAsset> assets,
    required ContentLoadPolicy policy,
  }) : _reader = reader,
       _assetsByPath = UnmodifiableMapView(<String, ContentAsset>{
         for (final asset in assets) asset.path: asset,
       }),
       _policy = policy;

  final ContentAssetReader _reader;
  final Map<String, ContentAsset> _assetsByPath;
  final ContentLoadPolicy _policy;

  @override
  Iterable<String> get allowedLogicalPaths => _assetsByPath.keys;

  @override
  Future<Uint8List> read(String logicalPath) async {
    try {
      PathPolicy.validate(logicalPath);
    } on ContentException {
      throw const ContentException(
        ContentError(code: ContentErrorCode.unsafePath),
      );
    }
    final asset = _assetsByPath[logicalPath];
    if (asset == null) {
      throw const ContentException(
        ContentError(code: ContentErrorCode.missingAsset),
      );
    }
    late final Uint8List bytes;
    try {
      bytes = await runBounded(() => _reader.read(logicalPath), _policy);
    } on TimeoutException {
      throw ContentException(
        ContentError(code: ContentErrorCode.timeout, contentId: asset.id),
      );
    } on ContentException catch (error) {
      throw ContentException(
        ContentError(code: error.error.code, contentId: asset.id),
      );
    } catch (_) {
      throw ContentException(
        ContentError(code: ContentErrorCode.missingAsset, contentId: asset.id),
      );
    }
    verifyAssetBytes(asset, bytes);
    return Uint8List.fromList(bytes);
  }
}
