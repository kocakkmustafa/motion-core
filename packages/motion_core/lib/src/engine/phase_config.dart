/// The family phase-config contract, sealed 2026-07-29 (M-F-40, 5/5 session
/// approval): `docs/40-FAZ-CONFIG-SEMASI-TASLAK.md`.
///
/// This file is the schema's *canonical reader*: a strict parser plus a
/// validator that enforces the invariants the family paid real measurements
/// to learn. Where this reader and the schema document disagree, the schema
/// wins and this reader is fixed — never the other way around.
///
/// Scope note: this increment is the **model + parser + validator** (the
/// config linter every app can run today). The runtime evaluator that drives
/// `PhaseStateMachine` from these configs is the next increment; apps'
/// existing engines keep running on their own formats until then (M-F-35
/// migration path).
library;

import 'dart:convert';

/// Thrown on any schema violation. Rule 8 (M-J-03): unknown fields and
/// unknown metric references are *hard* errors — a reader that silently
/// skips what it does not expect shows data as absent and manufactures a P0
/// upstream.
final class PhaseConfigError implements Exception {
  PhaseConfigError(this.path, this.message);

  /// JSON-path-ish location of the offence (e.g. `techniques[0].phases[2]`).
  final String path;
  final String message;

  @override
  String toString() => 'PhaseConfigError($path: $message)';
}

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

enum ConditionKind {
  metric,
  delta,
  timeInPhase,
  confidence,
  localMax,
  localMin,
  flag,
  category,
  intervalOverlap,
  all,
  any,
}

enum CompareOp { lt, gt, lte, gte, eq }

sealed class Condition {
  const Condition(this.kind);
  final ConditionKind kind;

  /// Metric ids this condition (transitively) references.
  Iterable<String> get referencedMetrics;
}

final class MetricCondition extends Condition {
  const MetricCondition(this.metric, this.op, this.value)
      : super(ConditionKind.metric);
  final String metric;
  final CompareOp op;
  final double value;
  @override
  Iterable<String> get referencedMetrics => <String>[metric];
}

/// Rate condition. **Per-second only** (L-069/L-070, P0): a per-frame delta
/// threshold is both amplitude- and fps-sensitive — the same movement at
/// 60 fps halves the per-frame value and the phase machine silently stalls.
/// Sign-only deltas (value 0) are frame-rate invariant and always legal.
final class DeltaCondition extends Condition {
  const DeltaCondition(this.metric, this.op, this.valuePerSecond)
      : super(ConditionKind.delta);
  final String metric;
  final CompareOp op;
  final double valuePerSecond;
  @override
  Iterable<String> get referencedMetrics => <String>[metric];
}

final class TimeInPhaseCondition extends Condition {
  const TimeInPhaseCondition(this.op, this.ms)
      : super(ConditionKind.timeInPhase);
  final CompareOp op;
  final double ms;
  @override
  Iterable<String> get referencedMetrics => const <String>[];
}

final class ConfidenceCondition extends Condition {
  const ConfidenceCondition(this.op, this.value)
      : super(ConditionKind.confidence);
  final CompareOp op;
  final double value;
  @override
  Iterable<String> get referencedMetrics => const <String>[];
}

final class LocalExtremumCondition extends Condition {
  const LocalExtremumCondition(this.metric, {required bool isMax})
      : super(isMax ? ConditionKind.localMax : ConditionKind.localMin);
  final String metric;
  @override
  Iterable<String> get referencedMetrics => <String>[metric];
}

final class FlagCondition extends Condition {
  const FlagCondition(this.metric, {required this.expected})
      : super(ConditionKind.flag);
  final String metric;
  final bool expected;
  @override
  Iterable<String> get referencedMetrics => <String>[metric];
}

final class CategoryCondition extends Condition {
  const CategoryCondition(this.metric, this.allowed)
      : super(ConditionKind.category);
  final String metric;
  final List<String> allowed;
  @override
  Iterable<String> get referencedMetrics => <String>[metric];
}

/// O-A1: fusion over *interval* measurements ("bow direction changed AND
/// sound stopped") is interval intersection, never instant equality.
final class IntervalOverlapCondition extends Condition {
  const IntervalOverlapCondition(this.events, {this.minOverlapMs = 0})
      : super(ConditionKind.intervalOverlap);
  final List<String> events;
  final double minOverlapMs;
  @override
  Iterable<String> get referencedMetrics => events;
}

