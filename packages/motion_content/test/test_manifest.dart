import 'dart:convert';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';

final modelBytes = Uint8List.fromList([1, 2, 3, 4]);
final lessonBytes = Uint8List.fromList(utf8.encode('{"lesson":1}'));

Map<String, Object?> validManifestMap() => <String, Object?>{
  'schemaVersion': 1,
  'contentVersion': '1.0.0',
  'appId': 'com.example.motion',
  'minimumCoreContract': '1.0.0',
  'locales': <Object?>['tr', 'en'],
  'courses': <Object?>[
    <String, Object?>{
      'id': 'foundation',
      'order': 0,
      'visibility': 'free',
      'title': <String, Object?>{'tr': 'Temel', 'en': 'Foundation'},
      'description': <String, Object?>{
        'tr': 'Temel dersler',
        'en': 'Foundation lessons',
      },
      'lessonIds': <Object?>['lesson-one'],
    },
  ],
  'lessons': <Object?>[
    <String, Object?>{
      'id': 'lesson-one',
      'type': 'practice',
      'title': <String, Object?>{'tr': 'Birinci ders', 'en': 'Lesson one'},
      'description': <String, Object?>{
        'tr': 'İlk çalışma',
        'en': 'First practice',
      },
      'instruction': <String, Object?>{'tr': 'Hazır ol', 'en': 'Get ready'},
      'accessibilityLabel': <String, Object?>{
        'tr': 'Birinci dersi aç',
        'en': 'Open lesson one',
      },
      'modelIds': <Object?>['pose-model'],
      'assetIds': <Object?>['lesson-data'],
    },
  ],
  'models': <Object?>[
    <String, Object?>{
      'id': 'pose-model',
      'format': 'tflite',
      'path': 'assets/motion_content/models/pose.tflite',
      'byteLength': modelBytes.length,
      'sha256': computeSha256Hex(modelBytes),
      'capabilities': <Object?>[
        <String, Object?>{
          'id': 'gpu_delegate',
          'required': false,
          'fallback': 'cpu',
        },
      ],
      'provenanceKind': 'thirdParty',
      'licenseSpdx': 'Apache-2.0',
      'sourceUrl': 'https://models.example.org/pose',
      'sourceVersion': '1.0.0',
      'exportTool': 'vendor-exporter',
      'exportToolVersion': '2.1.0',
      'vendorArtifactRef': 'vendor:pose:1.0.0',
      'vendorChecksum': computeSha256Hex(modelBytes),
    },
  ],
  'assets': <Object?>[
    <String, Object?>{
      'id': 'pose-model-bytes',
      'path': 'assets/motion_content/models/pose.tflite',
      'byteLength': modelBytes.length,
      'sha256': computeSha256Hex(modelBytes),
    },
    <String, Object?>{
      'id': 'lesson-data',
      'path': 'assets/motion_content/lessons/one.json',
      'byteLength': lessonBytes.length,
      'sha256': computeSha256Hex(lessonBytes),
    },
  ],
};

Map<String, Object?> deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map<Object?, Object?>)
        .cast<String, Object?>();

Uint8List encodeManifest(Map<String, Object?> map) {
  final copy = deepCopy(map)..remove('catalogDigest');
  copy['catalogDigest'] = computeCatalogDigest(copy);
  return Uint8List.fromList(utf8.encode(jsonEncode(copy)));
}

ContentManifest parseManifest([Map<String, Object?>? map]) =>
    ContentManifestParser().parse(encodeManifest(map ?? validManifestMap()));

Map<String, Uint8List> validReaderData() => <String, Uint8List>{
  'assets/motion_content/manifest.json': encodeManifest(validManifestMap()),
  'assets/motion_content/models/pose.tflite': modelBytes,
  'assets/motion_content/lessons/one.json': lessonBytes,
};
