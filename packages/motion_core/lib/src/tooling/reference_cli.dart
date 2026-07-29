import '../fixture/fixture.dart';
import '../geometry/joint_angles.dart';
import '../geometry/normalization.dart';
import '../pose/confidence_gate.dart';
import '../pose/pose_frame.dart';
import '../scoring/reference_builder.dart';

/// The canonical fixture→reference pipeline behind `tool/build_reference.dart`.
///
/// Lives in the library, not the tool entrypoint, for one reason: apps grew
/// their own builders while waiting for this (Gravita's three-gate tool), and
/// the only way "canonical" stays true is if the CLI and any app-side caller
/// run the *same* function. The tool file only parses arguments.
///
/// Every family gate runs here, in order, and every drop is counted, never
/// silent:
///  1. J-028 — isotropic correction when the fixture recorded its frame size
///     (a fixture without one is accepted but the artifact says so).
///  2. Confidence gate per frame (visibility + in-frame with aspect-aware
///     bounds) — dropped frames are counted per take.
///  3. minTakes / minSources / M-F-47 agreement — inside [ReferenceBuilder].
///
/// The artifact reports tolerance per joint WITH its source (G-050): a
/// consumer may only claim "variance-derived" where the label says variance.
/// M-F-43 standing of one fixture as a reference source (M-O-29 / M-F-62).
///
/// The harvest rig classifies every clip and writes `referenceEligible` into
/// its provenance — and for one whole night NOTHING asked: not the app pilot
/// that found the hole, not this CLI. A gate no consumer reads is a gate
/// that does not exist ("bu kapıya soran var mı?" — the fifth liveness
/// question). This enum is the reader.
enum TakeEligibility {
  /// Harvested and classified eligible by the rig.
  attested,

  /// No harvest provenance — a first-party recording (shot list, studio),
  /// whose eligibility is established outside the rig.
  firstParty,

  /// Harvested (has a source URL) but carries no eligibility attestation —
  /// e.g. classification ran without its evidence source. Fail-closed by
  /// default; admissible only under an explicit flag that stamps the whole
  /// artifact PROVISIONAL.
  unattested,

  /// Classified NOT eligible — never admitted, always named.
  ineligible,
}

final class ReferenceCli {
  const ReferenceCli({
    this.builder = const ReferenceBuilder(),
    this.clusterToleranceDeg = 14,
    this.specs = StandardJoints.fullBody,
    this.minVisibleShare = 0.6,
    this.allowUnattested = false,
  });

  /// Admit harvested takes whose eligibility was never attested (M-F-43
  /// fail-closed override). The artifact then declares itself PROVISIONAL —
  /// numbers exist but may not close tolerance claims (M-C-01 discipline).
  final bool allowUnattested;

  static TakeEligibility eligibilityOf(Fixture fixture) {
    final ProvenanceInfo? p = fixture.provenance;
    if (p == null) return TakeEligibility.firstParty;
    final Object? v = p.raw['referenceEligible'];
    if (v == true) return TakeEligibility.attested;
    if (v == false) return TakeEligibility.ineligible;
    return p.sourceUrl != null
        ? TakeEligibility.unattested
        : TakeEligibility.firstParty;
  }

  final ReferenceBuilder builder;
  final double clusterToleranceDeg;
  final List<JointSpec> specs;

  /// A frame passes when at least this share of the joints' required
  /// landmarks are visible per the confidence gate.
  final double minVisibleShare;

