import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:motion_account/src/motion_app_brand.dart';

void main() {
  test('membership title uses each app store brand spelling', () {
    expect(motionAppBrandName('jablab'), 'JabLab');
    expect(
      {for (final app in MotionApp.values) app.name: motionAppBrandName(app.name)},
      {
        'ostinato': 'Ostinato',
        'gravita': 'Gravita',
        'choreia': 'Choreia',
        'jablab': 'JabLab',
        'lissom': 'Lissom',
      },
    );
  });

  test('an id without an entry keeps the capitalised id', () {
    expect(motionAppBrandName('newapp'), 'Newapp');
    expect(motionAppBrandName(''), '');
  });
}
