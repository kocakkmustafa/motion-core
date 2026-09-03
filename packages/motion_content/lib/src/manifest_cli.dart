import 'dart:io';
import 'dart:typed_data';

import 'content_error.dart';
import 'manifest_builder.dart';
import 'semantic_version.dart';
import 'strict_json.dart';

Future<int> runMotionContentManifestCli(List<String> arguments) async {
  if (arguments.isEmpty ||
      (arguments.first != 'build' && arguments.first != 'verify')) {
    return 64;
  }
  final command = arguments.first;
  final options = _options(arguments.skip(1).toList(growable: false));
  if (options == null) return 64;
  try {
    if (command == 'build') {
      if (!_exactOptions(options, const {'source', 'root', 'output'})) {
        return 64;
      }
      final bytes = await ManifestBuilder().build(
        sourceBytes: await _readBoundedJsonFile(File(options['source']!)),
        root: Directory(options['root']!),
      );
      await _writeAtomically(File(options['output']!), bytes);
      return 0;
    }
    if (!_exactOptions(options, const {'manifest', 'root', 'app-id'})) {
      return 64;
    }
    await ManifestBuilder().verify(
      manifestBytes: await _readBoundedJsonFile(File(options['manifest']!)),
      root: Directory(options['root']!),
      expectedAppId: options['app-id']!,
      currentCoreContract: currentMotionContentContract,
    );
    return 0;
  } on ContentException catch (error) {
    stderr.writeln('motion_content_error:${error.error.code.name}');
    return 65;
  } on FormatException {
    stderr.writeln('motion_content_error:${ContentErrorCode.schema.name}');
    return 65;
  } on FileSystemException {
    stderr.writeln('motion_content_error:${ContentErrorCode.io.name}');
    return 74;
  }
}

Future<Uint8List> _readBoundedJsonFile(File file) async {
  final maximumBytes = const StrictJsonLimits().maxBytes;
  final handle = await file.open();
  try {
    if (await handle.length() > maximumBytes) {
      failContent(ContentErrorCode.resourceLimit);
    }
    final builder = BytesBuilder(copy: false);
    const chunkSize = 64 * 1024;
    while (builder.length <= maximumBytes) {
      final remaining = maximumBytes + 1 - builder.length;
      final bytes = await handle.read(
        remaining < chunkSize ? remaining : chunkSize,
      );
      if (bytes.isEmpty) break;
      builder.add(bytes);
    }
    final result = builder.takeBytes();
    if (result.length > maximumBytes) {
      failContent(ContentErrorCode.resourceLimit);
    }
    return result;
  } finally {
    await handle.close();
  }
}

Map<String, String>? _options(List<String> arguments) {
  if (arguments.length.isOdd) return null;
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final flag = arguments[index];
    if (!flag.startsWith('--') ||
        flag.length == 2 ||
        result.containsKey(flag.substring(2))) {
      return null;
    }
    final value = arguments[index + 1];
    if (value.isEmpty || value.startsWith('--')) return null;
    result[flag.substring(2)] = value;
  }
  return result;
}

bool _exactOptions(Map<String, String> options, Set<String> expected) =>
    options.length == expected.length &&
    options.keys.toSet().containsAll(expected);

Future<void> _writeAtomically(File output, List<int> bytes) async {
  await output.parent.create(recursive: true);
  final temporary = File('${output.path}.motion-content-tmp');
  if (await temporary.exists()) await temporary.delete();
  await temporary.writeAsBytes(bytes, flush: true);
  if (await output.exists()) await output.delete();
  await temporary.rename(output.path);
}
