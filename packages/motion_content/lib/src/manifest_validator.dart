import 'canonical_json.dart';
import 'content_error.dart';
import 'manifest.dart';
import 'path_policy.dart';
import 'semantic_version.dart';

final class ManifestValidationReport {
  ManifestValidationReport({
    this.error,
    List<String> degradedCapabilities = const [],
  }) : degradedCapabilities = List.unmodifiable(degradedCapabilities);

  final ContentError? error;
  final List<String> degradedCapabilities;

  bool get isBlocked => error != null;
  bool get isDegraded => error == null && degradedCapabilities.isNotEmpty;
}

final class ManifestValidator {
  ManifestValidator({
    required this.expectedAppId,
    required this.currentCoreContract,
    Set<String> availableCapabilities = const {},
  }) : availableCapabilities = Set.unmodifiable(availableCapabilities);

  final String expectedAppId;
  final SemanticVersion currentCoreContract;
  final Set<String> availableCapabilities;

  ManifestValidationReport validate(ContentManifest manifest) {
    final digest = computeCatalogDigest(manifest.toJson());
    if (digest != manifest.catalogDigest) {
      return ManifestValidationReport(
        error: ContentError(
          code: ContentErrorCode.catalogDigestMismatch,
          expectedHashPrefix: _prefix(manifest.catalogDigest),
          actualHashPrefix: _prefix(digest),
        ),
      );
    }
    if (manifest.appId != expectedAppId) {
      return ManifestValidationReport(
        error: const ContentError(code: ContentErrorCode.appIdentity),
      );
    }
    if (manifest.minimumCoreContract.compareTo(currentCoreContract) > 0) {
      return ManifestValidationReport(
        error: const ContentError(code: ContentErrorCode.compatibility),
      );
    }

    final ids = <String>{};
    for (final id in <Iterable<String>>[
      manifest.courses.map((value) => value.id),
      manifest.lessons.map((value) => value.id),
      manifest.models.map((value) => value.id),
      manifest.assets.map((value) => value.id),
    ].expand((values) => values)) {
      if (!ids.add(id)) {
        return ManifestValidationReport(
          error: ContentError(
            code: ContentErrorCode.duplicateId,
            contentId: id,
          ),
        );
      }
    }
    final assetPaths = <String>{};
    for (final asset in manifest.assets) {
      if (!assetPaths.add(asset.path)) {
        return ManifestValidationReport(
          error: ContentError(
            code: ContentErrorCode.duplicateId,
            contentId: asset.id,
          ),
        );
      }
    }

    for (final asset in manifest.assets) {
      final error = _pathError(asset.path, asset.id);
      if (error != null) return ManifestValidationReport(error: error);
    }
    for (final model in manifest.models) {
      final error = _pathError(model.path, model.id);
      if (error != null) return ManifestValidationReport(error: error);
    }

    final lessonIds = manifest.lessons.map((value) => value.id).toSet();
    for (final course in manifest.courses) {
      for (final lessonId in course.lessonIds) {
        if (!lessonIds.contains(lessonId)) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.orphanReference,
              contentId: course.id,
            ),
          );
        }
      }
    }
    final modelIds = manifest.models.map((value) => value.id).toSet();
    final assetIds = manifest.assets.map((value) => value.id).toSet();
    for (final lesson in manifest.lessons) {
      for (final modelId in lesson.modelIds) {
        if (!modelIds.contains(modelId)) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.orphanReference,
              contentId: lesson.id,
            ),
          );
        }
      }
      for (final assetId in lesson.assetIds) {
        if (!assetIds.contains(assetId)) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.orphanReference,
              contentId: lesson.id,
            ),
          );
        }
      }
    }

    final assetsByPath = <String, ContentAsset>{
      for (final asset in manifest.assets) asset.path: asset,
    };
    for (final model in manifest.models) {
      final asset = assetsByPath[model.path];
      if (asset == null) {
        return ManifestValidationReport(
          error: ContentError(
            code: ContentErrorCode.orphanReference,
            contentId: model.id,
          ),
        );
      }
      if (asset.byteLength != model.byteLength) {
        return ManifestValidationReport(
          error: ContentError(
            code: ContentErrorCode.sizeMismatch,
            contentId: model.id,
          ),
        );
      }
      if (asset.sha256 != model.sha256) {
        return ManifestValidationReport(
          error: ContentError(
            code: ContentErrorCode.hashMismatch,
            contentId: model.id,
            expectedHashPrefix: _prefix(asset.sha256),
            actualHashPrefix: _prefix(model.sha256),
          ),
        );
      }
    }

    final degraded = <String>{};
    for (final model in manifest.models) {
      final seenCapabilities = <String>{};
      for (final capability in model.capabilities) {
        if (!seenCapabilities.add(capability.id)) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.duplicateId,
              contentId: capability.id,
            ),
          );
        }
        if (availableCapabilities.contains(capability.id)) continue;
        if (capability.required) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.capability,
              contentId: capability.id,
            ),
          );
        }
        final fallback = capability.fallback;
        if (fallback == null || !availableCapabilities.contains(fallback)) {
          return ManifestValidationReport(
            error: ContentError(
              code: ContentErrorCode.capability,
              contentId: capability.id,
            ),
          );
        }
        degraded.add(capability.id);
      }
    }
    return ManifestValidationReport(
      degradedCapabilities: degraded.toList(growable: false),
    );
  }

  ContentError? _pathError(String path, String contentId) {
    try {
      PathPolicy.validate(path);
      return null;
    } on ContentException {
      return ContentError(
        code: ContentErrorCode.unsafePath,
        contentId: contentId,
      );
    }
  }
}

String _prefix(String digest) =>
    digest.substring(0, digest.length < 12 ? digest.length : 12);
