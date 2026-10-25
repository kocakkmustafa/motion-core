import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An age range shared by the store account (Apple Declared Age Range,
/// Google Play Age Signals). The store reports a band, never a birth date.
@immutable
class MotionStoreAgeSignal {
  const MotionStoreAgeSignal({
    required this.source,
    required this.shared,
    this.lower,
    this.upper,
    this.declaration,
  });

  /// `apple` or `google`.
  final String source;

  /// False when the person (or guardian) declined to share an age range.
  final bool shared;

  /// Inclusive lower bound; null for the lowest band.
  final int? lower;

  /// Inclusive upper bound; null for the open top band (for example 18+).
  final int? upper;

  /// Apple `ageRangeDeclaration` (selfDeclared, guardianDeclared, confirmed…)
  /// or null.
  final String? declaration;

  static MotionStoreAgeSignal? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final source = raw['source'];
    final shared = raw['shared'];
    if ((source != 'apple' && source != 'google') || shared is! bool) {
      return null;
    }
    int? bound(Object? value) =>
        value is int && value >= 0 && value <= 150 ? value : null;
    final lower = bound(raw['lower']);
    final upper = bound(raw['upper']);
    if (lower != null && upper != null && lower > upper) return null;
    final declaration = raw['declaration'];
    return MotionStoreAgeSignal(
      source: source as String,
      shared: shared,
      lower: shared ? lower : null,
      upper: shared ? upper : null,
      declaration: declaration is String && declaration.length <= 64
          ? declaration
          : null,
    );
  }
}

/// Platform channel facade. Tests replace [channel] handlers through
/// `TestDefaultBinaryMessengerBinding`.
class MotionPlatformSignals {
  const MotionPlatformSignals._();

  @visibleForTesting
  static const channel = MethodChannel('com.yulalab.motion_platform_signals');

  /// The age gates asked from the store: under 13, 13–15, 16–17, 18+.
  static const ageGates = [13, 16, 18];

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

  /// Asks the store account for an age range. May show the store's own
  /// sharing prompt. iOS 26+ (Declared Age Range; the app needs the
  /// `com.apple.developer.declared-age-range` entitlement) or Google Play Age
  /// Signals (returned only in regions where the store provides it). Null
  /// when unavailable, unsupported or failed: callers keep their own age flow.
  static Future<MotionStoreAgeSignal?> requestAgeSignal() async {
    try {
      final raw = await channel.invokeMethod<Object?>('requestAgeSignal', {
        'ageGates': ageGates,
      });
      return MotionStoreAgeSignal.fromMap(raw);
    } on Object {
      return null;
    }
  }
}
