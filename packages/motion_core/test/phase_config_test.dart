import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _validConfig() => <String, dynamic>{
      'schemaVersion': '3.0',
      'metrics': <String, dynamic>{
        'extensionRatio': <String, dynamic>{
          'unit': 'ratio',
          'range': <num>[0, 1.2],
          'noiseBand': 0.03,
          'baseline': 0.55,
        },
        'kneeAngle': <String, dynamic>{
          'unit': 'deg',
          'range': <num>[0, 180],
          'noiseBand': 4,
          'baseline': 172,
        },
      },
      'techniques': <dynamic>[
        <String, dynamic>{
          'id': 'jab',
          'limb': 'lead_arm',
          'sideResolution': 'calibrated',
          'phases': <dynamic>[
            <String, dynamic>{
              'id': 'GUARD',
              'enter': <String, dynamic>{
                'kind': 'metric',
                'metric': 'extensionRatio',
                'op': 'lt',
                'value': 0.62,
              },
              'timeoutMs': 4000,
            },
            <String, dynamic>{
              'id': 'EXTENSION',
              'enter': <String, dynamic>{
                'kind': 'all',
                'of': <dynamic>[
                  <String, dynamic>{
                    'kind': 'metric',
                    'metric': 'extensionRatio',
                    'op': 'gt',
                    'value': 0.68,
                  },
                  <String, dynamic>{
                    'kind': 'delta',
                    'metric': 'extensionRatio',
                    'op': 'gt',
                    'valuePerSecond': 0,
                  },
                ],
              },
              'timeoutMs': 400,
            },
            <String, dynamic>{
              'id': 'RECOVERED',
              'enter': <String, dynamic>{
                'kind': 'metric',
                'metric': 'extensionRatio',
                'op': 'lt',
                'value': 0.62,
              },
              'terminal': true,
            },
          ],
          'errors': <dynamic>[
            <String, dynamic>{
              'code': 'KNEE_LOCKED',
              'evaluateAt': <String, dynamic>{'kind': 'periodic', 'everyMs': 2000},
              'condition': <String, dynamic>{
                'kind': 'metric',
                'metric': 'kneeAngle',
                'op': 'gt',
                'value': 175,
              },
              'priority': 'quality',
              'perturbation': <String, dynamic>{
                'metric': 'kneeAngle',
                'targetValue': 180,
              },
            },
          ],
        },
      ],
    };

