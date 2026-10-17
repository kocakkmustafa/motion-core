import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

final model = 'a' * 64;
final calibration = 'b' * 64;
final acceptance = 'c' * 64;

MotionProviderManifest manifest({
  String version = '1.0.0',
  MotionProviderMode mode = MotionProviderMode.production,
  MotionCapabilityState state = MotionCapabilityState.validated,
  String space = 'image2d.aspectCorrected',
}) => MotionProviderManifest(
  providerId: 'synthetic.test.provider',
  providerVersion: version,
  mode: mode,
  runtimeAbi: 'synthetic.test.abi.v1',
  inputSchema: 'body33.image.v1',
  coordinateSpace: space,
  modelSha256: model,
  capabilities: {
    'test.task.v1': MotionCapability(
      state: state,
      calibrationSha256: calibration,
      acceptanceSha256: acceptance,
    ),
  },
);

MotionProviderRequirement requirement({
  String capability = 'test.task.v1',
  String? actualModel,
  String? actualCalibration,
  String? reviewedAcceptance,
  MotionProviderMode mode = MotionProviderMode.production,
}) => MotionProviderRequirement(
  capability: capability,
  runtimeAbi: 'synthetic.test.abi.v1',
  inputSchema: 'body33.image.v1',
  coordinateSpace: 'image2d.aspectCorrected',
  actualModelSha256: actualModel ?? model,
  actualCalibrationSha256: actualCalibration ?? calibration,
  reviewedAcceptanceSha256: reviewedAcceptance ?? acceptance,
  mode: mode,
);

void main() {
  test(
    'roundtrip retains exact model, capability and coordinate identities',
    () {
      final original = manifest();
      expect(
        MotionProviderManifest.fromJson(original.toJson()).toJson(),
        original.toJson(),
      );
      expect(requirement().inspect(original), MotionReadiness.ready);
    },
  );

  for (final field in [
    'schemaVersion',
    'contractVersion',
    'mode',
    'providerVersion',
    'modelSha256',
    'capabilities',
  ]) {
    test('malformed or unknown $field never defaults to a supported value', () {
      final json = manifest().toJson()..[field] = 'unknown';
      expect(
        () => MotionProviderManifest.fromJson(json),
        throwsFormatException,
      );
    });
  }

  test(
    'unknown capability state and incomplete validated provenance fail closed',
    () {
      for (final state in ['futureState', 'validated']) {
        final json = manifest().toJson()
          ..['capabilities'] = {
            'test.task.v1': {'state': state},
          };
        expect(
          () => MotionProviderManifest.fromJson(json),
          throwsFormatException,
        );
      }
    },
  );

  test('capability map is an immutable snapshot', () {
    final json = manifest();
    expect(json.capabilities.clear, throwsUnsupportedError);
  });

  test('unsupported, missing and uncalibrated tasks cannot become ready', () {
    expect(
      requirement().inspect(manifest(state: MotionCapabilityState.unsupported)),
      MotionReadiness.unsupported,
    );
    expect(
      requirement(capability: 'other.app.task').inspect(manifest()),
      MotionReadiness.unsupported,
    );
    expect(
      requirement().inspect(
        manifest(state: MotionCapabilityState.calibrationRequired),
      ),
      MotionReadiness.calibrationRequired,
    );
  });

  test(
    'replay manifests are rejected by production even with matching hashes',
    () {
      final replay = manifest(mode: MotionProviderMode.replay);
      expect(requirement().inspect(replay), MotionReadiness.replayOnly);
      expect(
        requirement(mode: MotionProviderMode.replay).inspect(replay),
        MotionReadiness.ready,
      );
    },
  );

  test('different space, runtime and input schema do not silently adapt', () {
    for (final field in ['runtimeAbi', 'inputSchema', 'coordinateSpace']) {
      final json = manifest().toJson()..[field] = 'other';
      expect(
        requirement().inspect(MotionProviderManifest.fromJson(json)),
        MotionReadiness.incompatible,
      );
    }
  });

  test('actual bytes and separate acceptance must all match', () {
    expect(
      requirement(actualModel: 'd' * 64).inspect(manifest()),
      MotionReadiness.artifactMismatch,
    );
    expect(
      requirement(actualCalibration: 'd' * 64).inspect(manifest()),
      MotionReadiness.artifactMismatch,
    );
    expect(
      requirement(reviewedAcceptance: 'd' * 64).inspect(manifest()),
      MotionReadiness.acceptanceRequired,
    );
    const missing = MotionProviderRequirement(
      capability: 'test.task.v1',
      runtimeAbi: 'synthetic.test.abi.v1',
      inputSchema: 'body33.image.v1',
      coordinateSpace: 'image2d.aspectCorrected',
      actualModelSha256: null,
      actualCalibrationSha256: null,
      reviewedAcceptanceSha256: null,
    );
    expect(missing.inspect(manifest()), MotionReadiness.artifactMismatch);
  });

  test('incompatible candidate preserves active and previous identities', () {
    final selection = MotionProviderSelection();
    final first = manifest();
    final second = manifest(version: '1.1.0');
    expect(selection.select(first, requirement()), MotionReadiness.ready);
    expect(selection.select(second, requirement()), MotionReadiness.ready);
    expect(
      selection.select(manifest(space: 'world3d'), requirement()),
      MotionReadiness.incompatible,
    );
    expect(selection.active, same(second));
    expect(selection.previous, same(first));
    expect(selection.rollback(requirement()), MotionReadiness.ready);
    expect(selection.active, same(first));
  });

  test('rollback revalidates current bytes; clear revokes both selections', () {
    final selection = MotionProviderSelection();
    expect(selection.rollback(requirement()), MotionReadiness.unsupported);
    selection.select(manifest(), requirement());
    final second = manifest(version: '1.1.0');
    selection.select(second, requirement());
    expect(
      selection.rollback(requirement(actualCalibration: 'e' * 64)),
      MotionReadiness.artifactMismatch,
    );
    expect(selection.active, same(second));
    selection.clear();
    expect(selection.active, isNull);
    expect(selection.previous, isNull);
  });
}