final class CompositeCondition extends Condition {
  const CompositeCondition(this.children, {required bool isAll})
      : super(isAll ? ConditionKind.all : ConditionKind.any);
  final List<Condition> children;
  @override
  Iterable<String> get referencedMetrics =>
      children.expand((Condition c) => c.referencedMetrics);
}

// ---------------------------------------------------------------------------
// Metric dictionary
// ---------------------------------------------------------------------------

/// D5 + M-F-34: every metric carrying thresholds must declare its physical
/// range, its noise band and its perfect-form baseline. "The baseline is
/// assumed zero" means the baseline was never measured (Gravita's flawless
/// plank read 6.5° until it was).
final class MetricSpec {
  const MetricSpec({
    required this.id,
    required this.unit,
    required this.range,
    required this.noiseBand,
    required this.baseline,
    this.baselineRef,
    this.interval = false,
    this.cutoffHz,
    this.measurementSpace = MeasurementSpace.isotropic,
    this.fastTransition = false,
  });

  final String id;
  final String unit;
  final (double, double) range;
  final double noiseBand;

  /// Numeric baseline, or NaN when [baselineRef] carries a dynamic reference
  /// (audio: the expected note — Ostinato adaptation).
  final double baseline;
  final String? baselineRef;

  /// O-A1: values are window-intervals (tStartUs/tEndUs), not instants.
  final bool interval;

  /// Mandatory when [fastTransition] is true (G-V10/J-027): the smoothing
  /// filter is an inseparable part of the threshold. Enforced by the
  /// validator, not by prose (Gravita gap #1: a rule that lives only in a
  /// doc comment binds the reader, never the writer).
  final double? cutoffHz;

  /// M-F-30/M-O-08: which space this metric's math runs in. Metrics over 3D
  /// body axes on habitually-angled subjects must declare `world`.
  final MeasurementSpace measurementSpace;

  /// Marks a metric whose signal transitions faster than the default
  /// smoothing can follow (J-027). Makes the cutoffHz obligation checkable.
  final bool fastTransition;
}

enum MeasurementSpace { world, isotropic, pixel }

// ---------------------------------------------------------------------------
// Phases, techniques, error layer
// ---------------------------------------------------------------------------

final class PhaseSpec {
  const PhaseSpec({
    required this.id,
    required this.enter,
    this.quality = const <String, double>{},
    this.exit,
    this.abort,
    this.abortCode,
    this.timeoutMs,
    this.minDurationMs,
    this.measureHere = false,
    this.terminal = false,
    this.checkpoint = false,
    this.skippableIn = const <String>[],
    this.requiredLandmarks = const <String>[],
    this.requiredSignals = const <SignalRequirement>[],
  });

  final String id;
  final Condition enter;

  /// D2: "did I *enter* this phase" (counting) and "did I do it *well*"
  /// (judgement) are different questions — G-027: an entry condition can be
  /// true without being discriminative.
  final Map<String, double> quality;
  final Condition? exit;
  final Condition? abort;
  final String? abortCode;
  final int? timeoutMs;
  final int? minDurationMs;
  final bool measureHere;
  final bool terminal;

  /// D3: coached, never scored ("blurred phases are checkpoint coaching").
  final bool checkpoint;
  final List<String> skippableIn;
  final List<String> requiredLandmarks;
  final List<SignalRequirement> requiredSignals;
}

enum SideResolution { visible, calibrated, explicit }

enum MarkerKind { phase, combinationEnd, periodic, appEvent }

/// M-J-05.1: the marker vocabulary is declarative — free-text markers would
/// let two apps invent incompatible dictionaries the interpreter can never
/// fire.
final class Marker {
  const Marker.phase(String this.phaseId)
      : kind = MarkerKind.phase,
        everyMs = null,
        event = null;
  const Marker.combinationEnd()
      : kind = MarkerKind.combinationEnd,
        phaseId = null,
        everyMs = null,
        event = null;
  const Marker.periodic(int this.everyMs)
      : kind = MarkerKind.periodic,
        phaseId = null,
        event = null;
  const Marker.appEvent(String this.event)
      : kind = MarkerKind.appEvent,
        phaseId = null,
        everyMs = null;

  final MarkerKind kind;
  final String? phaseId;
  final int? everyMs;
  final String? event;
}

enum ErrorPriority { safety, blocking, quality }

