@Tags(<String>['tool'])
library;

import 'dart:io';

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

/// Subprocess smoke tests for tool/build_reference.dart — the surface L-143
/// lived on. Review finding MEDIUM-1: the exception-arm ordering and the
/// named-refusal wording had zero automated coverage; reverting the handler
/// order reintroduced L-143 verbatim with the whole suite green.
void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('tool_smoke');
    File('${dir.path}/solo.json').writeAsStringSync(Fixture(
      app: 'lissom',
      technique: 'overhead_reach',
      frames: const <PoseFrame>[],
      provenance: ProvenanceInfo(channel: 'ch-solo'),
    ).encode());
    File('${dir.path}/broken.json').writeAsStringSync('{not json');
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  ProcessResult run(List<String> args) => Process.runSync(
        'dart',
        <String>['run', 'tool/build_reference.dart', ...args],
      );

  test('a frameless-only pool is a NAMED refusal at exit 65, never a crash',
      () {
    final ProcessResult r = run(<String>[
      '--technique', 'overhead_reach',
      '--out', '${dir.path}/ref.json',
      '--min-takes', '1',
      '--min-sources', '1',
      '${dir.path}/solo.json',
    ]);
    expect(r.exitCode, 65, reason: 'stderr: ${r.stderr}');
    expect('${r.stderr}', contains('REDDEDİLDİ'));
    expect('${r.stderr}', contains('solo'));
    expect('${r.stderr}', contains('no measurable frames'));
    expect('${r.stderr}', isNot(contains('İÇ HATA')));
    expect('${r.stderr}', isNot(contains('No element')));
  });

  test('a broken fixture file is an input error, not a gate refusal', () {
    final ProcessResult r = run(<String>[
      '--technique', 't',
      '--out', '${dir.path}/ref.json',
      '${dir.path}/broken.json',
    ]);
    expect(r.exitCode, 65, reason: 'stderr: ${r.stderr}');
    expect('${r.stderr}', contains('GİRDİ HATASI'));
    expect('${r.stderr}', isNot(contains('REDDEDİLDİ')));
  });

  test('a flag missing its value gets the usage surface, not a raw trace',
      () {
    final ProcessResult r = run(<String>['--technique']);
    expect(r.exitCode, 64, reason: 'stderr: ${r.stderr}');
    expect('${r.stderr}', contains('ARGÜMAN HATASI'));
    expect('${r.stderr}', contains('usage:'));
  });
}