  /// Decodes one fixture into a gated, angle-space take.
  ({ReferenceTake take, Map<String, dynamic> report}) prepareTake(
    String id,
    Fixture fixture,
  ) {
    final FrameSize? size = fixture.recordingMeta.frameSize;
    final List<int> required = <int>{
      for (final JointSpec s in specs) ...s.requiredLandmarks,
    }.where((int i) => i >= 0).toList(growable: false);
    const ConfidenceGate gate = ConfidenceGate();
    final PoseNormalizer normalizer = PoseNormalizer();
    final JointAngleExtractor extractor = JointAngleExtractor(specs: specs);

    int gateDropped = 0;
    final List<JointAngleVector> frames = <JointAngleVector>[];
    for (PoseFrame frame in fixture.frames) {
      if (size != null) frame = frame.toIsotropic(size);
      final FrameQuality q = gate.evaluate(
        frame,
        required: required,
        xExtent: size?.aspect ?? 1.0,
      );
      // Softer than [FrameQuality.judgeable] on purpose: judgeable demands
      // every required landmark, which discards most real harvest footage
      // over a clipped ankle. A reference frame needs MOST of the skeleton;
      // per-joint NaN handling absorbs the rest. An unreliable torso or any
      // off-frame landmark still drops the frame outright.
      final int visible = required.length - q.weakLandmarks.length;
      if (q.issue == QualityIssue.torsoUnreliable ||
          q.offFrameLandmarks.isNotEmpty ||
          visible < required.length * minVisibleShare) {
        gateDropped++;
        continue;
      }
      frames.add(extractor.extract(normalizer.normalize(frame)));
    }

    final String source = fixture.provenance?.sourceIdentity ??
        (fixture.recordingMeta.toJson()['source_video'] as String? ?? id);
    return (
      take: ReferenceTake(id: id, source: source, frames: frames),
      report: <String, dynamic>{
        'id': id,
        'source': source,
        'frames': frames.length,
        'undetectedFrames': fixture.undetectedFrameCount,
        'gateDroppedFrames': gateDropped,
        'fps': fixture.recordingMeta.fps,
        'isotropicCorrected': size != null,
        // Cycle counts need cycle alignment, which this pipeline has not run
        // — null means NOT MEASURED (Choreia's thinEvidence lesson: an
        // absent number must never be replaced by a plausible one).
        'cycleCount': null,
      },
    );
  }