/// O-A3 + M-O-07: event-triggered verdict windows. `collectNoVerdict` =
/// data is valid but aperiodic (bow-change attack window): collect, do not
/// judge. `discardWindow` = data is dirty (coach voice in the mic): do not
/// even collect — archived dirty data looks clean to the next analysis.
enum VerdictGateEffect { collectNoVerdict, discardWindow }

final class VerdictGateSpec {
  const VerdictGateSpec({
    required this.onEvent,
    required this.holdMs,
    required this.effect,
  });
  final String onEvent;
  final int holdMs;
  final VerdictGateEffect effect;
}

/// O-A2 (tam biçim): a signal precondition is a *measurable* requirement
/// (SNR ≥ 6 dB, periodicity ≥ 0.5, MIDI connected) — a bare name list loses
/// the op/value and turns the precondition into prose.
final class SignalRequirement {
  const SignalRequirement({required this.signal, this.op, this.value});
  final String signal;
  final CompareOp? op;
  final double? value;
}

final class ErrorSpec {
  const ErrorSpec({
    required this.code,
    required this.evaluateAt,
    required this.condition,
    required this.priority,
    this.perturbation,
    this.cooldownMs,
    this.maxPerRound,
    this.suppressesJudgement = false,
    this.drillId,
    this.cue,
  });

  final String code;
  final Marker evaluateAt;
  final Condition condition;

  /// F1: when several errors fire together, **safety speaks first** — the
  /// single-correction discipline cannot be built without this field.
  final ErrorPriority priority;

  /// F2: the detection rule and the perturbation that exercises it live in
  /// the same record, so the sentinel can check invariant #11.
  final ({String metric, double targetValue})? perturbation;
  final int? cooldownMs;
  final int? maxPerRound;
  final bool suppressesJudgement;
  final String? drillId;

  /// What the coach *says* when this error wins the correction slot —
  /// an i18n key, not display text. A coached error with nothing to say
  /// either drops silently or lets UI copy drift from the detection rule
  /// (the same drift the generated honesty box exists to kill).
  final String? cue;
}

final class TechniqueSpec {
  const TechniqueSpec({
    required this.id,
    required this.sideResolution,
    required this.phases,
    this.limb,
    this.cyclic = false,
    this.repCompletedOn,
    this.resetBetweenReps = const <String>[],
    this.fallback = false,
    this.requiredLandmarks = const <String>[],
    this.requiredSignals = const <SignalRequirement>[],
    this.verdictGates = const <VerdictGateSpec>[],
    this.errors = const <ErrorSpec>[],
  });

  final String id;
  final String? limb;

  /// D4, mandatory: how abstract side names bind to L/R. Raw `LEFT_*` in a
  /// config is banned (M-F-06).
  final SideResolution sideResolution;
  final bool cyclic;
  final String? repCompletedOn;
  final List<String> resetBetweenReps;
  final List<PhaseSpec> phases;
  final bool fallback;
  final List<String> requiredLandmarks;
  final List<SignalRequirement> requiredSignals;
  final List<VerdictGateSpec> verdictGates;
  final List<ErrorSpec> errors;
}

final class PhaseConfig {
  const PhaseConfig({
    required this.schemaVersion,
    required this.metrics,
    required this.techniques,
  });

  final String schemaVersion;
  final Map<String, MetricSpec> metrics;
  final List<TechniqueSpec> techniques;
}

// ---------------------------------------------------------------------------
// Parser — strict by design
// ---------------------------------------------------------------------------

final class PhaseConfigParser {
  const PhaseConfigParser();

  PhaseConfig parseJson(String source) =>
      parse(jsonDecode(source) as Map<String, dynamic>);

  PhaseConfig parse(Map<String, dynamic> root) {
    _expectKeys(root, 'config',
        required: const {'schemaVersion', 'metrics', 'techniques'},
        optional: const {r'$comment'});

    final Map<String, MetricSpec> metrics = <String, MetricSpec>{};
    final Map<String, dynamic> rawMetrics = _map(root, 'metrics', 'config');
    for (final MapEntry<String, dynamic> e in rawMetrics.entries) {
      metrics[e.key] = _metric(e.key, _castMap(e.value, 'metrics.${e.key}'));
    }

    final List<TechniqueSpec> techniques = <TechniqueSpec>[];
    final List<dynamic> rawTechniques = _list(root, 'techniques', 'config');
    for (int i = 0; i < rawTechniques.length; i++) {
      techniques.add(
          _technique(_castMap(rawTechniques[i], 'techniques[$i]'), i));
    }

    return PhaseConfig(
      schemaVersion: root['schemaVersion'].toString(),
      metrics: metrics,
      techniques: techniques,
    );
  }

