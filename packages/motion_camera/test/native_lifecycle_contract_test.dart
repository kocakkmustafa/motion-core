import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) {
  for (final String candidate in <String>[
    relativePath,
    'packages/motion_camera/$relativePath',
  ]) {
    final File source = File(candidate);
    if (source.existsSync()) return source.readAsStringSync();
  }
  throw StateError('motion_camera source not found: $relativePath');
}

void main() {
  test(
    'Android is bound to the real Activity lifecycle and rejects stale work',
    () {
      final String source = _source(
        'android/src/main/kotlin/com/yulalab/motion_camera/'
        'MotionCameraPlugin.kt',
      );

      expect(source, contains('ActivityAware'));
      expect(source, contains('DefaultLifecycleObserver'));
      expect(source, isNot(contains('SessionLifecycleOwner')));
      expect(source, isNot(contains('LifecycleRegistry')));
      expect(source, contains('onDetachedFromActivityForConfigChanges'));
      expect(source, contains('override fun onStop(owner: LifecycleOwner)'));
      expect(source, contains('isCurrentGeneration'));
      expect(source, contains('analyze(proxy, generation)'));
      expect(
        source,
        contains('if (!isCurrentGeneration(generation)) return@post'),
      );
      expect(
        source,
        matches(
          RegExp(r'override fun onCancel\([^}]+tearDown\(', dotAll: true),
        ),
      );
      expect(
        source,
        matches(
          RegExp(
            r'private fun stop\(result: MethodChannel\.Result\) \{\s*'
            r'tearDown\(\)\s*result\.success\(null\)',
            dotAll: true,
          ),
        ),
      );
    },
  );

  test('iOS requires active state and tears down before background', () {
    final String source = _source('ios/Classes/MotionCameraPlugin.swift');

    expect(source, contains('registrar.publish(instance)'));
    expect(source, contains('@objc(detachFromEngineForRegistrar:)'));
    expect(source, contains('UIApplication.willResignActiveNotification'));
    expect(
      source,
      contains('UIApplication.shared.applicationState == .active'),
    );
    expect(source, contains('isCurrentGeneration'));
    expect(source, contains('generation: generation'));
    expect(source, contains('output === activeOutput'));
    expect(
      source,
      contains('guard self.isCurrentGeneration(generation) else { return }'),
    );
    expect(
      source,
      matches(RegExp(r'onCancel\(withArguments[^}]+tearDown\(', dotAll: true)),
    );
    expect(
      source,
      matches(
        RegExp(
          r'private func stop\(result: @escaping FlutterResult\) \{\s*'
          r'tearDown\s*\{\s*result\(nil\)\s*\}',
          dotAll: true,
        ),
      ),
    );
  });
}
