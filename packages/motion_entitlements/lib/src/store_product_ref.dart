enum StorePlatform { ios, android }

/// One offer returned by the platform store. Google Play can return monthly
/// and yearly offers for the same subscription product ID, so [planId] is
/// part of the selection. The localized price comes from the store, never a
/// hard-coded USD amount in the app.
class StoreProductRef {
  const StoreProductRef({
    required this.productId,
    required this.platform,
    required this.planId,
    required this.localizedPrice,
    this.freeTrialPeriod,
  });

  final String productId;
  final StorePlatform platform;
  final String planId;

  /// The recurring price charged per [planId] period (after any free trial).
  final String localizedPrice;

  /// ISO-8601 length of a free trial the store says this user can start with
  /// this purchase (for example `P14D`), normalised to days for day/week
  /// periods. Null when the store offers no free trial, the user is not
  /// eligible, or eligibility could not be read: no trial is claimed then.
  final String? freeTrialPeriod;

  /// Whole days of [freeTrialPeriod] when it is day- or week-based.
  int? get freeTrialDays {
    final match = RegExp(r'^P(\d+)D$').firstMatch(freeTrialPeriod ?? '');
    return match == null ? null : int.parse(match.group(1)!);
  }
}

/// Normalises a store period (`P2W` × 1, `P1W` × 2, `P14D`) to ISO-8601;
/// day/week periods become days. Returns null for an unreadable period.
String? motionStorePeriod(String isoPeriod, {int count = 1}) {
  final match = RegExp(r'^P(\d+)([DWMY])$').firstMatch(isoPeriod);
  if (match == null || count < 1) return null;
  final value = int.parse(match.group(1)!) * count;
  if (value < 1) return null;
  return switch (match.group(2)!) {
    'D' => 'P${value}D',
    'W' => 'P${value * 7}D',
    final unit => 'P$value$unit',
  };
}
