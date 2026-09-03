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

    test('the eligibility gate is actually ASKED (M-O-29, fifth question)',
        () {
      // The rig wrote referenceEligible all night and no consumer read it —
      // including this CLI's first release. A gate nobody asks is a gate
      // that does not exist.
      Fixture harvested(String id, {Object? eligible}) => Fixture(
            app: 'lissom',
            technique: 'deep_squat',
            frames: SyntheticNoise.jitter(
                fourCountPhrase().sample(fps: 30), seed: id.hashCode & 0xff,
                sigma: 0.004),
            provenance: ProvenanceInfo(
              channel: 'ch-$id',
              sourceUrl: 'https://youtu.be/$id',
              raw: <String, dynamic>{
                'sourceUrl': 'https://youtu.be/$id',
                'channel': 'ch-$id',
                if (eligible != null) 'referenceEligible': eligible,
              },
            ),
          );

      final Map<String, Fixture> mixed = <String, Fixture>{
        for (int i = 0; i < 3; i++) 'ok$i': harvested('ok$i', eligible: true),
        'bad': harvested('bad', eligible: false),
        'unk': harvested('unk'),
      };

      final Map<String, dynamic> artifact = const ReferenceCli()
          .buildArtifact(technique: 'deep_squat', fixturesById: mixed);
      final Map<String, dynamic> r = artifact['result'] as Map<String, dynamic>;
      expect(r['excludedIneligibleIds'], <String>['bad'],
          reason: 'classified-ineligible is never admitted, always named');
      expect(r['excludedUnattestedIds'], <String>['unk'],
          reason: 'harvested without attestation is fail-closed by default');
      expect(r['contributingTakes'], 3);
      expect(artifact['measurementProvenance'], 'ATTESTED');

      // The explicit override admits the unattested take but the artifact
      // must say what its numbers now are.
      final Map<String, dynamic> loose =
          const ReferenceCli(allowUnattested: true)
              .buildArtifact(technique: 'deep_squat', fixturesById: mixed);
      expect(loose['measurementProvenance'], 'PROVISIONAL');
      expect((loose['result'] as Map<String, dynamic>)['contributingTakes'],
          4);

      // Eligibility exclusions can starve the build — that refusal must
      // surface as the count/source gate, not be papered over.
      final Map<String, Fixture> starved = <String, Fixture>{
        'a': harvested('a', eligible: true),
        'b': harvested('b', eligible: false),
        'c': harvested('c', eligible: false),
      };
      expect(
        () => const ReferenceCli()
            .buildArtifact(technique: 'deep_squat', fixturesById: starved),
        throwsArgumentError,
      );
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

    // J-056 (core P0, JabLab proved it): extract() ignores visibility, and
    // prepareTake never called gate() — invisible ankles' guessed positions
    // became numeric shin/knee angles that read as instructor disagreement.
    test('a joint whose landmarks are invisible is NaN, not a guessed number',
        () {
      final List<PoseFrame> frames = fourCountPhrase()
          .sample(fps: 30)
          .map((PoseFrame f) => PoseFrame(
                tUs: f.tUs,
                landmarks: <PoseLandmark>[
                  for (int i = 0; i < f.landmarks.length; i++)
                    // Ankles (27/28) effectively invisible with IN-FRAME
                    // garbage coordinates — the MediaPipe shape (guessed
                    // positions, low confidence). In-frame on purpose: the
                    // frame-level gate must NOT save us here, the per-joint
                    // gate must.
                    (i == 27 || i == 28)
                        ? PoseLandmark(0.3 + 0.01 * i, 0.95, 0, 0.05)
                        : f.landmarks[i],
                ],
                modelVersion: f.modelVersion,
              ))
          .toList(growable: false);
      final Fixture fx = Fixture(
        app: 'jablab',
        technique: 'stance',
        frames: frames,
        provenance: ProvenanceInfo(channel: 'ch-lowvis'),
      );
      final ({ReferenceTake take, Map<String, dynamic> report}) p =
          const ReferenceCli().prepareTake('lowvis', fx);
      expect(p.take.frames, isNotEmpty,
          reason: 'upper body is fine; frames must survive the frame gate');
      int shinNaN = 0, shinNum = 0, armNum = 0;
      for (final JointAngleVector v in p.take.frames) {
        final double? shin = v.byId('left_shin');
        final double? arm = v.byId('left_upper_arm');
        if (shin == null) {
          shinNaN++;
        } else {
          shinNum++;
        }
        if (arm != null) armNum++;
      }
      expect(shinNum, 0,
          reason: 'an invisible ankle must never yield a numeric shin angle '
              '— that number would enter consensus as a real measurement');
      expect(shinNaN, p.take.frames.length);
      expect(armNum, greaterThan(0),
          reason: 'gating is per-joint, not per-frame');
    });

    // L-143: a harvest clip whose every frame was undetected decodes into a
    // frameless take. That used to crash deep in consensus math — and the
    // crash printed as a count/source gate refusal, a code defect wearing a
    // gate's clothes.
    test('a frameless fixture is excluded BY NAME and the build continues '
        '(L-143)', () {
      final Map<String, Fixture> fixtures = <String, Fixture>{
        for (int i = 0; i < 6; i++)
          'take$i': fixtureOf('take$i', tempoRatio: 0.94 + i * 0.03, seed: i),
        'undetected': Fixture(
          app: 'lissom',
          technique: 'overhead_reach',
          frames: const <PoseFrame>[],
          provenance: ProvenanceInfo(channel: 'channel-undetected'),
        ),
      };
      final Map<String, dynamic> artifact = const ReferenceCli()
          .buildArtifact(technique: 'overhead_reach', fixturesById: fixtures);
      final Map<String, dynamic> r = artifact['result'] as Map<String, dynamic>;
      expect(r['excludedNoMeasurableFrameIds'], <String>['undetected']);
      expect(r['contributingTakes'], 6);
      // The exclusion is visible in the take reports with its reason — an
      // exclusion the artifact does not show is one nobody can ask about.
      final Map<String, dynamic> report = (artifact['takes'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((Map<String, dynamic> t) => t['id'] == 'undetected');
      expect(report['excluded'], 'noMeasurableFrames');
      expect(report['frames'], 0);
    });

    test('the single-fixture L-143 repro is a named refusal, not a crash',
        () {
      final Map<String, Fixture> one = <String, Fixture>{
        'solo': Fixture(
          app: 'lissom',
          technique: 'overhead_reach',
          frames: const <PoseFrame>[],
          provenance: ProvenanceInfo(channel: 'ch-solo'),
        ),
      };
      const ReferenceCli cli = ReferenceCli(
          builder: ReferenceBuilder(minTakes: 1, minSources: 1));
      expect(
        () =>
            cli.buildArtifact(technique: 'overhead_reach', fixturesById: one),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => '${e.message}', 'message',
                allOf(contains('solo'), contains('no measurable frames')))
            // The old failure shape: RangeError('Invalid value') IS an
            // ArgumentError — the refusal must not be that.
            .having((ArgumentError e) => e, 'type', isNot(isA<RangeError>()))),
      );
    });

    test('a pool thinned below the gates is refused with names and reasons',
        () {
      final Map<String, Fixture> mixed = <String, Fixture>{
        'good0': fixtureOf('good0', seed: 60),
        'good1': fixtureOf('good1', seed: 61),
        'empty': Fixture(
          app: 'lissom',
          technique: 'deep_squat',
          frames: const <PoseFrame>[],
          provenance: ProvenanceInfo(channel: 'ch-empty'),
        ),
      };
      expect(
        () => const ReferenceCli()
            .buildArtifact(technique: 'deep_squat', fixturesById: mixed),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(contains('empty'), contains('no measurable frames'),
                contains('2 usable take(s)')))),
      );
    });

    test('DTW capacity refusal reaches the CLI boundary by its exact name', () {
      final Map<String, Fixture> fixtures = <String, Fixture>{
        for (int i = 0; i < 3; i++)
          'take$i': fixtureOf('take$i', seed: 80 + i),
      };
      const ReferenceCli cli = ReferenceCli(
        builder: ReferenceBuilder(
          dtw: Dtw(maxSequenceLength: 4),
          minTakes: 3,
          minSources: 3,
        ),
        segmentCycles: false,
      );

      expect(
        () => cli.buildArtifact(
          technique: 'deep_squat',
          fixturesById: fixtures,
        ),
        throwsA(
          isA<DtwLimitExceeded>()
              .having(
                (DtwLimitExceeded e) => e.reason,
                'reason',
                DtwLimitReason.sequenceLengthExceeded,
              )
              .having(
                (DtwLimitExceeded e) => '${e.message}',
                'message',
                contains(DtwLimitReason.sequenceLengthExceeded.code),
              ),
        ),
      );
    });
  });
}