void main() {
  const PhaseConfigParser parser = PhaseConfigParser();
  const PhaseConfigValidator validator = PhaseConfigValidator();

  group('PhaseConfig parser (sealed schema v3.0)', () {
    test('parses a well-formed config completely', () {
      final PhaseConfig c = parser.parse(_validConfig());
      expect(c.techniques.single.phases, hasLength(3));
      expect(c.techniques.single.sideResolution, SideResolution.calibrated);
      expect(c.techniques.single.errors.single.priority, ErrorPriority.quality);
      expect(validator.validate(c), isEmpty);
    });

    test('unknown fields are hard errors, not warnings (rule 8)', () {
      final Map<String, dynamic> bad = _validConfig();
      (bad['techniques'] as List)[0]['surpriseField'] = 1;
      expect(() => parser.parse(bad),
          throwsA(isA<PhaseConfigError>()
              .having((e) => e.message, 'message', contains('bilinmeyen'))));
    });

    test('a per-frame delta value is rejected at parse time (L-069, P0)', () {
      final Map<String, dynamic> bad = _validConfig();
      final Map<String, dynamic> delta =
          ((bad['techniques'] as List)[0]['phases'] as List)[1]['enter']['of'][1]
              as Map<String, dynamic>;
      delta.remove('valuePerSecond');
      delta['value'] = 1.0; // kare-başına — 60 fps'te sessiz duruş
      expect(() => parser.parse(bad),
          throwsA(isA<PhaseConfigError>()
              .having((e) => e.message, 'message', contains('L-069'))));
    });

    test('a phase marker without phaseId cannot be built (M-J-05.1)', () {
      final Map<String, dynamic> bad = _validConfig();
      ((bad['techniques'] as List)[0]['errors'] as List)[0]['evaluateAt'] =
          <String, dynamic>{'kind': 'phase'};
      expect(() => parser.parse(bad), throwsA(isA<PhaseConfigError>()));
    });

    test('baseline outside the physical range is impossible (M-F-34 + D5)',
        () {
      final Map<String, dynamic> bad = _validConfig();
      (bad['metrics'] as Map<String, dynamic>)['kneeAngle']['baseline'] = 220;
      expect(() => parser.parse(bad), throwsA(isA<PhaseConfigError>()));
    });
  });

  group('PhaseConfig validator (family invariants)', () {
    test('non-terminal phase without timeout is flagged (invariant #1, J-009)',
        () {
      final Map<String, dynamic> bad = _validConfig();
      (((bad['techniques'] as List)[0]['phases'] as List)[0]
              as Map<String, dynamic>)
          .remove('timeoutMs');
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.single, contains('J-009'));
    });

    test('threshold outside physical range is flagged (G-016 — the 206° knee)',
        () {
      final Map<String, dynamic> bad = _validConfig();
      ((bad['techniques'] as List)[0]['errors'] as List)[0]['condition']
          ['value'] = 206;
      // Perturbasyon hedefi de menzil-dışı eşiğe göre saçmalaşır; iki bulgu
      // birden gelebilir — G-016 satırını arıyoruz.
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.join('\n'), contains('G-016'));
    });

    test('overlapping endpoint conditions are flagged (invariant #9, V11)',
        () {
      final Map<String, dynamic> bad = _validConfig();
      // GUARD: < 0.62 · EXTENSION'ı basit koşula indirip > 0.55 yap — örtüşür.
      (((bad['techniques'] as List)[0]['phases'] as List)[1]
          as Map<String, dynamic>)['enter'] = <String, dynamic>{
        'kind': 'metric',
        'metric': 'extensionRatio',
        'op': 'gt',
        'value': 0.55,
      };
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.join('\n'), contains('değişmez #9'));
    });

    test(
        'a perturbation inside the noise band tests nothing and is flagged '
        '(invariant #11, C-011)', () {
      final Map<String, dynamic> bad = _validConfig();
      // Eşik 175, noiseBand 4 → hedef 177 yetersiz (fark 2 < 4).
      ((bad['techniques'] as List)[0]['errors'] as List)[0]['perturbation']
          ['targetValue'] = 177;
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.single, contains('değişmez #11'));
    });

    test('raw LEFT_/RIGHT_ landmarks in a config are banned (M-F-06/D4)', () {
      final Map<String, dynamic> bad = _validConfig();
      (bad['techniques'] as List)[0]['requiredLandmarks'] = <String>[
        'LEFT_WRIST'
      ];
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.single, contains('M-F-06'));
    });

    test('an undefined metric reference is flagged, never silently read', () {
      final Map<String, dynamic> bad = _validConfig();
      (((bad['techniques'] as List)[0]['phases'] as List)[0]
          as Map<String, dynamic>)['enter'] = <String, dynamic>{
        'kind': 'metric',
        'metric': 'ghostMetric',
        'op': 'lt',
        'value': 0.5,
      };
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.join('\n'), contains('ghostMetric'));
    });

    test('cyclic without repCompletedOn is flagged (D1)', () {
      final Map<String, dynamic> bad = _validConfig();
      (bad['techniques'] as List)[0]['cyclic'] = true;
      final List<String> issues = validator.validate(parser.parse(bad));
      expect(issues.single, contains('D1'));
    });
  });

  _round2();
  _round3();
}

// ---------------------------------------------------------------------------
// 0.4.1 — M-O-10 + Gravita boşlukları
// ---------------------------------------------------------------------------

