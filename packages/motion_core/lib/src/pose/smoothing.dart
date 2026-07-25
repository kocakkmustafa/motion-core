import 'dart:math' as math;

import 'landmark_index.dart';
import 'pose_frame.dart';

/// Single-channel low-pass filter used inside [OneEuroFilter].
final class _LowPass {
  double? _prev;

  double filter(double value, double alpha) {
    final double? prev = _prev;
    final double out =
        (prev == null) ? value : alpha * value + (1 - alpha) * prev;
    _prev = out;
    return out;
  }

  double? get last => _prev;

  void reset() => _prev = null;
}

/// One Euro filter — adaptive low-pass smoothing for noisy pose signals.
///
/// Chosen over a fixed EMA for a reason that matters a great deal to Choreia:
/// a fixed filter forces one trade-off for the whole session — smooth but
/// laggy, or responsive but jittery. The One Euro filter raises its cutoff as
/// the signal speeds up, so a held pose is smoothed hard while a fast step
/// keeps almost no lag. Lag on a fast movement is not cosmetic here: it shifts
/// the measured phase timestamps, and phase timestamps are exactly what the
/// beat-alignment score is computed from (family rule D2 — timing comes from
/// phase durations, never from inter-frame pixel speed).
///
/// Reference: Casiez, Roussel & Vogel, "1€ Filter" (CHI 2012).
final class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 1.0,
    this.beta = 0.007,
    this.derivativeCutoff = 1.0,
  });

  /// Cutoff frequency (Hz) at rest. Lower = smoother when still.
  final double minCutoff;

  /// Speed coefficient. Higher = less lag when moving fast.
  final double beta;

  final double derivativeCutoff;

  final _LowPass _value = _LowPass();
  final _LowPass _derivative = _LowPass();
  int? _lastTUs;

  static double _alpha(double cutoff, double dt) {
    final double tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double value, int tUs) {
    final int? lastT = _lastTUs;
    _lastTUs = tUs;

    if (lastT == null) {
      _value.filter(value, 1.0);
      return value;
    }
    final double dt = (tUs - lastT) / 1e6;
    if (dt <= 0) return _value.last ?? value;

    final double prev = _value.last ?? value;
    final double rawDerivative = (value - prev) / dt;
    final double edx =
        _derivative.filter(rawDerivative, _alpha(derivativeCutoff, dt));
    final double cutoff = minCutoff + beta * edx.abs();
    return _value.filter(value, _alpha(cutoff, dt));
  }

  void reset() {
    _value.reset();
    _derivative.reset();
    _lastTUs = null;
  }
}

/// Applies a [OneEuroFilter] independently to every landmark coordinate.
///
/// Visibility is deliberately **not** smoothed: it is a gate input, and
/// smoothing it would let a confidently-tracked past frame prop up a lost
/// current frame — turning "I cannot see it" into a delayed false verdict.
final class PoseSmoother {
  PoseSmoother({
    double minCutoff = 1.0,
    double beta = 0.007,
    double derivativeCutoff = 1.0,
  }) : _filters = List<List<OneEuroFilter>>.generate(
          Lm.count,
          (_) => List<OneEuroFilter>.generate(
            3,
            (_) => OneEuroFilter(
              minCutoff: minCutoff,
              beta: beta,
              derivativeCutoff: derivativeCutoff,
            ),
            growable: false,
          ),
          growable: false,
        );

  final List<List<OneEuroFilter>> _filters;

  PoseFrame smooth(PoseFrame frame) {
    final List<PoseLandmark> out = List<PoseLandmark>.generate(
      Lm.count,
      (int i) {
        final PoseLandmark lm = frame[i];
        return PoseLandmark(
          _filters[i][0].filter(lm.x, frame.tUs),
          _filters[i][1].filter(lm.y, frame.tUs),
          _filters[i][2].filter(lm.z, frame.tUs),
          lm.visibility,
        );
      },
      growable: false,
    );
    return PoseFrame(
      tUs: frame.tUs,
      landmarks: out,
      modelVersion: frame.modelVersion,
    );
  }

  void reset() {
    for (final List<OneEuroFilter> axes in _filters) {
      for (final OneEuroFilter f in axes) {
        f.reset();
      }
    }
  }
}
