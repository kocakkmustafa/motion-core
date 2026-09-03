import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'canonical_json.dart';
import 'content_error.dart';
import 'manifest.dart';
import 'manifest_validator.dart';
import 'path_policy.dart';
import 'secure_asset_file.dart';
import 'semantic_version.dart';
import 'validated_asset_reader.dart';

final class ManifestBuilder {
  Future<Uint8List> build({
    required Uint8List sourceBytes,
    required Directory root,
  }) async {
    final source = decodeStrictJsonObject(sourceBytes);
    if (source.containsKey('catalogDigest')) {
      failContent(ContentErrorCode.schema);
    }
    final rawAssets = _objectList(source['assets'], maximumAssetCount);
    final assetsByPath = <String, Map<String, Object?>>{};
    final assetIds = <String>{};
    for (final rawAsset in rawAssets) {
      if (!_hasExactKeys(rawAsset, const {'id', 'path'})) {
        failContent(ContentErrorCode.schema);
      }
      final id = _safeIdentifier(rawAsset['id']);
      final logicalPath = _safeString(rawAsset['path']);
      PathPolicy.validate(logicalPath);
      if (!assetIds.add(id) || assetsByPath.containsKey(logicalPath)) {
        failContent(ContentErrorCode.duplicateId, contentId: id);
      }
      assetsByPath[logicalPath] = rawAsset;
    }

    final preflightLengths = <String, int>{};
    var declaredBytes = 0;
    for (final entry in assetsByPath.entries) {
      final id = entry.value['id']! as String;
      final length = await _physicalAssetLength(root, entry.key, id);
      declaredBytes += length;
      if (declaredBytes > maximumDeclaredAssetBytes) {
        failContent(ContentErrorCode.resourceLimit, contentId: id);
      }
      preflightLengths[entry.key] = length;
    }

    var readBytes = 0;
    for (final entry in assetsByPath.entries) {
      final rawAsset = entry.value;
      final id = rawAsset['id']! as String;
      final bytes = await _readPhysicalAsset(root, entry.key, id);
      if (bytes.length != preflightLengths[entry.key]) {
        failContent(ContentErrorCode.sizeMismatch, contentId: id);
      }
      readBytes += bytes.length;
      if (readBytes > maximumDeclaredAssetBytes) {
        failContent(ContentErrorCode.resourceLimit, contentId: id);
      }
      rawAsset
        ..['byteLength'] = bytes.length
        ..['sha256'] = computeSha256Hex(bytes);
    }

    final rawModels = _objectList(source['models'], maximumModelCount);
    for (final rawModel in rawModels) {
      if (rawModel.containsKey('byteLength') ||
          rawModel.containsKey('sha256')) {
        failContent(ContentErrorCode.schema);
      }
      final id = _safeIdentifier(rawModel['id']);
      final logicalPath = _safeString(rawModel['path']);
      PathPolicy.validate(logicalPath);
      final asset = assetsByPath[logicalPath];
      if (asset == null) {
        failContent(ContentErrorCode.orphanReference, contentId: id);
      }
      rawModel
        ..['byteLength'] = asset['byteLength']
        ..['sha256'] = asset['sha256'];
    }

    source['catalogDigest'] = computeCatalogDigest(source);
    final manifest = ContentManifestParser().parse(_canonicalBytes(source));
    final allCapabilities = <String>{
      for (final model in manifest.models)
        for (final capability in model.capabilities) capability.id,
    };
    final report = ManifestValidator(
      expectedAppId: manifest.appId,
      currentCoreContract: currentMotionContentContract,
      availableCapabilities: allCapabilities,
    ).validate(manifest);
    if (report.error case final error?) throw ContentException(error);
    return _canonicalBytes(manifest.toJson());
  }

  Future<void> verify({
    required Uint8List manifestBytes,
    required Directory root,
    required String expectedAppId,
    required SemanticVersion currentCoreContract,
  }) async {
    final manifest = ContentManifestParser().parse(manifestBytes);
    final allCapabilities = <String>{
      for (final model in manifest.models)
        for (final capability in model.capabilities) capability.id,
    };
    final report = ManifestValidator(
      expectedAppId: expectedAppId,
      currentCoreContract: currentCoreContract,
      availableCapabilities: allCapabilities,
    ).validate(manifest);
    if (report.error case final error?) throw ContentException(error);

    final canonical = _canonicalBytes(manifest.toJson());
    if (!_bytesEqual(canonical, manifestBytes)) {
      failContent(ContentErrorCode.schema);
    }
    for (final asset in manifest.assets) {
      final bytes = await _readPhysicalAsset(root, asset.path, asset.id);
      verifyAssetBytes(asset, bytes);
    }
  }

