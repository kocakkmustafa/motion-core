import 'dart:convert';

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

/// The harvest pipeline (Python, `mocore/fixture.py` SCHEMA_VERSION=2) and
/// this reader share one family schema with two producers. These tests pin
/// the bridge: a byte-for-byte-shaped v2 document — compact `lm` frames,
/// ms timestamps, snake_case meta, `provenance` block — must decode into
/// the same types every other consumer of [Fixture] already speaks.
void main() {
  Map<String, dynamic> v2Doc() => <String, dynamic>{
        'schemaVersion': 2,
        'app': 'lissom',
        'recordingMeta': <String, dynamic>{
          'test': 'unknown',
          'subject': 'unknown',
          'side': 'bilateral',
          'plane': 'frontal',
          'light': 'bright',
          'clothing': 'tight',
          'distance_cm': 0,
          'take': 'freeform',
          'device': 'harvest',
          'fps': 29.97,
          'frame_count': 3,
          'technique': 'deep_squat',
          'lighting': 'bright',
          'camera_setup': 'unknown',
          'body_profile': 'unknown',
          'resolution': '1920x1080',
          'source_video': 'clip.mp4',
          'frames_without_pose': 1,
        },
        'modelVersion': 'pose_landmarker_full/float16/1',
        'modelSha256': 'abc123',
        'frames': <Map<String, dynamic>>[
          <String, dynamic>{
            't': 0.0,
            'detected': true,
            'lm': List<List<double>>.generate(
                Lm.count, (int i) => <double>[0.5, 0.4, 0.0, 0.9, 0.99]),
            'world': List<List<double>>.generate(
                Lm.count, (int i) => <double>[0.1, -0.2, 0.05]),
          },
          <String, dynamic>{'t': 33.37, 'detected': false},
          <String, dynamic>{
            't': 66.73,
            'detected': true,
            'lm': List<List<double>>.generate(
                Lm.count, (int i) => <double>[0.51, 0.41, 0.01, 0.8, 0.97]),
          },
        ],
        'labels': <Map<String, dynamic>>[],
        'provenance': <String, dynamic>{
          'sourceUrl': 'https://youtu.be/example',
          'license': 'CC-BY',
          'channel': 'physio-anna',
          'extractor': 'extract_landmarks.py',
          'futureField': 'kept',
        },
      };

  group('fixture schema v2 bridge', () {
    test('decodes the Python harvest dialect end to end', () {
      final Fixture fx = Fixture.decode(jsonEncode(v2Doc()));

      expect(fx.schemaVersion, 2);
      expect(fx.app, 'lissom');
      expect(fx.technique, 'deep_squat',
          reason: 'v2 carries technique inside the free-form meta');
      expect(fx.frames, hasLength(2));
      expect(fx.undetectedFrameCount, 1,
          reason: 'the dropped frame must stay countable, not vanish');
      expect(fx.frames[0].tUs, 0);
      expect(fx.frames[1].tUs, 66730,
          reason: 'ms timestamps convert to the family µs clock');
      expect(fx.frames[0].landmarks, hasLength(Lm.count));
      expect(fx.frames[0].landmarks[Lm.leftShoulder].visibility,
          closeTo(0.9, 1e-9),
          reason: 'visibility comes from lm[3]; presence (lm[4]) is dropped '
              'so calibrated gate thresholds keep their meaning');
    });

    test('surfaces provenance for the instructor-counting gates', () {
      final Fixture fx = Fixture.decode(jsonEncode(v2Doc()));
      expect(fx.provenance, isNotNull);
      expect(fx.provenance!.sourceIdentity, 'physio-anna',
          reason: 'channel is the identity minSources counts as one teacher');
      expect(fx.provenance!.raw['futureField'], 'kept',
          reason: 'unmodelled provenance fields must survive round trips');
    });

    test('parses resolution into the J-028 correction input', () {
      final FrameSize? size =
          Fixture.decode(jsonEncode(v2Doc())).recordingMeta.frameSize;
      expect(size, isNotNull);
      expect(size!.aspect, closeTo(1920 / 1080, 1e-9));
    });

    test('a fixture with technique only in the shot-list test id still '
        'names itself', () {
      final Map<String, dynamic> doc = v2Doc();
      (doc['recordingMeta'] as Map<String, dynamic>).remove('technique');
      (doc['recordingMeta'] as Map<String, dynamic>)['test'] = 'hip_hinge';
      expect(Fixture.decode(jsonEncode(doc)).technique, 'hip_hinge');
    });

    test('v1 documents keep decoding exactly as before', () {
      final Fixture original = Fixture(
        app: 'choreia',
        technique: 'running_man',
        frames: <PoseFrame>[
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0),
        ],
      );
      final Fixture back = Fixture.decode(original.encode());
      expect(back.schemaVersion, 1);
      expect(back.technique, 'running_man');
      expect(back.frames, hasLength(1));
      expect(back.provenance, isNull);
    });

    test('a future schema version is refused loudly', () {
      final Map<String, dynamic> doc = v2Doc()..['schemaVersion'] = 3;
      expect(() => Fixture.decode(jsonEncode(doc)),
          throwsA(isA<FormatException>()));
    });
  });
}
