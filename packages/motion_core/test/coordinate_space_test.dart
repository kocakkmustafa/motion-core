import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

/// The invariance pattern (Choreia C-061): instead of testing proximity to a
/// noisy referee, test the invariant we actually need — the same body seen
/// through two different frame aspects must measure identically after
/// correction, and must NOT measure identically before it.
///
/// The probe arm is deliberately *oblique*: axis-aligned angles survive axis
/// scaling unchanged (a right angle between a vertical and a horizontal
/// segment stays 90° at any aspect), so a test built on one would pass
/// against a broken implementation.
PoseFrame _bentArm() {
  final PoseFrame base =
      const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
  final List<PoseLandmark> lm = List<PoseLandmark>.of(base.landmarks);
  lm[Lm.leftShoulder] = const PoseLandmark(0.40, 0.30, 0, 1);
  lm[Lm.leftElbow] = const PoseLandmark(0.50, 0.42, 0, 1);
  lm[Lm.leftWrist] = const PoseLandmark(0.62, 0.40, 0, 1);
  return PoseFrame(tUs: 0, landmarks: lm);
}

double _elbow(PoseFrame f) => jointAngle2D(
    f.point(Lm.leftShoulder), f.point(Lm.leftElbow), f.point(Lm.leftWrist));

/// A camera at aspect A stores x as pixels/width: x_norm = x_iso / A
/// (z scales like x, per MediaPipe's convention).
PoseFrame _normalizedAt(PoseFrame isotropic, FrameSize size) {
  final double a = size.aspect;
  final List<PoseLandmark> lm = isotropic.landmarks
      .map((PoseLandmark l) =>
          PoseLandmark(l.x / a, l.y, l.z / a, l.visibility))
      .toList(growable: false);
  return PoseFrame(tUs: isotropic.tUs, landmarks: lm);
}

void main() {
  group('FrameSize / toIsotropic (M-F-30, J-028)', () {
    const FrameSize wide = FrameSize(1920, 1080);
    const FrameSize tall = FrameSize(608, 1080);

    test('raw normalized angles bend with the aspect ratio — the defect', () {
      final PoseFrame truth = _bentArm();
      final double atWide = _elbow(_normalizedAt(truth, wide));
      final double atTall = _elbow(_normalizedAt(truth, tall));

      expect((atWide - atTall).abs(), greaterThan(0.08),
          reason: 'the same physical arm must NOT read the same in raw '
              'normalized space — if it does, this test lost its subject');
    });

    test('after toIsotropic the same body measures the same at every aspect',
        () {
      final PoseFrame truth = _bentArm();
      final double reference = _elbow(truth);

      for (final FrameSize size in <FrameSize>[
        wide,
        tall,
        const FrameSize(1080, 1080),
        const FrameSize(3840, 1600),
      ]) {
        final double corrected =
            _elbow(_normalizedAt(truth, size).toIsotropic(size));
        expect(corrected, closeTo(reference, 1e-9),
            reason: 'aspect ${size.aspect.toStringAsFixed(2)} must be fully '
                'unbent — partial correction is the same silent-wrong class');
      }
    });

    test('gating an isotropic frame needs xExtent — the G-038 composition',
        () {
      final PoseFrame truth = _bentArm();
      // Denek karenin sağ yarısında: ham-normalize x ~0.62 → izotropikte ~1.1.
      final PoseFrame iso = _normalizedAt(truth, wide).toIsotropic(wide);
      const ConfidenceGate gate = ConfidenceGate();

      final FrameQuality wrong = gate.evaluate(iso);
      expect(wrong.offFrameLandmarks, isNotEmpty,
          reason: 'ham sınırla kapılamak sağ-yarı deneği "kadraj dışı" sayar — '
              'kusurun kendisi; bu beklenti kırılırsa test öznesini yitirmiş');

      final FrameQuality right = gate.evaluate(iso, xExtent: wide.aspect);
      expect(right.offFrameLandmarks, isEmpty,
          reason: 'aspect-farkında sınırla aynı denek kadraj içindedir');
    });

    test('a square frame is already isotropic and passes through unchanged',
        () {
      final PoseFrame truth = _bentArm();
      const FrameSize square = FrameSize(720, 720);
      expect(_elbow(_normalizedAt(truth, square).toIsotropic(square)),
          closeTo(_elbow(truth), 1e-12));
    });
  });
}