  MetricSpec _metric(String id, Map<String, dynamic> m) {
    final String path = 'metrics.$id';
    _expectKeys(m, path,
        required: const {'unit', 'range', 'noiseBand', 'baseline'},
        optional: const {
          'interval', 'cutoffHz', 'measurementSpace', 'fastTransition', r'$doc'
        });
    final List<dynamic> range = _list(m, 'range', path);
    if (range.length != 2) {
      throw PhaseConfigError('$path.range', 'iki değer ister: [min, max]');
    }
    final double lo = _num(range[0], '$path.range[0]');
    final double hi = _num(range[1], '$path.range[1]');
    if (hi <= lo) {
      throw PhaseConfigError('$path.range', 'max ($hi) min ($lo) üstünde olmalı');
    }
    final Object? baseline = m['baseline'];
    double baseValue = double.nan;
    String? baseRef;
    if (baseline is Map) {
      final Map<String, dynamic> b = _castMap(baseline, '$path.baseline');
      _expectKeys(b, '$path.baseline', required: const {'ref'});
      baseRef = b['ref'].toString();
    } else {
      baseValue = _num(baseline, '$path.baseline');
      if (baseValue < lo || baseValue > hi) {
        throw PhaseConfigError('$path.baseline',
            'taban ($baseValue) fiziksel aralık [$lo, $hi] dışında');
      }
    }
    return MetricSpec(
      id: id,
      unit: m['unit'].toString(),
      range: (lo, hi),
      noiseBand: _num(m['noiseBand'], '$path.noiseBand'),
      baseline: baseValue,
      baselineRef: baseRef,
      interval: (m['interval'] as bool?) ?? false,
      cutoffHz:
          m.containsKey('cutoffHz') ? _num(m['cutoffHz'], '$path.cutoffHz') : null,
      measurementSpace: m.containsKey('measurementSpace')
          ? _enumValue(MeasurementSpace.values, m['measurementSpace'],
              '$path.measurementSpace')
          : MeasurementSpace.isotropic,
      fastTransition: (m['fastTransition'] as bool?) ?? false,
    );
  }

  TechniqueSpec _technique(Map<String, dynamic> t, int index) {
    final String path = 'techniques[$index]';
    _expectKeys(t, path, required: const {
      'id',
      'sideResolution',
      'phases',
    }, optional: const {
      'limb',
      'cyclic',
      'repCompletedOn',
      'resetBetweenReps',
      'fallback',
      'requiredLandmarks',
      'requiredSignals',
      'requires',
      'verdictGates',
      'errors',
      r'$doc',
    });

    final List<PhaseSpec> phases = <PhaseSpec>[];
    final List<dynamic> rawPhases = _list(t, 'phases', path);
    for (int i = 0; i < rawPhases.length; i++) {
      phases.add(_phase(_castMap(rawPhases[i], '$path.phases[$i]'),
          '$path.phases[$i]'));
    }

    final List<ErrorSpec> errors = <ErrorSpec>[];
    for (int i = 0; i < (_optList(t, 'errors')?.length ?? 0); i++) {
      errors.add(_error(
          _castMap((t['errors'] as List<dynamic>)[i], '$path.errors[$i]'),
          '$path.errors[$i]'));
    }

    final (List<String> reqLm, List<SignalRequirement> reqSig) =
        _requires(t, path);
    return TechniqueSpec(
      id: t['id'].toString(),
      limb: t['limb']?.toString(),
      sideResolution: _enumValue(
          SideResolution.values, t['sideResolution'], '$path.sideResolution'),
      cyclic: (t['cyclic'] as bool?) ?? false,
      repCompletedOn: t['repCompletedOn']?.toString(),
      resetBetweenReps: _strList(t['resetBetweenReps']),
      phases: phases,
      fallback: (t['fallback'] as bool?) ?? false,
      requiredLandmarks: reqLm,
      requiredSignals: reqSig,
      verdictGates: _verdictGates(t['verdictGates'], '$path.verdictGates'),
      errors: errors,
    );
  }

