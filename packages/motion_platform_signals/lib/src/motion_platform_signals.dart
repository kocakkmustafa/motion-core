import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel facade. Tests replace [channel] handlers through
/// `TestDefaultBinaryMessengerBinding`.
class MotionPlatformSignals {
  const MotionPlatformSignals._();

  @visibleForTesting
  static const channel = MethodChannel('com.yulalab.motion_platform_signals');

  /// The App Store `AppTransaction.appTransactionID` for this install's Apple
  /// Account (StoreKit 2, iOS 16+; verified transactions only). Null on
  /// Android, iOS 15, an unverified app transaction or any error.
  static Future<String?> appTransactionId() async {
    try {
      final value = await channel.invokeMethod<String>('appTransactionId');
      return value == null || value.isEmpty || value.length > 64 ? null : value;
    } on Object {
      return null;
    }
  }
}
