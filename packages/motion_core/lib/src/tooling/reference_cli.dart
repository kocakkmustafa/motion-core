import '../fixture/fixture.dart';
import '../geometry/joint_angles.dart';
import '../geometry/normalization.dart';
import '../pose/confidence_gate.dart';
import '../pose/pose_frame.dart';
import '../scoring/cycle_aligner.dart';
import '../scoring/dtw.dart';
import '../scoring/cycle_segmentation.dart';
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
///  3. Cycle segmentation (L-139 / 0.8.0) — periodic takes are reduced to
///     one phase-aligned repetition each, so consensus compares rep against
///     rep instead of bending different rep counts onto each other; static
///     material is declared `notApplied` and passes through whole.
///  4. minTakes / minSources / M-F-47 agreement — inside [ReferenceBuilder].
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
    this.segmentCycles = true,
    this.periodEstimator = const CyclePeriodEstimator(),
    this.cycleAligner = const CycleAligner(),
  });

  /// Cycle segmentation (L-139 / 0.8.0): reduce each periodic take to one
  /// phase-aligned repetition before consensus, instead of whole-video DTW —
  /// which, on takes with different rep counts, bends cycle boundaries to
  /// make the lengths meet (4 reps warped onto 9) and reports the bending
  /// as 34-43° of instructor "disagreement".
  ///
  /// Honest fallbacks, in order: material where no take repeats (a static
  /// stance) is declared `notApplied` and flows through the whole-take path
  /// unchanged; an aperiodic take inside a periodic pool is excluded BY
  /// NAME with its reason; a take whose phase cannot be resolved likewise.
  final bool segmentCycles;

  final CyclePeriodEstimator periodEstimator;

  /// Cross-take phase search. Cycles cut from the SAME take share a phase by
  /// construction, so intra-take comparisons use fixed endpoints; across
  /// takes, phase comes from this aligner — never from file order.
  final CycleAligner cycleAligner;

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

    // ---- Cycle segmentation (L-139 / 0.8.0) -------------------------------
    final Map<String, String> excludedUnalignable = <String, String>{};
    String segmentationState = 'notApplied';
    String segmentationReason =
        segmentCycles ? 'fewer than two usable takes' : 'disabled by caller';
    List<ReferenceTake> usable = takes;
    if (segmentCycles && takes.length >= 2) {
      final Map<String, Map<String, dynamic>> reportById =
          <String, Map<String, dynamic>>{
        for (final Map<String, dynamic> r in takeReports) r['id'] as String: r,
      };
      final Map<String, CyclePeriodEstimate> periods =
          <String, CyclePeriodEstimate>{
        for (final ReferenceTake t in takes)
          t.id: periodEstimator.estimate(t.frames),
      };
      for (final ReferenceTake t in takes) {
        final CyclePeriodEstimate p = periods[t.id]!;
        final Map<String, dynamic> rep = reportById[t.id]!;
        if (p.measured) {
          rep['periodFrames'] = p.periodFrames;
          rep['periodicity'] =
              double.parse(p.periodicity.toStringAsFixed(4));
          // A real count at last — until now this field was honestly null
          // (Choreia's thinEvidence lesson).
          rep['cycleCount'] = t.frames.length ~/ p.periodFrames;
        } else {
          rep['periodUnmeasured'] = p.reason;
        }
      }
      final List<ReferenceTake> periodic = <ReferenceTake>[
        for (final ReferenceTake t in takes)
          if (periods[t.id]!.measured) t,
      ];
      if (periodic.isEmpty) {
        segmentationReason = 'no take shows periodic structure — material '
            'treated as non-cyclic (a static hold is the expected case)';
      } else if (periodic.length * 2 <= takes.length) {
        segmentationReason = 'periodic takes are a minority '
            '(${periodic.length}/${takes.length}) — material treated as '
            'non-cyclic; the periodic minority is left to the agreement gate';
      } else {
        // Majority periodic: the aperiodic minority cannot be phase-aligned
        // against repeating material — excluded by name, never averaged in.
        for (final ReferenceTake t in takes) {
          if (!periods[t.id]!.measured) {
            excludedUnalignable[t.id] =
                'aperiodic in a periodic pool: ${periods[t.id]!.reason}';
            reportById[t.id]!['excluded'] = 'unalignable';
          }
        }
        // Anchor: the medoid take among the periodic ones; its representative
        // cycle is its own cycle-medoid. Cycles cut from one take at its own
        // period share a phase by construction, so fixed endpoints are
        // correct for the intra-take comparison.
        final ReferenceTake anchor =
            periodic[builder.selectMedoid(periodic)];
        final int anchorP = periods[anchor.id]!.periodFrames;
        final int anchorCycles = anchor.frames.length ~/ anchorP;
        int bestCycle = 0;
        double bestCost = double.infinity;
        for (int k = 0; k < anchorCycles; k++) {
          final List<JointAngleVector> a =
              anchor.frames.sublist(k * anchorP, (k + 1) * anchorP);
          double total = 0;
          for (int m = 0; m < anchorCycles; m++) {
            if (m == k) continue;
            final List<JointAngleVector> b =
                anchor.frames.sublist(m * anchorP, (m + 1) * anchorP);
            total += cycleAligner.dtw
                .align(
                    a.length,
                    b.length,
                    (int i, int j) =>
                        builder.similarity.distance(a[i], b[j]),
                    dtUs: Dtw.medianDtUs(
                        <int>[for (final JointAngleVector f in b) f.tUs]))
                .normalizedCost;
          }
          if (total < bestCost) {
            bestCost = total;
            bestCycle = k;
          }
        }
        final int anchorStart = bestCycle * anchorP;

        final List<ReferenceTake> reduced = <ReferenceTake>[];
        for (final ReferenceTake t in periodic) {
          final Map<String, dynamic> rep = reportById[t.id]!;
          if (identical(t, anchor)) {
            rep['cycleAnchor'] = true;
            rep['cycleStartFrame'] = anchorStart;
            reduced.add(ReferenceTake(
              id: t.id,
              source: t.source,
              frames: anchor.frames.sublist(anchorStart, anchorStart + anchorP),
            ));
            continue;
          }
          final int p = periods[t.id]!.periodFrames;
          final CycleAlignment al = cycleAligner.align(
            refStart: anchorStart,
            refPeriod: anchorP,
            learnerLen: t.frames.length,
            learnerPeriod: p,
            cost: (int i, int j) =>
                builder.similarity.distance(anchor.frames[i], t.frames[j]),
            dtUs: Dtw.medianDtUs(
                <int>[for (final JointAngleVector f in t.frames) f.tUs]),
          );
          if (!al.resolved) {
            excludedUnalignable[t.id] = al.reason;
            rep['excluded'] = 'unalignable';
            continue;
          }
          rep['cycleStartFrame'] = al.phaseOffset;
          rep['phaseMargin'] =
              double.parse(al.phaseMargin.toStringAsFixed(4));
          rep['cycleAlignCost'] =
              double.parse(al.normalizedCost.toStringAsFixed(4));
          if (al.secondCycleCost != null) {
            // Reported, not gated: a divergence threshold here would be an
            // unmeasured limit, and unmeasured limits do not gate (M-F-63).
            rep['secondCycleCost'] =
                double.parse(al.secondCycleCost!.toStringAsFixed(4));
          }
          reduced.add(ReferenceTake(
            id: t.id,
            source: t.source,
            frames: t.frames.sublist(al.phaseOffset, al.phaseOffset + p),
          ));
        }
        usable = reduced;
        segmentationState = 'applied';
        segmentationReason = 'ok';
      }
    }

    // Refuse BEFORE the builder when EXCLUSIONS thinned the pool below the
    // gates: the builder's generic count message cannot say WHY the pool
    // shrank — this layer knows, so this layer names it (L-143 discipline:
    // a refusal carries names and reasons, a crash is never a refusal).
    // Only when something was actually excluded, though: with nothing
    // excluded, "pool thinned" would be false and this message would shadow
    // the builder's more specific ones (the M-F-38 rationale and its
    // single-teacher escape hatch live there — review finding HIGH-2).
    final bool anyExcluded = excludedIneligible.isNotEmpty ||
        excludedUnattested.isNotEmpty ||
        excludedNoFrames.isNotEmpty ||
        excludedUnalignable.isNotEmpty;
    final int distinctSources =
        usable.map((ReferenceTake t) => t.source).toSet().length;
    if (anyExcluded &&
        (usable.length < builder.minTakes ||
            distinctSources < builder.minSources)) {
      throw ArgumentError(
        'pool thinned below gates: ${fixturesById.length} fixture(s) → '
        '${usable.length} usable take(s) from $distinctSources source(s) '
        '(need ${builder.minTakes} takes / ${builder.minSources} sources). '
        'Excluded — ineligible: '
        '${excludedIneligible.isEmpty ? 'none' : excludedIneligible.join(', ')}'
        '; unattested: '
        '${excludedUnattested.isEmpty ? 'none' : excludedUnattested.join(', ')}'
        '${excludedUnattested.isNotEmpty && !allowUnattested ? ' (--allow-unattested admits them, artifact becomes PROVISIONAL)' : ''}'
        '; no measurable frames: '
        '${excludedNoFrames.isEmpty ? 'none' : excludedNoFrames.join(', ')}'
        '; unalignable: '
        '${excludedUnalignable.isEmpty ? 'none' : excludedUnalignable.entries.map((MapEntry<String, String> e) => '${e.key} (${e.value})').join(', ')}',
      );
    }

    final CanonicalReference ref = builder.build(
      usable,
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
        'cycleSegmentation': segmentCycles,
      },
      // L-139 / 0.8.0: whether takes were reduced to phase-aligned single
      // cycles before consensus. `notApplied` is a declaration, not a
      // failure — static material has no cycles to segment, and pretending
      // otherwise would be the thinEvidence failure inverted.
      'cycleSegmentation': <String, dynamic>{
        'state': segmentationState,
        'reason': segmentationReason,
        'excludedUnalignable': excludedUnalignable,
      },
      'takes': takeReports,
      'result': <String, dynamic>{
        'contributingTakes': ref.contributingTakes,
        'sources': ref.sources,
        'distinctSources': ref.sources.toSet().length,
        'mirroredTakeIds': ref.mirroredTakeIds,
        'mirrorConfident': ref.mirrorConfident,
        'mirrorGapMeasured': ref.mirrorGapMeasured,
        'mirrorSearchDecisive': ref.mirrorSearchDecisive,
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
