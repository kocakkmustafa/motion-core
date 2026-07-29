// Canonical reference builder CLI (M-F-46 üretim yanı).
//
//   dart run tool/build_reference.dart \
//     --technique deep_squat --out ref.json [--min-takes 3] [--min-sources 3] \
//     [--cluster-tolerance-deg 14] [--joints fullBody|lowerBody|upperBody] \
//     fixture1.json fixture2.json ...
//
// Bütün mantık lib/src/tooling/reference_cli.dart'ta yaşar — app'ler ve bu
// araç AYNI fonksiyonu koşar, "kanonik" ancak böyle doğru kalır.
import 'dart:convert';
import 'dart:io';

import 'package:motion_core/motion_core.dart';

void main(List<String> args) {
  String? technique;
  String? out;
  int minTakes = 3;
  int minSources = 3;
  double clusterToleranceDeg = 14;
  bool allowUnattested = false;
  bool segmentCycles = true;
  List<JointSpec> specs = StandardJoints.fullBody;
  final List<String> paths = <String>[];

  try {
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--technique':
          technique = args[++i];
        case '--out':
          out = args[++i];
        case '--min-takes':
          minTakes = int.parse(args[++i]);
        case '--min-sources':
          minSources = int.parse(args[++i]);
        case '--cluster-tolerance-deg':
          clusterToleranceDeg = double.parse(args[++i]);
        case '--allow-unattested':
          allowUnattested = true;
        case '--no-cycle-segmentation':
          segmentCycles = false;
        case '--joints':
          specs = switch (args[++i]) {
            'lowerBody' => StandardJoints.lowerBody,
            'upperBody' => StandardJoints.upperBody,
            'flexionEight' => StandardJoints.flexionEight,
            _ => StandardJoints.fullBody,
          };
        default:
          paths.add(args[i]);
      }
    }
  } on Object catch (e) {
    // A flag missing its value or a non-numeric count is an operator
    // mistake, not a crash — it gets the usage surface, never a raw trace.
    stderr.writeln('ARGÜMAN HATASI: $e');
    stderr.writeln(
      'usage: build_reference.dart --technique <id> --out '
      '<path> [flags] <fixture.json>...',
    );
    exitCode = 64;
    return;
  }

  if (technique == null || out == null || paths.isEmpty) {
    stderr.writeln(
      'usage: build_reference.dart --technique <id> --out '
      '<path> [flags] <fixture.json>...',
    );
    exitCode = 64;
    return;
  }

  // Input loading stays OUTSIDE the gate try below — deliberately. If it
  // ever moves inside, an ArgumentError from Fixture.decode would print as
  // "REDDEDİLDİ (sayı/kaynak kapısı)" and L-143 is reborn in a new place:
  // a broken input file is not a policy refusal.
  final Map<String, Fixture> fixtures = <String, Fixture>{};
  for (final String p in paths) {
    final String id = p.split('/').last.replaceAll(RegExp(r'\.json$'), '');
    try {
      fixtures[id] = Fixture.decode(File(p).readAsStringSync());
    } on Object catch (e) {
      stderr.writeln('GİRDİ HATASI — fixture okunamadı ($p): $e');
      exitCode = 65;
      return;
    }
  }

  final ReferenceCli cli = ReferenceCli(
    builder: ReferenceBuilder(minTakes: minTakes, minSources: minSources),
    clusterToleranceDeg: clusterToleranceDeg,
    specs: specs,
    allowUnattested: allowUnattested,
    segmentCycles: segmentCycles,
  );

  try {
    final Map<String, dynamic> artifact = cli.buildArtifact(
      technique: technique,
      fixturesById: fixtures,
    );
    File(
      out,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(artifact));
    final Map<String, dynamic> r = artifact['result'] as Map<String, dynamic>;
    stdout.writeln(
      '✓ $out  takes=${r['contributingTakes']} '
      'sources=${r['distinctSources']} mirrored=${r['mirroredTakeIds']} '
      'excluded=${r['excludedOutlierIds']}',
    );
  } on RangeError catch (e, st) {
    // RangeError extends ArgumentError — without this arm a code defect
    // prints as "sayı/kaynak kapısı" and reads like a policy refusal
    // (L-143: hours lost to a crash wearing a gate's clothes).
    stderr.writeln('İÇ HATA — kod kusuru, kapı reddi DEĞİL: $e');
    stderr.writeln(st);
    exitCode = 70;
  } on StateError catch (e, st) {
    stderr.writeln('İÇ HATA — kod kusuru, kapı reddi DEĞİL: $e');
    stderr.writeln(st);
    exitCode = 70;
  } on ArgumentError catch (e) {
    stderr.writeln('REDDEDİLDİ (sayı/kaynak kapısı): ${e.message}');
    exitCode = 65;
  } on ReferenceAgreementError catch (e) {
    stderr.writeln('REDDEDİLDİ (M-F-47 anlaşma kapısı): $e');
    exitCode = 66;
  }
}