  PhaseSpec _phase(Map<String, dynamic> p, String path) {
    _expectKeys(p, path, required: const {
      'id',
      'enter',
    }, optional: const {
      'quality',
      'exit',
      'abort',
      'abortCode',
      'timeoutMs',
      'minDurationMs',
      'measureHere',
      'terminal',
      'checkpoint',
      'skippableIn',
      'requiredLandmarks',
      'requiredSignals',
      'requires',
      r'$doc',
    });
    final Map<String, double> quality = <String, double>{};
    if (p['quality'] != null) {
      for (final MapEntry<String, dynamic> e
          in _castMap(p['quality'], '$path.quality').entries) {
        quality[e.key] = _num(e.value, '$path.quality.${e.key}');
      }
    }
    return PhaseSpec(
      id: p['id'].toString(),
      enter: _condition(_castMap(p['enter'], '$path.enter'), '$path.enter'),
      quality: quality,
      exit: p['exit'] == null
          ? null
          : _condition(_castMap(p['exit'], '$path.exit'), '$path.exit'),
      abort: p['abort'] == null
          ? null
          : _condition(_castMap(p['abort'], '$path.abort'), '$path.abort'),
      abortCode: p['abortCode']?.toString(),
      timeoutMs: (p['timeoutMs'] as num?)?.toInt(),
      minDurationMs: (p['minDurationMs'] as num?)?.toInt(),
      measureHere: (p['measureHere'] as bool?) ?? false,
      terminal: (p['terminal'] as bool?) ?? false,
      checkpoint: (p['checkpoint'] as bool?) ?? false,
      skippableIn: _strList(p['skippableIn']),
      requiredLandmarks: _requires(p, path).$1,
      requiredSignals: _requires(p, path).$2,
    );
  }

  ErrorSpec _error(Map<String, dynamic> e, String path) {
    _expectKeys(e, path, required: const {
      'code',
      'evaluateAt',
      'condition',
      'priority',
    }, optional: const {
      'perturbation',
      'cooldownMs',
      'maxPerRound',
      'suppressesJudgement',
      'drillId',
      'cue',
      r'$doc',
    });
    ({String metric, double targetValue})? perturbation;
    if (e['perturbation'] != null) {
      final Map<String, dynamic> pt =
          _castMap(e['perturbation'], '$path.perturbation');
      _expectKeys(pt, '$path.perturbation',
          required: const {'metric', 'targetValue'});
      perturbation = (
        metric: pt['metric'].toString(),
        targetValue: _num(pt['targetValue'], '$path.perturbation.targetValue'),
      );
    }
    return ErrorSpec(
      code: e['code'].toString(),
      evaluateAt:
          _marker(_castMap(e['evaluateAt'], '$path.evaluateAt'), '$path.evaluateAt'),
      condition:
          _condition(_castMap(e['condition'], '$path.condition'), '$path.condition'),
      priority:
          _enumValue(ErrorPriority.values, e['priority'], '$path.priority'),
      perturbation: perturbation,
      cooldownMs: (e['cooldownMs'] as num?)?.toInt(),
      maxPerRound: (e['maxPerRound'] as num?)?.toInt(),
      suppressesJudgement: (e['suppressesJudgement'] as bool?) ?? false,
      drillId: e['drillId']?.toString(),
      cue: e['cue']?.toString(),
    );
  }

