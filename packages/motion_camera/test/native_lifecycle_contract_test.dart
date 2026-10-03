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
  // Source wiring checks only. The host helper harness and physical/plugin
  // acceptance are separate; these strings execute no CameraX/AVFoundation.
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
      expect(source, contains('lifecycle.requestClose(ownerId, scoped)'));
      expect(
        source,
        contains('lifecycle.finishClose(!failed && captureClosed)'),
      );
      expect(source, contains('CameraState.Type.CLOSED'));
      expect(source, contains('marker.close()'));
      expect(source, contains('tearDown(ownerId = ownerId, scoped = true)'));
      expect(
        source,
        contains('OrientedCaptureTasks(createTask(), createTask())'),
      );
      expect(
        source,
        contains(
          'tasks.task(inverted).detectForVideo(image, processing, tUs / 1000)',
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
      contains('lifecycle.requestClose(ownerId: ownerId, scoped: scoped)'),
    );
    expect(source, contains('lifecycle.finishClose(success: captureClosed)'));
    expect(source, contains('retired.session?.isRunning != true'));
    expect(source, contains('retired.tasks = nil'));
    expect(source, contains('tearDown(ownerId: owner, scoped: true)'));
    expect(source, contains('tasks.task(inverted: rotated).detect('));
  });
}
