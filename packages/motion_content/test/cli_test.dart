import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:motion_content/src/manifest_cli.dart';
import 'package:test/test.dart';

import 'manifest_builder_test.dart';

void main() {
  test(
    'build and verify commands round-trip; tampering fails verify',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final sourceFile = File('${root.path}/manifest.source.json');
      final outputFile = File('${root.path}/manifest.json');
      await sourceFile.writeAsString(jsonEncode(sourceManifestMap()));

      expect(
        await runMotionContentManifestCli([
          'build',
          '--source',
          sourceFile.path,
          '--root',
          root.path,
          '--output',
          outputFile.path,
        ]),
        0,
      );
      expect(
        await runMotionContentManifestCli([
          'verify',
          '--manifest',
          outputFile.path,
          '--root',
          root.path,
          '--app-id',
          'com.example.motion',
        ]),
        0,
      );

      final lesson = File(
        '${root.path}/assets/motion_content/lessons/one.json',
      );
      await lesson.writeAsString('{"tampered":true}');
      expect(
        await runMotionContentManifestCli([
          'verify',
          '--manifest',
          outputFile.path,
          '--root',
          root.path,
          '--app-id',
          'com.example.motion',
        ]),
        isNot(0),
      );
    },
  );

  test('unknown/missing arguments fail without throwing raw paths', () async {
    expect(await runMotionContentManifestCli(['unknown']), 64);
    expect(await runMotionContentManifestCli(['build']), 64);
    expect(await runMotionContentManifestCli(['build', '--root']), 64);
    expect(
      await runMotionContentManifestCli([
        'build',
        '--root',
        '--source',
        'value',
      ]),
      64,
    );
    expect(
      await runMotionContentManifestCli([
        'build',
        '--root',
        'one',
        '--root',
        'two',
      ]),
      64,
    );
  });

  test(
    'unknown verify options and missing input map to stable codes',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final missing = '${root.path}/missing.json';
      expect(
        await runMotionContentManifestCli([
          'verify',
          '--manifest',
          missing,
          '--root',
          root.path,
          '--app-id',
          'com.example.motion',
        ]),
        74,
      );

      final sourceFile = File('${root.path}/manifest.source.json');
      final outputFile = File('${root.path}/manifest.json');
      await sourceFile.writeAsString(jsonEncode(sourceManifestMap()));
      expect(
        await runMotionContentManifestCli([
          'build',
          '--source',
          sourceFile.path,
          '--root',
          root.path,
          '--output',
          outputFile.path,
        ]),
        0,
      );
      expect(
        await runMotionContentManifestCli([
          'verify',
          '--manifest',
          outputFile.path,
          '--root',
          root.path,
          '--app-id',
          'com.example.motion',
          '--core-contract',
          '1.0.0',
        ]),
        64,
      );
    },
  );

  test(
    'oversized build and verify JSON inputs fail with a stable code',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'motion_content_cli_limit_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final oversized = File('${root.path}/oversized.json');
      await oversized.writeAsBytes(Uint8List(1024 * 1024 + 1));

      expect(
        await runMotionContentManifestCli([
          'build',
          '--source',
          oversized.path,
          '--root',
          root.path,
          '--output',
          '${root.path}/manifest.json',
        ]),
        65,
      );
      expect(
        await runMotionContentManifestCli([
          'verify',
          '--manifest',
          oversized.path,
          '--root',
          root.path,
          '--app-id',
          'com.example.motion',
        ]),
        65,
      );
    },
  );
}