  List<SignalRequirement> _signalReqs(Object? v, String path) {
    if (v == null) return const <SignalRequirement>[];
    final List<SignalRequirement> out = <SignalRequirement>[];
    final List<dynamic> raw = v as List<dynamic>;
    for (int i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is String) {
        out.add(SignalRequirement(signal: item));
      } else {
        final Map<String, dynamic> m = _castMap(item, '$path[$i]');
        _expectKeys(m, '$path[$i]',
            required: const {'signal'}, optional: const {'op', 'value'});
        out.add(SignalRequirement(
          signal: m['signal'].toString(),
          op: m.containsKey('op')
              ? _enumValue(CompareOp.values, m['op'], '$path[$i].op')
              : null,
          value: m.containsKey('value')
              ? _num(m['value'], '$path[$i].value')
              : null,
        ));
      }
    }
    return out;
  }

  (List<String>, List<SignalRequirement>) _requires(
      Map<String, dynamic> owner, String path) {
    List<String> landmarks = _strList(owner['requiredLandmarks']);
    List<SignalRequirement> signals =
        _signalReqs(owner['requiredSignals'], '$path.requiredSignals');
    if (owner['requires'] != null) {
      final Map<String, dynamic> r = _castMap(owner['requires'], '$path.requires');
      _expectKeys(r, '$path.requires',
          required: const <String>{},
          optional: const {'landmarks', 'signals'});
      landmarks = <String>[...landmarks, ..._strList(r['landmarks'])];
      signals = <SignalRequirement>[
        ...signals,
        ..._signalReqs(r['signals'], '$path.requires.signals'),
      ];
    }
    return (landmarks, signals);
  }

  List<VerdictGateSpec> _verdictGates(Object? v, String path) {
    if (v == null) return const <VerdictGateSpec>[];
    final List<dynamic> raw = v as List<dynamic>;
    final List<VerdictGateSpec> out = <VerdictGateSpec>[];
    for (int i = 0; i < raw.length; i++) {
      final Map<String, dynamic> g = _castMap(raw[i], '$path[$i]');
      _expectKeys(g, '$path[$i]',
          required: const {'onEvent', 'holdMs', 'effect'});
      out.add(VerdictGateSpec(
        onEvent: g['onEvent'].toString(),
        holdMs: (g['holdMs'] as num).toInt(),
        effect: _enumValue(
            VerdictGateEffect.values, g['effect'], '$path[$i].effect'),
      ));
    }
    return out;
  }

  Marker _marker(Map<String, dynamic> m, String path) {
    _expectKeys(m, path,
        required: const {'kind'},
        optional: const {'phaseId', 'everyMs', 'event'});
    final MarkerKind kind = _enumValue(MarkerKind.values, m['kind'], '$path.kind');
    switch (kind) {
      case MarkerKind.phase:
        if (m['phaseId'] == null) {
          throw PhaseConfigError(path, 'phase işareti phaseId ister');
        }
        return Marker.phase(m['phaseId'].toString());
      case MarkerKind.combinationEnd:
        return const Marker.combinationEnd();
      case MarkerKind.periodic:
        if (m['everyMs'] == null) {
          throw PhaseConfigError(path, 'periodic işareti everyMs ister');
        }
        return Marker.periodic((m['everyMs'] as num).toInt());
      case MarkerKind.appEvent:
        if (m['event'] == null) {
          throw PhaseConfigError(path, 'appEvent işareti event ister');
        }
        return Marker.appEvent(m['event'].toString());
    }
  }

  Condition _condition(Map<String, dynamic> c, String path) {
    _expectKeys(c, path, required: const {
      'kind'
    }, optional: const {
      'metric', 'op', 'value', 'valuePerSecond', 'ms', 'is', 'in',
      'of', 'minOverlapMs', r'$doc',
    });
    final ConditionKind kind =
        _enumValue(ConditionKind.values, c['kind'], '$path.kind');
    switch (kind) {
      case ConditionKind.metric:
        return MetricCondition(
          c['metric'].toString(),
          _enumValue(CompareOp.values, c['op'], '$path.op'),
          _num(c['value'], '$path.value'),
        );
      case ConditionKind.delta:
        if (c.containsKey('value')) {
          // L-069 (P0): the presence of a per-frame field is itself the bug.
          throw PhaseConfigError(path,
              "delta koşulu 'value' alamaz — birim SANİYE-başınadır "
              "('valuePerSecond'); kare-başına eşik fps değişince faz "
              'makinesini sessizce durdurur (L-069)');
        }
        return DeltaCondition(
          c['metric'].toString(),
          _enumValue(CompareOp.values, c['op'], '$path.op'),
          _num(c['valuePerSecond'], '$path.valuePerSecond'),
        );
      case ConditionKind.timeInPhase:
        return TimeInPhaseCondition(
            _enumValue(CompareOp.values, c['op'], '$path.op'),
            _num(c['ms'], '$path.ms'));
      case ConditionKind.confidence:
        return ConfidenceCondition(
            _enumValue(CompareOp.values, c['op'], '$path.op'),
            _num(c['value'], '$path.value'));
      case ConditionKind.localMax:
        return LocalExtremumCondition(c['metric'].toString(), isMax: true);
      case ConditionKind.localMin:
        return LocalExtremumCondition(c['metric'].toString(), isMax: false);
      case ConditionKind.flag:
        return FlagCondition(c['metric'].toString(), expected: c['is'] as bool);
      case ConditionKind.category:
        return CategoryCondition(c['metric'].toString(), _strList(c['in']));
      case ConditionKind.intervalOverlap:
        return IntervalOverlapCondition(_strList(c['of']),
            minOverlapMs: c.containsKey('minOverlapMs')
                ? _num(c['minOverlapMs'], '$path.minOverlapMs')
                : 0);
      case ConditionKind.all:
      case ConditionKind.any:
        final List<dynamic> of = _list(c, 'of', path);
        return CompositeCondition(
          <Condition>[
            for (int i = 0; i < of.length; i++)
              _condition(_castMap(of[i], '$path.of[$i]'), '$path.of[$i]'),
          ],
          isAll: kind == ConditionKind.all,
        );
    }
  }

  // -- primitives ----------------------------------------------------------

  void _expectKeys(Map<String, dynamic> m, String path,
      {required Set<String> required, Set<String> optional = const {}}) {
    for (final String k in required) {
      if (!m.containsKey(k)) {
        throw PhaseConfigError(path, "zorunlu alan eksik: '$k'");
      }
    }
    for (final String k in m.keys) {
      if (!required.contains(k) && !optional.contains(k)) {
        throw PhaseConfigError(
            path, "bilinmeyen alan: '$k' (sessiz yutma yok — kural 8)");
      }
    }
  }

  Map<String, dynamic> _castMap(Object? v, String path) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    throw PhaseConfigError(path, 'nesne bekleniyordu, ${v.runtimeType} geldi');
  }

  Map<String, dynamic> _map(Map<String, dynamic> m, String k, String path) =>
      _castMap(m[k], '$path.$k');

  List<dynamic> _list(Map<String, dynamic> m, String k, String path) {
    final Object? v = m[k];
    if (v is List) return v;
    throw PhaseConfigError('$path.$k', 'liste bekleniyordu');
  }

  List<dynamic>? _optList(Map<String, dynamic> m, String k) =>
      m[k] == null ? null : m[k] as List<dynamic>;

  List<String> _strList(Object? v) =>
      v == null ? const <String>[] : (v as List).map((e) => e.toString()).toList();

  double _num(Object? v, String path) {
    if (v is num) return v.toDouble();
    throw PhaseConfigError(path, 'sayı bekleniyordu, ${v.runtimeType} geldi');
  }

  T _enumValue<T extends Enum>(List<T> values, Object? v, String path) {
    final String s = v.toString();
    for (final T e in values) {
      if (e.name == s) return e;
    }
    throw PhaseConfigError(
        path, "geçersiz değer '$s' (beklenen: ${values.map((e) => e.name).join('|')})");
  }
}

