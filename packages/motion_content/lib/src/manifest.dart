import 'dart:typed_data';

import 'content_error.dart';
import 'semantic_version.dart';
import 'strict_json.dart';

const int supportedContentSchemaVersion = 1;
const int maximumCourseCount = 256;
const int maximumLessonCount = 4096;
const int maximumModelCount = 64;
const int maximumAssetCount = 8192;
const int maximumSingleAssetBytes = 64 * 1024 * 1024;
const int maximumDeclaredAssetBytes = 512 * 1024 * 1024;

final class ContentManifest {
  ContentManifest({
    required this.schemaVersion,
    required this.contentVersion,
    required this.appId,
    required this.minimumCoreContract,
    required List<String> locales,
    required List<ContentCourse> courses,
    required List<ContentLesson> lessons,
    required List<ContentModel> models,
    required List<ContentAsset> assets,
    required this.catalogDigest,
  }) : locales = List.unmodifiable(locales),
       courses = List.unmodifiable(courses),
       lessons = List.unmodifiable(lessons),
       models = List.unmodifiable(models),
       assets = List.unmodifiable(assets);

  final int schemaVersion;
  final SemanticVersion contentVersion;
  final String appId;
  final SemanticVersion minimumCoreContract;
  final List<String> locales;
  final List<ContentCourse> courses;
  final List<ContentLesson> lessons;
  final List<ContentModel> models;
  final List<ContentAsset> assets;
  final String catalogDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'contentVersion': contentVersion.toString(),
    'appId': appId,
    'minimumCoreContract': minimumCoreContract.toString(),
    'locales': locales,
    'courses': courses.map((value) => value.toJson()).toList(growable: false),
    'lessons': lessons.map((value) => value.toJson()).toList(growable: false),
    'models': models.map((value) => value.toJson()).toList(growable: false),
    'assets': assets.map((value) => value.toJson()).toList(growable: false),
    'catalogDigest': catalogDigest,
  };
}

final class ContentCourse {
  ContentCourse({
    required this.id,
    required this.order,
    required this.visibility,
    required Map<String, String> title,
    required Map<String, String> description,
    required List<String> lessonIds,
  }) : title = Map.unmodifiable(title),
       description = Map.unmodifiable(description),
       lessonIds = List.unmodifiable(lessonIds);

  final String id;
  final int order;
  final String visibility;
  final Map<String, String> title;
  final Map<String, String> description;
  final List<String> lessonIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'order': order,
    'visibility': visibility,
    'title': title,
    'description': description,
    'lessonIds': lessonIds,
  };
}

final class ContentLesson {
  ContentLesson({
    required this.id,
    required this.type,
    required Map<String, String> title,
    required Map<String, String> description,
    required Map<String, String> instruction,
    required Map<String, String> accessibilityLabel,
    required List<String> modelIds,
    required List<String> assetIds,
  }) : title = Map.unmodifiable(title),
       description = Map.unmodifiable(description),
       instruction = Map.unmodifiable(instruction),
       accessibilityLabel = Map.unmodifiable(accessibilityLabel),
       modelIds = List.unmodifiable(modelIds),
       assetIds = List.unmodifiable(assetIds);

  final String id;
  final String type;
  final Map<String, String> title;
  final Map<String, String> description;
  final Map<String, String> instruction;
  final Map<String, String> accessibilityLabel;
  final List<String> modelIds;
  final List<String> assetIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'instruction': instruction,
    'accessibilityLabel': accessibilityLabel,
    'modelIds': modelIds,
    'assetIds': assetIds,
  };
}

final class ModelCapability {
  const ModelCapability({
    required this.id,
    required this.required,
    this.fallback,
  });

  final String id;
  final bool required;
  final String? fallback;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'required': required,
    if (fallback != null) 'fallback': fallback,
  };
}

sealed class ModelProvenance {
  const ModelProvenance({
    required this.licenseSpdx,
    required this.sourceUrl,
    required this.sourceVersion,
    required this.exportTool,
    required this.exportToolVersion,
  });

  final String licenseSpdx;
  final String sourceUrl;
  final String sourceVersion;
  final String exportTool;
  final String exportToolVersion;

  String get kind;
  Map<String, Object?> toJson();

  Map<String, Object?> commonJson() => <String, Object?>{
    'provenanceKind': kind,
    'licenseSpdx': licenseSpdx,
    'sourceUrl': sourceUrl,
    'sourceVersion': sourceVersion,
    'exportTool': exportTool,
    'exportToolVersion': exportToolVersion,
  };
}