void _round2() {
  const PhaseConfigParser parser = PhaseConfigParser();
  const PhaseConfigValidator validator = PhaseConfigValidator();

  group('0.4.1 reader alignment (M-O-10, Gravita gaps)', () {
    test('verdictGates parse with both effects (M-O-07)', () {
      final Map<String, dynamic> cfg = _validConfig();
      (cfg['techniques'] as List)[0]['verdictGates'] = <dynamic>[
        <String, dynamic>{
          'onEvent': 'onsetDetected',
          'holdMs': 100,
          'effect': 'collectNoVerdict',
        },
        <String, dynamic>{
          'onEvent': 'coachCueStarted',
          'holdMs': 300,
          'effect': 'discardWindow',
        },
      ];
      final PhaseConfig c = parser.parse(cfg);
      expect(c.techniques.single.verdictGates, hasLength(2));
      expect(c.techniques.single.verdictGates[1].effect,
          VerdictGateEffect.discardWindow);
    });

    test('requires.signals keeps op/value — a bare name list loses the '
        'precondition (O-A2)', () {
      final Map<String, dynamic> cfg = _validConfig();
      (cfg['techniques'] as List)[0]['requires'] = <String, dynamic>{
        'signals': <dynamic>[
          <String, dynamic>{'signal': 'snrDb', 'op': 'gte', 'value': 6},
          'midiConnected',
        ],
      };
      final PhaseConfig c = parser.parse(cfg);
      final List<SignalRequirement> reqs = c.techniques.single.requiredSignals;
      expect(reqs, hasLength(2));
      expect(reqs.first.op, CompareOp.gte);
      expect(reqs.first.value, 6);
      expect(reqs.last.op, isNull, reason: 'presence-only requirement');
    });

    test('fastTransition without cutoffHz is a violation, not a doc comment '
        '(Gravita gap #1)', () {
      final Map<String, dynamic> cfg = _validConfig();
      (cfg['metrics'] as Map<String, dynamic>)['extensionRatio']
          ['fastTransition'] = true;
      final List<String> issues = validator.validate(parser.parse(cfg));
      expect(issues.single, contains('J-027'));
    });

    test('an error can carry its coach line (Gravita gap #2)', () {
      final Map<String, dynamic> cfg = _validConfig();
      ((cfg['techniques'] as List)[0]['errors'] as List)[0]['cue'] =
          'cue.knee_locked';
      final PhaseConfig c = parser.parse(cfg);
      expect(c.techniques.single.errors.single.cue, 'cue.knee_locked');
    });

    test('measurementSpace: world is declarable (M-O-08/J-028)', () {
      final Map<String, dynamic> cfg = _validConfig();
      (cfg['metrics'] as Map<String, dynamic>)['kneeAngle']
          ['measurementSpace'] = 'world';
      final PhaseConfig c = parser.parse(cfg);
      expect(c.metrics['kneeAngle']!.measurementSpace, MeasurementSpace.world);
    });
  });
}

void _round3() {
  const PhaseConfigParser parser = PhaseConfigParser();

  group(r'0.4.2 — $-önekli gerekçe anahtarları (M-J-07)', () {
    test(r'$why/$doc her düzeyde yok sayılır — sayı gerekçesini taşır', () {
      final Map<String, dynamic> cfg = _validConfig();
      cfg[r'$why'] = 'kök gerekçe';
      (cfg['techniques'] as List)[0][r'$timeoutWhy'] = 'J-009 ölçümü';
      (((cfg['techniques'] as List)[0]['phases'] as List)[1]
          as Map<String, dynamic>)[r'$derivation'] = 'D2: 128ms medyan';
      final PhaseConfig c = parser.parse(cfg);
      expect(c.techniques.single.phases, hasLength(3));
    });

    test('yazım hatası hâlâ sert hata — katılık zayıflamadı', () {
      final Map<String, dynamic> bad = _validConfig();
      (bad['techniques'] as List)[0]['tiemoutMs'] = 400; // typo
      expect(() => parser.parse(bad), throwsA(isA<PhaseConfigError>()));
    });
  });
}
