/// Store/platform signals for the Yula Motion family. Every call returns
/// null when the platform API is unavailable (OS version, platform, store
/// region or an error); callers must keep their own fallback.
library;

export 'src/motion_platform_signals.dart';