  /// Runs the full pipeline and returns the artifact as a JSON-shaped map.
  ///
  /// Throws what [ReferenceBuilder.build] throws — refusals are the point,
  /// so the CLI surfaces them instead of catching them.
  Map<String, dynamic> buildArtifact({
    required String technique,
    required Map<String, Fixture> fixturesById,
    Map<String, bool>? leadSidePrior,
  }) {
    final List<ReferenceTake> takes = <ReferenceTake>[];
    final List<Map<String, dynamic>> takeReports = <Map<String, dynamic>>[];
    final List<String> excludedIneligible = <String>[];
    final List<String> excludedUnattested = <String>[];
    final List<String> excludedNoFrames = <String>[];
    bool provisional = false;
    for (final MapEntry<String, Fixture> e in fixturesById.entries) {
      final TakeEligibility elig = eligibilityOf(e.value);
      if (elig == TakeEligibility.ineligible) {
        excludedIneligible.add(e.key);
        continue;
      }
      if (elig == TakeEligibility.unattested && !allowUnattested) {
        excludedUnattested.add(e.key);
        continue;
      }
      final ({ReferenceTake take, Map<String, dynamic> report}) p =
          prepareTake(e.key, e.value);
      p.report['eligibility'] = elig.name;
      // A take whose every frame was undetected or gate-dropped has nothing
      // to align — passing it on used to crash deep in consensus math and
      // read as a gate refusal (L-143). It is excluded HERE, by name, with
      // its reason carried in the take report (frames/undetected/gateDropped
      // counts), and still listed among the takes so the artifact shows it
      // existed and why it contributed nothing.
      if (p.take.frames.isEmpty) {
        excludedNoFrames.add(e.key);
        p.report['excluded'] = 'noMeasurableFrames';
        takeReports.add(p.report);
        continue;
      }
      if (elig == TakeEligibility.unattested) provisional = true;
      takes.add(p.take);
      takeReports.add(p.report);
    }

    // Refuse BEFORE the builder when exclusions thinned the pool below the
    // gates: the builder's generic count message cannot say WHY the pool
    // shrank — this layer knows, so this layer names it (L-143 discipline:
    // a refusal carries names and reasons, a crash is never a refusal).
    final int distinctSources =
        takes.map((ReferenceTake t) => t.source).toSet().length;
    if (takes.length < builder.minTakes || distinctSources < builder.minSources) {
      throw ArgumentError(
        'pool thinned below gates: ${fixturesById.length} fixture(s) → '
        '${takes.length} usable take(s) from $distinctSources source(s) '
        '(need ${builder.minTakes} takes / ${builder.minSources} sources). '
        'Excluded — ineligible: '
        '${excludedIneligible.isEmpty ? 'none' : excludedIneligible.join(', ')}'
        '; unattested: '
        '${excludedUnattested.isEmpty ? 'none' : excludedUnattested.join(', ')}'
        '${excludedUnattested.isNotEmpty && !allowUnattested ? ' (--allow-unattested admits them, artifact becomes PROVISIONAL)' : ''}'
        '; no measurable frames: '
        '${excludedNoFrames.isEmpty ? 'none' : excludedNoFrames.join(', ')}',
      );
    }

    final CanonicalReference ref = builder.build(
      takes,
      leadSidePrior: leadSidePrior,
      clusterToleranceDeg: clusterToleranceDeg,
    );

    final List<String> jointIds =
        ref.frames.first.specs.map((JointSpec s) => s.id).toList();
    final Map<String, double> floorShare = ref.floorBoundShare();
    double meanAgreement = 0;
    for (int f = 0; f < ref.length; f++) {
      meanAgreement += ref.agreementAt(f);
    }
    meanAgreement /= ref.length;

    // Per joint: dominant tolerance source across frames — the claim a
    // consumer is allowed to make (G-050/M-F-55).
    final Map<String, String> toleranceSource = <String, String>{
      for (int j = 0; j < jointIds.length; j++)
        jointIds[j]: (floorShare[jointIds[j]] ?? 1.0) > 0.5
            ? 'floor'
            : 'variance',
    };

    return <String, dynamic>{
      'schema': 'motion-core/reference@1',
      'technique': technique,
      // A number's standing, not just its value (M-O-29): PROVISIONAL means
      // unattested sources were admitted under an explicit flag — the
      // tolerances exist but may not close variance-derived claims.
      'measurementProvenance': provisional ? 'PROVISIONAL' : 'ATTESTED',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'gates': <String, dynamic>{
        'minTakes': builder.minTakes,
        'minSources': builder.minSources,
        'clusterToleranceDeg': clusterToleranceDeg,
        'minVisibleShare': minVisibleShare,
      },
      'takes': takeReports,
      'result': <String, dynamic>{
        'contributingTakes': ref.contributingTakes,
        'sources': ref.sources,
        'distinctSources': ref.sources.toSet().length,
        'mirroredTakeIds': ref.mirroredTakeIds,
        'mirrorConfident': ref.mirrorConfident,
        'mirrorGapMeasured': ref.mirrorGapMeasured,
        'excludedOutlierIds': ref.excludedOutlierIds,
        'excludedIneligibleIds': excludedIneligible,
        'excludedUnattestedIds': excludedUnattested,
        'excludedNoMeasurableFrameIds': excludedNoFrames,
        'priorDisagreements': ref.priorDisagreements,
        'length': ref.length,
        'meanAgreement': meanAgreement,
        'unreliableJoints': ref.unreliableJoints(),
      },
      'tolerance': <String, dynamic>{
        'perJointSource': toleranceSource,
        'floorBoundShare': floorShare,
        'params': <String, double>{
          'freeFloorDeg': 8,
          'freeCeilingDeg': 45,
          'zeroMultiplier': 3.2,
        },
      },
      'joints': jointIds,
      'frames': <String, dynamic>{
        'meanRad': <List<double>>[
          for (int f = 0; f < ref.length; f++)
            <double>[for (int j = 0; j < jointIds.length; j++) ref.frames[f][j]],
        ],
        'dispersionRad': ref.dispersion,
      },
    };
  }
}