final class FirstPartyModelProvenance extends ModelProvenance {
  const FirstPartyModelProvenance({
    required super.licenseSpdx,
    required super.sourceUrl,
    required super.sourceVersion,
    required super.exportTool,
    required super.exportToolVersion,
    required this.trainingReceiptRef,
    required this.holdoutReceiptRef,
  });

  final String trainingReceiptRef;
  final String holdoutReceiptRef;

  @override
  String get kind => 'firstParty';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...commonJson(),
    'trainingReceiptRef': trainingReceiptRef,
    'holdoutReceiptRef': holdoutReceiptRef,
  };
}

final class ThirdPartyModelProvenance extends ModelProvenance {
  const ThirdPartyModelProvenance({
    required super.licenseSpdx,
    required super.sourceUrl,
    required super.sourceVersion,
    required super.exportTool,
    required super.exportToolVersion,
    required this.vendorArtifactRef,
    required this.vendorChecksum,
  });

  final String vendorArtifactRef;
  final String vendorChecksum;

  @override
  String get kind => 'thirdParty';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...commonJson(),
    'vendorArtifactRef': vendorArtifactRef,
    'vendorChecksum': vendorChecksum,
  };
}

final class ContentModel {
  ContentModel({
    required this.id,
    required this.format,
    required this.path,
    required this.byteLength,
    required this.sha256,
    required List<ModelCapability> capabilities,
    required this.provenance,
  }) : capabilities = List.unmodifiable(capabilities);

  final String id;
  final String format;
  final String path;
  final int byteLength;
  final String sha256;
  final List<ModelCapability> capabilities;
  final ModelProvenance provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'format': format,
    'path': path,
    'byteLength': byteLength,
    'sha256': sha256,
    'capabilities': capabilities
        .map((value) => value.toJson())
        .toList(growable: false),
    ...provenance.toJson(),
  };
}

final class ContentAsset {
  const ContentAsset({
    required this.id,
    required this.path,
    required this.byteLength,
    required this.sha256,
  });

  final String id;
  final String path;
  final int byteLength;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'byteLength': byteLength,
    'sha256': sha256,
  };
}

final class ContentManifestParser {
  ContentManifestParser({StrictJsonDecoder? decoder})
    : decoder = decoder ?? const StrictJsonDecoder();

  final StrictJsonDecoder decoder;

  ContentManifest parse(Uint8List bytes) {
    final decoded = decoder.decode(bytes);
    final root = _object(decoded);
    _fields(
      root,
      required: const {
        'schemaVersion',
        'contentVersion',
        'appId',
        'minimumCoreContract',
        'locales',
        'courses',
        'lessons',
        'models',
        'assets',
        'catalogDigest',
      },
    );
    final schemaVersion = _integer(root['schemaVersion']);
    if (schemaVersion != supportedContentSchemaVersion) {
      failContent(ContentErrorCode.schema);
    }
    final locales = _stringList(root['locales']);
    if (locales.length != 2 || locales[0] != 'tr' || locales[1] != 'en') {
      failContent(ContentErrorCode.locale);
    }
    final rawCourses = _list(root['courses'], maximumCourseCount);
    final rawLessons = _list(root['lessons'], maximumLessonCount);
    final rawModels = _list(root['models'], maximumModelCount);
    final rawAssets = _list(root['assets'], maximumAssetCount);

    final courses = rawCourses.map(_course).toList(growable: false);
    final lessons = rawLessons.map(_lesson).toList(growable: false);
    final models = rawModels.map(_model).toList(growable: false);
    final assets = rawAssets.map(_asset).toList(growable: false);
    var declaredBytes = 0;
    for (final asset in assets) {
      declaredBytes += asset.byteLength;
      if (asset.byteLength > maximumSingleAssetBytes ||
          declaredBytes > maximumDeclaredAssetBytes) {
        failContent(ContentErrorCode.resourceLimit, contentId: asset.id);
      }
    }

    return ContentManifest(
      schemaVersion: schemaVersion,
      contentVersion: _version(root['contentVersion']),
      appId: _identifier(root['appId']),
      minimumCoreContract: _version(root['minimumCoreContract']),
      locales: locales,
      courses: courses,
      lessons: lessons,
      models: models,
      assets: assets,
      catalogDigest: _hash(root['catalogDigest']),
    );
  }

  ContentCourse _course(Object? raw) {
    final map = _object(raw);
    _fields(
      map,
      required: const {
        'id',
        'order',
        'visibility',
        'title',
        'description',
        'lessonIds',
      },
    );
    return ContentCourse(
      id: _identifier(map['id']),
      order: _nonNegativeInteger(map['order']),
      visibility: _identifier(map['visibility']),
      title: _localized(map['title']),
      description: _localized(map['description']),
      lessonIds: _identifierList(map['lessonIds']),
    );
  }