// ---------------------------------------------------------------------------
// Validator — where the family's paid-for lessons are enforced
// ---------------------------------------------------------------------------

final class PhaseConfigValidator {
  const PhaseConfigValidator();

  /// Returns every violation (empty = valid). Each message names its rule so
  /// a red CI line teaches the reader which measured lesson it protects.
  List<String> validate(PhaseConfig config) {
    final List<String> issues = <String>[];

    // Gravita gap #1: a rule that lives only in a doc comment binds the
    // reader, never the writer. fastTransition => cutoffHz, enforced.
    for (final MetricSpec m in config.metrics.values) {
      if (m.fastTransition && m.cutoffHz == null) {
        issues.add('metric ${m.id}: fastTransition metrik cutoffHz beyan '
            'etmeli — filtre eşiğin ayrılmaz parçasıdır (J-027/G-V10)');
      }
    }

    for (final TechniqueSpec t in config.techniques) {
      final String tp = 'technique ${t.id}';

      // Invariant #1: every non-terminal phase must carry a timeout (J-009:
      // without it, "extend and hold" was counted as a 736 ms punch).
      for (final PhaseSpec p in t.phases) {
        if (!p.terminal && p.timeoutMs == null) {
          issues.add('$tp/${p.id}: terminal olmayan fazda timeoutMs ZORUNLU '
              '(değişmez #1, J-009)');
        }
      }

      // D1: a cyclic technique must say which transition completes a rep and
      // what resets — otherwise rep 2 inherits rep 1's extremes.
      if (t.cyclic && t.repCompletedOn == null) {
        issues.add('$tp: cyclic teknik repCompletedOn beyan etmeli (D1)');
      }

      // M-F-06 / D4: raw side-labelled landmarks are banned in configs.
      for (final String lm in <String>[
        ...t.requiredLandmarks,
        for (final PhaseSpec p in t.phases) ...p.requiredLandmarks,
      ]) {
        if (lm.startsWith('LEFT_') || lm.startsWith('RIGHT_')) {
          issues.add("$tp: config'te ham taraf etiketi yasak ('$lm') — "
              'soyut ad + sideResolution kullanılır (M-F-06/D4)');
        }
      }

      // Rule 8: every referenced metric must exist in the dictionary.
      final Iterable<(String, Condition)> conditions = <(String, Condition)>[
        for (final PhaseSpec p in t.phases) ...[
          ('$tp/${p.id}.enter', p.enter),
          if (p.exit != null) ('$tp/${p.id}.exit', p.exit!),
          if (p.abort != null) ('$tp/${p.id}.abort', p.abort!),
        ],
        for (final ErrorSpec e in t.errors) ('$tp/error ${e.code}', e.condition),
      ];
      for (final (String where, Condition c) in conditions) {
        if (c.kind == ConditionKind.intervalOverlap) continue; // event refs
        for (final String m in c.referencedMetrics) {
          if (!config.metrics.containsKey(m)) {
            issues.add("$where: tanımsız metrik '$m' — tanımsız metriğe eşik "
                'yazılamaz (Gravita metrik sözlüğü kuralı)');
          }
        }
      }
      for (final PhaseSpec p in t.phases) {
        for (final String m in p.quality.keys) {
          if (!config.metrics.containsKey(m)) {
            issues.add("$tp/${p.id}.quality: tanımsız metrik '$m'");
          }
        }
      }

      // G-016: thresholds must sit inside the metric's physical range.
      void checkRange(String where, Condition c) {
        if (c is MetricCondition) {
          final MetricSpec? spec = config.metrics[c.metric];
          if (spec != null &&
              (c.value < spec.range.$1 || c.value > spec.range.$2)) {
            issues.add('$where: eşik ${c.value} fiziksel aralık '
                '[${spec.range.$1}, ${spec.range.$2}] dışında (G-016 — '
                '206° diz sınıfı)');
          }
        } else if (c is CompositeCondition) {
          for (final Condition child in c.children) {
            checkRange(where, child);
          }
        }
      }

      for (final (String where, Condition c) in conditions) {
        checkRange(where, c);
      }

      // Invariant #9 (Gravita V11): opposing endpoint conditions on the same
      // metric must not overlap — otherwise a frame satisfies both ends and
      // the engine mints reps forever.
      final List<(String, MetricCondition)> simpleEnters =
          <(String, MetricCondition)>[
        for (final PhaseSpec p in t.phases)
          if (p.enter is MetricCondition) (p.id, p.enter as MetricCondition),
      ];
      for (int i = 0; i < simpleEnters.length; i++) {
        for (int j = i + 1; j < simpleEnters.length; j++) {
          final (String pa, MetricCondition a) = simpleEnters[i];
          final (String pb, MetricCondition b) = simpleEnters[j];
          if (a.metric != b.metric) continue;
          final bool aLow = a.op == CompareOp.lt || a.op == CompareOp.lte;
          final bool bLow = b.op == CompareOp.lt || b.op == CompareOp.lte;
          if (aLow == bLow) continue; // same direction — not endpoints
          final MetricCondition low = aLow ? a : b;
          final MetricCondition high = aLow ? b : a;
          if (low.value >= high.value) {
            issues.add('$tp: $pa/$pb uç koşulları örtüşüyor '
                '(${a.metric}: <${low.value} ile >${high.value}) — her kare '
                'iki uçta birden sayılır (değişmez #9, Gravita V11)');
          }
        }
      }

      // Invariant #11 (F2): a perturbation must clear its own detection
      // threshold by at least the metric's noise band, or the fixture tests
      // nothing (C-011).
      for (final ErrorSpec e in t.errors) {
        final ({String metric, double targetValue})? pt = e.perturbation;
        if (pt == null) continue;
        final MetricSpec? spec = config.metrics[pt.metric];
        if (spec == null) {
          issues.add('$tp/error ${e.code}: perturbation tanımsız metrik '
              "'${pt.metric}' hedefliyor");
          continue;
        }
        final double? threshold = _thresholdFor(e.condition, pt.metric);
        if (threshold != null &&
            (pt.targetValue - threshold).abs() < spec.noiseBand) {
          issues.add('$tp/error ${e.code}: perturbation hedefi '
              '(${pt.targetValue}) eşiği ($threshold) en az noiseBand '
              '(${spec.noiseBand}) kadar aşmalı (değişmez #11, C-011)');
        }
      }
    }

    return issues;
  }

  double? _thresholdFor(Condition c, String metric) {
    if (c is MetricCondition && c.metric == metric) return c.value;
    if (c is CompositeCondition) {
      for (final Condition child in c.children) {
        final double? t = _thresholdFor(child, metric);
        if (t != null) return t;
      }
    }
    return null;
  }
}
