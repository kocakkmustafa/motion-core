import 'dart:io';

import 'package:motion_content/src/manifest_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMotionContentManifestCli(arguments);
}