  ContentLesson _lesson(Object? raw) {
    final map = _object(raw);
    _fields(
      map,
      required: const {
        'id',
        'type',
        'title',
        'description',
        'instruction',
        'accessibilityLabel',
        'modelIds',
        'assetIds',
      },
    );
    return ContentLesson(
      id: _identifier(map['id']),
      type: _identifier(map['type']),
      title: _localized(map['title']),
      description: _localized(map['description']),
      instruction: _localized(map['instruction']),
      accessibilityLabel: _localized(map['accessibilityLabel']),
      modelIds: _identifierList(map['modelIds']),
      assetIds: _identifierList(map['assetIds']),
    );
  }

  ContentModel _model(Object? raw) {
    final map = _object(raw);
    final kind = _string(map['provenanceKind']);
    final common = <String>{
      'id',
      'format',
      'path',
      'byteLength',
      'sha256',
      'capabilities',
      'provenanceKind',
      'licenseSpdx',
      'sourceUrl',
      'sourceVersion',
      'exportTool',
      'exportToolVersion',
    };
    late final ModelProvenance provenance;
    if (kind == 'firstParty') {
      _fields(
        map,
        required: {...common, 'trainingReceiptRef', 'holdoutReceiptRef'},
      );
      provenance = FirstPartyModelProvenance(
        licenseSpdx: _spdxIdentifier(map['licenseSpdx']),
        sourceUrl: _sourceUrl(map['sourceUrl']),
        sourceVersion: _provenanceToken(map['sourceVersion']),
        exportTool: _provenanceToken(map['exportTool']),
        exportToolVersion: _provenanceToken(map['exportToolVersion']),
        trainingReceiptRef: _provenanceReference(
          map['trainingReceiptRef'],
          'training',
        ),
        holdoutReceiptRef: _provenanceReference(
          map['holdoutReceiptRef'],
          'holdout',
        ),
      );
    } else if (kind == 'thirdParty') {
      _fields(
        map,
        required: {...common, 'vendorArtifactRef', 'vendorChecksum'},
      );
      provenance = ThirdPartyModelProvenance(
        licenseSpdx: _spdxIdentifier(map['licenseSpdx']),
        sourceUrl: _sourceUrl(map['sourceUrl']),
        sourceVersion: _provenanceToken(map['sourceVersion']),
        exportTool: _provenanceToken(map['exportTool']),
        exportToolVersion: _provenanceToken(map['exportToolVersion']),
        vendorArtifactRef: _provenanceReference(
          map['vendorArtifactRef'],
          'vendor',
        ),
        vendorChecksum: _hash(map['vendorChecksum']),
      );
    } else {
      failContent(ContentErrorCode.schema);
    }
    final capabilities = _list(
      map['capabilities'],
      256,
    ).map(_capability).toList(growable: false);
    return ContentModel(
      id: _identifier(map['id']),
      format: _identifier(map['format']),
      path: _string(map['path']),
      byteLength: _boundedAssetLength(map['byteLength']),
      sha256: _hash(map['sha256']),
      capabilities: capabilities,
      provenance: provenance,
    );
  }

  ModelCapability _capability(Object? raw) {
    final map = _object(raw);
    _fields(
      map,
      required: const {'id', 'required'},
      optional: const {'fallback'},
    );
    final required = _boolean(map['required']);
    final fallback = map.containsKey('fallback')
        ? _identifier(map['fallback'])
        : null;
    if ((!required && fallback == null) || (required && fallback != null)) {
      failContent(ContentErrorCode.capability, contentId: _safeId(map['id']));
    }
    return ModelCapability(
      id: _identifier(map['id']),
      required: required,
      fallback: fallback,
    );
  }

  ContentAsset _asset(Object? raw) {
    final map = _object(raw);
    _fields(map, required: const {'id', 'path', 'byteLength', 'sha256'});
    return ContentAsset(
      id: _identifier(map['id']),
      path: _string(map['path']),
      byteLength: _boundedAssetLength(map['byteLength']),
      sha256: _hash(map['sha256']),
    );
  }
}

Map<String, Object?> decodeStrictJsonObject(Uint8List bytes) {
  final decoded = const StrictJsonDecoder().decode(bytes);
  return _object(decoded);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) failContent(ContentErrorCode.schema);
  return value;
}

List<Object?> _list(Object? value, int maximum) {
  if (value is! List<Object?>) failContent(ContentErrorCode.schema);
  if (value.length > maximum) failContent(ContentErrorCode.resourceLimit);
  return value;
}

