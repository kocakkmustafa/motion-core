import 'package:flutter_test/flutter_test.dart';
import 'package:motion_audio/motion_audio.dart';

void main() {
  group('PitchEstimate.midiNote — standard equal-temperament A440', () {
    test('440 Hz resolves to MIDI note 69 (A4)', () {
      const estimate = PitchEstimate(
        frequencyHz: 440,
        confidence: 1,
        timestampMs: 0,
      );
      expect(estimate.midiNote, 69);
    });

    test('220 Hz resolves to MIDI note 57 (A3, one octave down)', () {
      const estimate = PitchEstimate(
        frequencyHz: 220,
        confidence: 1,
        timestampMs: 0,
      );
      expect(estimate.midiNote, 57);
    });

    test('261.63 Hz resolves to MIDI note 60 (middle C)', () {
      const estimate = PitchEstimate(
        frequencyHz: 261.63,
        confidence: 1,
        timestampMs: 0,
      );
      expect(estimate.midiNote, 60);
    });

    test('fail-closed: zero frequency yields no MIDI note', () {
      const estimate = PitchEstimate(
        frequencyHz: 0,
        confidence: 1,
        timestampMs: 0,
      );
      expect(estimate.midiNote, isNull);
    });

    test('fail-closed: negative frequency yields no MIDI note', () {
      const estimate = PitchEstimate(
        frequencyHz: -10,
        confidence: 1,
        timestampMs: 0,
      );
      expect(estimate.midiNote, isNull);
    });

    for (final (String name, double frequency) in <(String, double)>[
      ('NaN', double.nan),
      ('positive infinity', double.infinity),
      ('positive subnormal underflow', double.minPositive),
    ]) {
      test('fail-closed: $name yields no MIDI note', () {
        final estimate = PitchEstimate(
          frequencyHz: frequency,
          confidence: 1,
          timestampMs: 0,
        );
        expect(estimate.midiNote, isNull);
      });
    }
  });

  group('ChordEstimate.isWellFormed', () {
    test('pitch classes within 0-11 are well-formed', () {
      const chord = ChordEstimate(
        pitchClasses: {0, 4, 7},
        confidence: 0.8,
        timestampMs: 0,
      );
      expect(chord.isWellFormed, isTrue);
    });

    test('fail-closed: a pitch class above 11 is not well-formed', () {
      const chord = ChordEstimate(
        pitchClasses: {0, 4, 12},
        confidence: 0.8,
        timestampMs: 0,
      );
      expect(chord.isWellFormed, isFalse);
    });

    test('fail-closed: a negative pitch class is not well-formed', () {
      const chord = ChordEstimate(
        pitchClasses: {-1, 4, 7},
        confidence: 0.8,
        timestampMs: 0,
      );
      expect(chord.isWellFormed, isFalse);
    });

    test('fail-closed: an empty pitch-class set is not well-formed', () {
      const chord = ChordEstimate(
        pitchClasses: {},
        confidence: 0.8,
        timestampMs: 0,
      );
      expect(chord.isWellFormed, isFalse);
    });
  });
}
