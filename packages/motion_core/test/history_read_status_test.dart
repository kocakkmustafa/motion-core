import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

void main() {
  group('HistoryReadStatus — üç-hâl sözleşmesi (M-F-254, 0.11.0)', () {
    test('of(0) → HistoryOk (temiz hâl hiçbir şey söylemez — ikizin tabanı)',
        () {
      expect(HistoryReadStatus.of(0), isA<HistoryOk>());
    });

    test('of(n>0) → HistoryPartial(n) ve sayı taşınır', () {
      final HistoryReadStatus s = HistoryReadStatus.of(3);
      expect(s, isA<HistoryPartial>());
      expect((s as HistoryPartial).unreadable, 3);
    });

    test('SIFIRLI-KISMİ TİP DÜZEYİNDE İMKÂNSIZ (Gravita deseni, M-F-251)', () {
      expect(() => HistoryPartial(0), throwsA(isA<AssertionError>()));
      expect(() => HistoryPartial(-1), throwsA(isA<AssertionError>()));
    });

    test('unavailable detail taşır; of() onu ÜRETEMEZ (istisna yolu ayrı)',
        () {
      const HistoryUnavailable u = HistoryUnavailable('fs-error: EACCES');
      expect(u.detail, contains('EACCES'));
      // of() yalnız ok/partial üretir — açılamama sayıdan türetilemez.
      expect(HistoryReadStatus.of(0), isNot(isA<HistoryUnavailable>()));
    });

    test('sealed: switch üç hâli de zorlar (derleme-düzeyi tüketim kanıtı)',
        () {
      String render(HistoryReadStatus s) => switch (s) {
            HistoryOk() => 'sessiz',
            HistoryPartial(:final int unreadable) => 'taban:$unreadable',
            HistoryUnavailable() => 'sayı-yok',
          };
      expect(render(const HistoryOk()), 'sessiz');
      expect(render(HistoryPartial(2)), 'taban:2');
      expect(render(const HistoryUnavailable('x')), 'sayı-yok');
    });
  });
}
