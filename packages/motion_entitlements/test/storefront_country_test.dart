import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

void main() {
  test('App Store alpha-3 and Play alpha-2 normalise to alpha-2', () async {
    expect(await motionStorefrontCountry(read: () async => 'TUR'), 'TR');
    expect(await motionStorefrontCountry(read: () async => 'usa'), 'US');
    expect(await motionStorefrontCountry(read: () async => 'DE'), 'DE');
    expect(await motionStorefrontCountry(read: () async => ' gb '), 'GB');
  });

  test('unknown, empty, failing or slow stores yield null', () async {
    for (final raw in ['', 'XX', 'XXX', 'TURKEY', '12']) {
      expect(await motionStorefrontCountry(read: () async => raw), isNull);
    }
    expect(
      await motionStorefrontCountry(
        read: () async => throw StateError('no store'),
      ),
      isNull,
    );
    expect(
      await motionStorefrontCountry(
        read: () => Completer<String>().future,
        timeout: const Duration(milliseconds: 20),
      ),
      isNull,
    );
  });

  test('the JDK-derived table covers every Motion rule country', () {
    for (final code in [
      'AT',
      'BE',
      'BG',
      'HR',
      'CY',
      'CZ',
      'DK',
      'EE',
      'FI',
      'FR',
      'DE',
      'GR',
      'HU',
      'IE',
      'IT',
      'LV',
      'LT',
      'LU',
      'MT',
      'NL',
      'PL',
      'PT',
      'RO',
      'SK',
      'SI',
      'ES',
      'SE',
      'IS',
      'LI',
      'NO',
      'GB',
      'CH',
      'US',
      'CA',
      'BR',
      'MX',
      'AR',
      'KR',
      'CN',
      'JP',
      'IN',
      'ID',
      'SA',
      'AE',
      'TR',
      'AU',
    ]) {
      expect(motionAlpha2Country(code), code, reason: code);
    }
    expect(motionAlpha2Country('SAU'), 'SA');
    expect(motionAlpha2Country('ARE'), 'AE');
    expect(motionAlpha2Country('KOR'), 'KR');
  });
}