  Future<Uint8List> _readPhysicalAsset(
    Directory root,
    String logicalPath,
    String contentId,
  ) async {
    final rootPath = await _validatedPhysicalRoot(root, logicalPath, contentId);
    final file = SecureAssetFile.open(
      rootPath: rootPath,
      logicalPath: logicalPath,
      contentId: contentId,
    );
    try {
      return file.readBounded(maximumSingleAssetBytes, contentId);
    } on ContentException {
      rethrow;
    } finally {
      file.close();
    }
  }

  Future<int> _physicalAssetLength(
    Directory root,
    String logicalPath,
    String contentId,
  ) async {
    final rootPath = await _validatedPhysicalRoot(root, logicalPath, contentId);
    final file = SecureAssetFile.open(
      rootPath: rootPath,
      logicalPath: logicalPath,
      contentId: contentId,
    );
    try {
      if (file.length > maximumSingleAssetBytes) {
        failContent(ContentErrorCode.resourceLimit, contentId: contentId);
      }
      return file.length;
    } finally {
      file.close();
    }
  }

  Future<String> _validatedPhysicalRoot(
    Directory root,
    String logicalPath,
    String contentId,
  ) async {
    var suppliedRootPath = root.absolute.path;
    // POSIX resolves a trailing separator before open(2) applies O_NOFOLLOW to
    // the final component. Strip it before both the diagnostic lstat and the
    // descriptor-bound open so `root-link/` cannot disguise a symlink root.
    while (suppliedRootPath.length > 1 &&
        suppliedRootPath.endsWith(Platform.pathSeparator)) {
      suppliedRootPath = suppliedRootPath.substring(
        0,
        suppliedRootPath.length - 1,
      );
    }
    if (_hasUnsafePhysicalRootSyntax(suppliedRootPath)) {
      failContent(ContentErrorCode.unsafePath, contentId: contentId);
    }
    late final FileSystemEntityType rootType;
    try {
      rootType = await FileSystemEntity.type(
        suppliedRootPath,
        followLinks: false,
      );
    } on FileSystemException {
      failContent(ContentErrorCode.missingAsset, contentId: contentId);
    }
    if (rootType == FileSystemEntityType.link) {
      failContent(ContentErrorCode.unsafePath, contentId: contentId);
    }
    if (rootType != FileSystemEntityType.directory) {
      failContent(ContentErrorCode.missingAsset, contentId: contentId);
    }

    final rootPath = suppliedRootPath;
    var current = rootPath;
    final segments = logicalPath.split('/');
    for (var index = 0; index < segments.length; index += 1) {
      current = '$current${Platform.pathSeparator}${segments[index]}';
      late final FileSystemEntityType type;
      try {
        type = await FileSystemEntity.type(current, followLinks: false);
      } on FileSystemException {
        failContent(ContentErrorCode.missingAsset, contentId: contentId);
      }
      if (type == FileSystemEntityType.link) {
        failContent(ContentErrorCode.unsafePath, contentId: contentId);
      }
      final isLast = index == segments.length - 1;
      if ((!isLast && type != FileSystemEntityType.directory) ||
          (isLast && type != FileSystemEntityType.file)) {
        failContent(ContentErrorCode.missingAsset, contentId: contentId);
      }
    }
    return rootPath;
  }

  // Asset bytes are opened by [SecureAssetFile] after the diagnostic pathname
  // checks above. The pathname is never used for length or content reads.
}

bool _hasUnsafePhysicalRootSyntax(String rootPath) {
  if (!rootPath.startsWith('/') || rootPath.contains('\u0000')) return true;
  if (rootPath == '/') return false;
  return rootPath
      .split('/')
      .skip(1)
      .any((segment) => segment.isEmpty || segment == '.' || segment == '..');
}

Uint8List _canonicalBytes(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode('${canonicalJsonEncode(value)}\n'));

List<Map<String, Object?>> _objectList(Object? value, int maximum) {
  if (value is! List<Object?> || value.length > maximum) {
    failContent(
      value is List<Object?>
          ? ContentErrorCode.resourceLimit
          : ContentErrorCode.schema,
    );
  }
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map<String, Object?>) failContent(ContentErrorCode.schema);
    result.add(item);
  }
  return result;
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

String _safeString(Object? value) {
  if (value is! String || value.isEmpty) failContent(ContentErrorCode.schema);
  return value;
}

String _safeIdentifier(Object? value) {
  final string = _safeString(value);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$').hasMatch(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
