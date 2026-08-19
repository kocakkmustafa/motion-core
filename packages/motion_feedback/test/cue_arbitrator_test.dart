import 'package:flutter_test/flutter_test.dart';
import 'package:motion_feedback/motion_feedback.dart';

class _FixedClock implements Clock {
  _FixedClock(this._t);
  DateTime _t;

  @override
  DateTime now() => _t;

  void advance(Duration d) => _t = _t.add(d);
}

const _validCue = Cue(
  id: 'c1',
  priority: CuePriority.medium,
  category: CueCategory.form,
  audioAssetRef: 'cue.form.raise_arm',
  haptic: HapticPattern.light,
  cooldown: Duration(seconds: 2),
);

void main() {
  group('CueArbitrator — one-correction-at-a-time policy', () {
    test('accepts the first valid cue and exposes it as the active cue', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      expect(arbitrator.offer(_validCue), isTrue);
      expect(arbitrator.activeCue, same(_validCue));
    });

    test('rejects a same-priority cue while the active cue has not expired', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      arbitrator.offer(_validCue);
      const rival = Cue(
        id: 'c2',
        priority: CuePriority.medium,
        category: CueCategory.tempo,
        audioAssetRef: 'cue.tempo.slow_down',
        haptic: HapticPattern.light,
        cooldown: Duration(seconds: 2),
      );
      expect(arbitrator.offer(rival), isFalse);
      expect(arbitrator.activeCue, same(_validCue));
    });

    test('rejects a lower-priority cue while the active cue has not expired', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      const active = Cue(
        id: 'c1',
        priority: CuePriority.high,
        category: CueCategory.form,
        audioAssetRef: 'cue.form.a',
        haptic: HapticPattern.light,
        cooldown: Duration(seconds: 2),
      );
      arbitrator.offer(active);
      const lower = Cue(
        id: 'c2',
        priority: CuePriority.low,
        category: CueCategory.encouragement,
        audioAssetRef: 'cue.encouragement.a',
        haptic: HapticPattern.none,
        cooldown: Duration(seconds: 1),
      );
      expect(arbitrator.offer(lower), isFalse);
      expect(arbitrator.activeCue, same(active));
    });

    test('accepts a strictly higher-priority cue and interrupts the active one', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      arbitrator.offer(_validCue); // medium
      const urgent = Cue(
        id: 'c2',
        priority: CuePriority.critical,
        category: CueCategory.safety,
        audioAssetRef: 'cue.safety.stop',
        haptic: HapticPattern.warning,
        cooldown: Duration(seconds: 1),
      );
      expect(arbitrator.offer(urgent), isTrue);
      expect(arbitrator.activeCue, same(urgent));
    });

    test('accepts a new cue once the previous cooldown has fully elapsed', () {
      final clock = _FixedClock(DateTime(2026));
      final arbitrator = CueArbitrator(clock: clock);
      arbitrator.offer(_validCue);
      clock.advance(const Duration(seconds: 2));
      const next = Cue(
        id: 'c2',
        priority: CuePriority.medium,
        category: CueCategory.tempo,
        audioAssetRef: 'cue.tempo.slow_down',
        haptic: HapticPattern.light,
        cooldown: Duration(seconds: 2),
      );
      expect(arbitrator.offer(next), isTrue);
      expect(arbitrator.activeCue, same(next));
    });

    test('fail-closed: rejects a cue with an empty audioAssetRef without throwing', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      const malformed = Cue(
        id: 'c1',
        priority: CuePriority.critical,
        category: CueCategory.safety,
        audioAssetRef: '',
        haptic: HapticPattern.warning,
        cooldown: Duration(seconds: 1),
      );
      expect(() => arbitrator.offer(malformed), returnsNormally);
      expect(arbitrator.offer(malformed), isFalse);
      expect(arbitrator.activeCue, isNull);
    });

    test('fail-closed: rejects a cue with a negative cooldown without throwing', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      const malformed = Cue(
        id: 'c1',
        priority: CuePriority.critical,
        category: CueCategory.safety,
        audioAssetRef: 'cue.safety.stop',
        haptic: HapticPattern.warning,
        cooldown: Duration(seconds: -1),
      );
      expect(arbitrator.offer(malformed), isFalse);
      expect(arbitrator.activeCue, isNull);
    });

    test('fail-closed: rejects a cue with a blank id without throwing', () {
      final arbitrator = CueArbitrator(clock: _FixedClock(DateTime(2026)));
      const malformed = Cue(
        id: '  ',
        priority: CuePriority.critical,
        category: CueCategory.safety,
        audioAssetRef: 'cue.safety.stop',
        haptic: HapticPattern.warning,
        cooldown: Duration(seconds: 1),
      );
      expect(arbitrator.offer(malformed), isFalse);
    });
  });
}
