import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// End-to-end: six synthetic teachers, serialized through the family fixture
/// format, back in through the v2-capable reader, out as a reference
/// artifact. This is the same function the CLI runs — the test IS the CLI
/// minus argument parsing.
void main() {
  Fixture fixtureOf(String id, {double tempoRatio = 1.0, int seed = 1}) {
    final List<PoseFrame> frames = SyntheticNoise.jitter(
      fourCountPhrase().sample(fps: 30, tempoRatio: tempoRatio),
      seed: seed,
      sigma: 0.004,
    );
    return Fixture(
      app: 'lissom',
      technique: 'deep_squat',
      frames: frames,
      provenance: ProvenanceInfo(channel: 'channel-$id'),
    );
  }

  group('ReferenceCli', () {
    test('builds an artifact whose claims match the reference', () {
      final Map<String, Fixture> fixtures = <String, Fixture>{
        for (int i = 0; i < 6; i++)
          'take$i': fixtureOf('take$i', tempoRatio: 0.94 + i * 0.03, seed: i),
      };
      final Map<String, dynamic> artifact = const ReferenceCli()
          .buildArtifact(technique: 'deep_squat', fixturesById: fixtures);

      final Map<String, dynamic> r =
          artifact['result'] as Map<String, dynamic>;
      expect(r['contributingTakes'], 6);
      expect(r['distinctSources'], 6);
      expect(r['excludedOutlierIds'], isEmpty);

      final Map<String, dynamic> tol =
          artifact['tolerance'] as Map<String, dynamic>;
      final Map<String, dynamic> sources =
          tol['perJointSource'] as Map<String, dynamic>;
      expect(sources.values, everyElement(isIn(<String>['floor', 'variance'])),
          reason: 'every joint must declare where its tolerance came from');
      // Near-identical synthetic teachers: dispersion sits under the floor,
      // and the artifact must SAY so rather than posing as measured
      // disagreement (G-050).
      expect(sources.values, contains('floor'));

      final List<dynamic> mean =
          (artifact['frames'] as Map<String, dynamic>)['meanRad']
              as List<dynamic>;
      expect(mean, hasLength(r['length']));
      expect((artifact['takes'] as List<dynamic>).length, 6);
      for (final dynamic t in artifact['takes'] as List<dynamic>) {
        expect((t as Map<String, dynamic>)['cycleCount'], isNull,
            reason: 'cycles were not measured; a plausible number here '
                'would be the thinEvidence failure inverted');
      }
    });

    test('artifact survives the fixture wire format round trip', () {
      // The CLI reads files, not objects — encode/decode must not change
      // the outcome (this is where the ms→µs and lm-row bridges would leak).
      final Map<String, Fixture> direct = <String, Fixture>{
        for (int i = 0; i < 3; i++) 'w$i': fixtureOf('w$i', seed: 40 + i),
      };
      final Map<String, Fixture> wired = <String, Fixture>{
        for (final MapEntry<String, Fixture> e in direct.entries)
          e.key: Fixture.decode(e.value.encode()),
      };
      final Map<String, dynamic> a = const ReferenceCli()
          .buildArtifact(technique: 'x', fixturesById: direct);
      final Map<String, dynamic> b = const ReferenceCli()
          .buildArtifact(technique: 'x', fixturesById: wired);
      expect(
          (b['result'] as Map<String, dynamic>)['contributingTakes'],
          (a['result'] as Map<String, dynamic>)['contributingTakes']);
      expect((b['frames'] as Map<String, dynamic>)['meanRad'],
          (a['frames'] as Map<String, dynamic>)['meanRad']);
    });

    test('one teacher pretending to be six is refused end to end', () {
      final Map<String, Fixture> fixtures = <String, Fixture>{
        for (int i = 0; i < 6; i++) 'take$i': Fixture(
            app: 'lissom',
            technique: 'deep_squat',
            frames: fourCountPhrase().sample(fps: 30),
            provenance: const ProvenanceInfo(channel: 'same-channel')),
      };
      expect(
        () => const ReferenceCli()
            .buildArtifact(technique: 'deep_squat', fixturesById: fixtures),
        throwsArgumentError,
      );
    });
  });
}