void _fields(
  Map<String, Object?> map, {
  required Set<String> required,
  Set<String> optional = const {},
}) {
  if (!map.keys.toSet().containsAll(required) ||
      map.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    failContent(ContentErrorCode.schema);
  }
}

String _string(Object? value) {
  if (value is! String || value.isEmpty) failContent(ContentErrorCode.schema);
  return value;
}

String _identifier(Object? value) {
  final string = _string(value);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$').hasMatch(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

String? _safeId(Object? value) {
  if (value is String &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$').hasMatch(value)) {
    return value;
  }
  return null;
}

String _boundedProvenanceString(Object? value, int maximumLength) {
  final string = _string(value);
  final trimmed = string.trim();
  if (trimmed.isEmpty ||
      trimmed != string ||
      string.length > maximumLength ||
      trimmed.toUpperCase() == 'N/A') {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

String _spdxIdentifier(Object? value) {
  final string = _boundedProvenanceString(value, 64);
  // Motion Embedded Content V1 intentionally supports only this permissive
  // model-license subset. Every ID is a current, non-deprecated entry in SPDX
  // License List 3.28.0. Expanding this set is a schema/R2 decision rather than
  // accepting arbitrary SPDX-shaped text.
  const supportedV1Licenses = {
    'Apache-2.0',
    'BSD-2-Clause',
    'BSD-3-Clause',
    'MIT',
  };
  if (!supportedV1Licenses.contains(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

String _provenanceToken(Object? value) {
  final string = _boundedProvenanceString(value, 80);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$').hasMatch(string) ||
      _looksCredentialBearing(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

String _provenanceReference(Object? value, String namespace) {
  final string = _boundedProvenanceString(value, 128);
  final pattern = RegExp('^$namespace:[A-Za-z0-9][A-Za-z0-9._:-]{0,63}\$');
  if (!pattern.hasMatch(string) || _looksCredentialBearing(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

bool _looksCredentialBearing(String value) => RegExp(
  r'(?:bearer|secret|api[_-]?key|github_pat_|gh[pousr]_|sk-(?:proj-)?|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})',
  caseSensitive: false,
).hasMatch(value);

String _sourceUrl(Object? value) {
  final string = _boundedProvenanceString(value, 2048);
  final uri = Uri.tryParse(string);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      _looksCredentialBearingAfterPercentDecoding(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

bool _looksCredentialBearingAfterPercentDecoding(String value) {
  var candidate = value;
  // Every successful pass consumes at least one percent-escape, so the input
  // length is a strict work bound even for multiply encoded credentials.
  for (var pass = 0; pass <= value.length; pass += 1) {
    if (_looksCredentialBearing(candidate)) return true;
    if (!candidate.contains('%')) return false;
    try {
      final decoded = Uri.decodeComponent(candidate);
      if (decoded == candidate) return false;
      candidate = decoded;
    } on FormatException {
      return true;
    }
  }
  return true;
}

int _integer(Object? value) {
  if (value is! int) failContent(ContentErrorCode.schema);
  return value;
}

int _nonNegativeInteger(Object? value) {
  final number = _integer(value);
  if (number < 0) failContent(ContentErrorCode.schema);
  return number;
}

int _boundedAssetLength(Object? value) {
  final number = _nonNegativeInteger(value);
  if (number > maximumSingleAssetBytes) {
    failContent(ContentErrorCode.resourceLimit);
  }
  return number;
}

bool _boolean(Object? value) {
  if (value is! bool) failContent(ContentErrorCode.schema);
  return value;
}

SemanticVersion _version(Object? value) {
  try {
    return SemanticVersion.parse(_string(value));
  } on FormatException {
    failContent(ContentErrorCode.schema);
  }
}

String _hash(Object? value) {
  final string = _string(value);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(string)) {
    failContent(ContentErrorCode.schema);
  }
  return string;
}

List<String> _stringList(Object? value) =>
    _list(value, maximumAssetCount).map(_string).toList(growable: false);

List<String> _identifierList(Object? value) =>
    _list(value, maximumAssetCount).map(_identifier).toList(growable: false);

Map<String, String> _localized(Object? value) {
  final map = _object(value);
  if (map.length != 2 || !map.containsKey('tr') || !map.containsKey('en')) {
    failContent(ContentErrorCode.locale);
  }
  final result = <String, String>{};
  for (final locale in const ['tr', 'en']) {
    final text = map[locale];
    if (text is! String || text.trim().isEmpty) {
      failContent(ContentErrorCode.locale);
    }
    result[locale] = text;
  }
  return result;
}
