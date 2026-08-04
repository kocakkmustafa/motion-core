/// Üç-hâl geçmiş-okuma sözleşmesi (M-F-254, motion_core 0.11.0).
///
/// Üç hat (JabLab · Gravita · Choreia) AYNI semantiğe bağımsız yakınsadı;
/// üçler kuralı SEMANTİKTE doldu ve yalnız SÖZLEŞME terfi etti — WIDGET
/// terfi ETMEDİ (isimli erteleme, M-F-254: görsel yüzey her app'in kendi
/// sesidir; tetik "ikinci app aynı WIDGET'ı kopyalamak zorunda kaldığında").
///
/// Kullanım: `unreadableRecords()` başarılı okumada [HistoryReadStatus.of]
/// ile hâle çevrilir; store AÇILAMADIĞINDA (istisna) [HistoryUnavailable]
/// kurulur. Yüzey kuralları docs/75-SESSION-SURFACE-HONESTY.md'de —
/// özellikle: hâller birbirinin yerine GEÇEMEZ (hâl-başına ayrı render
/// yolu) ve temiz hâl HİÇBİR ŞEY söylemez.
library;

/// Kapalı hiyerarşi: bir okuma sonucu bu üçünden tam biridir.
sealed class HistoryReadStatus {
  const HistoryReadStatus();

  /// Başarılı okumanın kayıp sayısından hâl türetir: 0 → [HistoryOk],
  /// n>0 → [HistoryPartial]. AÇILAMAMA buradan üretilmez — o bir istisna
  /// yoludur ve çağıran [HistoryUnavailable]'ı kendisi kurar ("yanlış çıktı
  /// gizlenmez, hiç OLUŞMAZ": açılamayan store'dan sayı türetilemez).
  static HistoryReadStatus of(int unreadable) =>
      unreadable > 0 ? HistoryPartial(unreadable) : const HistoryOk();
}

/// Geçmiş TAM okundu. Yüzey bu hâlde HİÇBİR beyan göstermez — koşulsuz
/// uyaran bir yüzey, temiz-hâl ikizini geçemez (M-F-236/6b sınıfının
/// oturum-yüzü karşılığı).
final class HistoryOk extends HistoryReadStatus {
  const HistoryOk();
}

/// KISMİ okuma: [unreadable] kayıt çözülemedi. Toplamlar TABANDIR
/// ("en az bu kadar") ve yüzey bunu SAYILARIN ÜSTÜNDE söyler.
///
/// n > 0 tip düzeyinde zorunlu (Gravita deseni, M-F-251): sıfır kayıplı
/// bir "kısmi" beyanı yalan olurdu — o hâl [HistoryOk]'tur.
final class HistoryPartial extends HistoryReadStatus {
  HistoryPartial(this.unreadable)
      : assert(unreadable > 0,
            'sıfır kayıplı "kısmi" beyanı yalandır — HistoryOk kullanın');

  final int unreadable;
}

/// Geçmiş AÇILAMADI: sayı YOKTUR (totals-nullable — Choreia deseni,
/// M-F-250). "Hiç yapmadın ≠ bilmiyorum" bu hâlde yaşar: yüzey sayı
/// GÖSTERMEZ, durumu beyan eder; "okunabilir kayıt 0" ucunda "taban" dili
/// KULLANILMAZ (taban sıfırken "taban" demek doğru ve işe yaramaz).
final class HistoryUnavailable extends HistoryReadStatus {
  const HistoryUnavailable(this.detail);

  /// Teşhis sınıfı/detayı — geliştirici içindir, kullanıcı metni DEĞİLDİR
  /// (kullanıcı metni app'in sesiyle yazılır; ham detail yüzeye SIZMAZ).
  final String detail;
}
