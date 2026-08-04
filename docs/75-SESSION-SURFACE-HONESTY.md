# 75 — SESSION-SURFACE-HONESTY (normatif; M-F-254, 2026-08-04)

> Oturum-geçmişi YÜZEYLERİNİN dürüstlük sözleşmesi. Bu doküman bu vardiyada
> ÜÇ hatta bağımsız ÖLÇÜLEN değişmezleri kodifiye eder (JabLab `d66c7f1`
> cihaz-kanıtı · Gravita `5ca6e79` · Choreia `7d6dd9c`). Tip: motion_core
> 0.11.0 `HistoryReadStatus` (sealed: Ok · Partial(n>0) · Unavailable).
> WIDGET terfi ETMEDİ — görsel yüzey app'in sesidir; tetik: "ikinci app aynı
> WIDGET'ı kopyalamak zorunda kaldığında" (M-F-254).

## Yedi değişmez (hepsi ölçülmüş vakadan; hiçbiri öneri değildir)

1. **Sıfırlı-kısmi İMKÂNSIZDIR — tip düzeyinde.** `HistoryPartial(0)` kurulamaz
   (assert). Sıfır kayıplı "kısmi" beyanı yalandır; o hâl `HistoryOk`'tur.
   *(Gravita, M-F-251.)*
2. **Açılamayan geçmişten SAYI DOĞMAZ (totals-nullable).** Sıfır-dolu özet
   dönmek, dosya-açamamayı "0 seans, 0 dk" diye render ettirir — "hiçbir şey
   yapmadın" yalanının en kendinden emin hâli. Nesne yoksa render edilecek
   sayı da yoktur: yanlış çıktı gizlenmez, HİÇ OLUŞMAZ. *(Choreia, M-F-250.)*
3. **Kısmi beyan SAYILARIN ÜSTÜNDE durur.** Toplamlardan sonra gelen bir not,
   onların tam sayım olarak okunmasına çoktan izin vermiştir. Kısmi hâlde
   toplamlar TABANDIR ve taban-dili ("en az bu kadar") kayıp SAYISIYLA
   birlikte verilir. *(Choreia + JabLab taban-dili.)*
4. **Okunabilir-kayıt-0 ucunda "taban" dili YASAKTIR.** Taban sıfırken "taban"
   demek doğru ve İŞE YARAMAZ; o uç AYRI cümledir ve gerçek şeyi söyler
   ("bu, hiç çalışmadığınla aynı şey değil — içindekini okuyamıyoruz").
   Kısmi-metin `at least` taşır, sıfır-ucu metni TAŞIMAZ (ikizli sınanır).
   *(Choreia; JabLab uç-durum kuralı: tüm-satırlar-bozuk kısmi-dalı susturamaz.)*
5. **Hâller birbirinin YERİNE GEÇEMEZ.** Hâl-başına AYRI render yolu/anahtarı;
   `unavailable` hiçbir koşulda `ok` gibi, `partial` hiçbir koşulda tam-sayım
   gibi görünemez. Ham `detail` yüzeye SIZMAZ (kullanıcı metni app'in sesiyle).
   *(Gravita widget-anahtarları; Choreia none-readable ayrı-metni.)*
6. **Temiz hâl HİÇBİR ŞEY söylemez.** Koşulsuz-uyaran bir yüzey diğer bütün
   testleri geçer — temiz-store→sessiz ikizi ZORUNLUDUR. *(Choreia kilit ikizi;
   M-F-236/6b sınıfının oturum-yüzü karşılığı.)*
7. **"Pin bump tek başına adopsiyon DEĞİLDİR" — yüzey-zorlama nöbeti ZORUNLU.**
   Arayüz-zorlaması (zorunlu üye) çekirdeğin implementasyonunu KULLANANLARA
   ulaşmaz; adaptör sessizce uyumlu kalır ("çekirdek cevap veriyordu, yüzey
   bakmıyordu"). Her adopsiyon iki şeyi SINAR: `unreadableRecords()` üründe
   TÜKETİLİYOR ve yüzey `Partial`'da DALLANIYOR. *(Choreia mekanizma-sınırı +
   Gravita nöbeti, M-F-250/251 — birbirinin cevabı.)*

## Mekanizma notları

- Kaynak veri: `SessionStore.unreadableRecords()` (0.10.0, varsayılansız
  zorunlu üye — M-F-246). Sayım semantiği: bozuk satır + bilinmeyen-sürüm =
  KAYIP; v1-göç = kayıp DEĞİL; dosya-yok = 0/0 (ilk açılış). Yol-dosya-değilse
  YÜKSEK SESLE istisna (0.10.1 — "var olan ama okunamayan yol, hiç yazılmamış
  gibi okunamaz").
- Hâl türetimi: başarılı okumada `HistoryReadStatus.of(unreadable)`;
  açılamama İSTİSNA yoludur ve `HistoryUnavailable` çağıranda kurulur.
- Test asgarisi (adopsiyon başına): temiz→sessiz ikizi · kısmi→görünür+sayı+
  taban-dili · sıfır-ucu→ayrı-metin (`at least` İÇERMEZ) · açılamama→sayı YOK ·
  gerçek-dosya bozuk-satır enjeksiyonu (store'un KENDİ yazdığı dosyada; şema
  anahtarını elle yazma — Gravita'nın enjeksiyon-hatası dersi: gerçek yazıcıyı
  kullan) · metin testi SAYIYI arar (interpolasyon-kaçağı sınıfı).

## Adopsiyon durumu (2026-08-04)

| hat | durum |
|---|---|
| Gravita | ✅ sealed yerel tip → 0.11.0 tipine doğal dokunuşta geçer |
| Choreia | ✅ yerel üç-durum → 0.11.0 tipine doğal dokunuşta geçer |
| JabLab | ✅ TAMAM (2026-08-04, `325542d`): yerel store EMEKLİ, pin `f13bdc9`
(motion_core-v0.11.0'ı ebeveyn olarak taşır — tek-pin çözümü); v1→v2 veri-göçü
5 testle + CİHAZDA doğrulandı ("göç yanlış çalışsaydı J-092 mekanizması kendi
kurbanı olurdu"); değişmez-7 CASUS-DEPO ile sınanıyor (ürün unreadableRecords'u
gerçekten çağırmazsa test düşer); RecordedSummary app'te KALDI (sunum = app'in
sesi — widget-terfi-etmez sınırının aynısı) |
| Lissom | SessionStore tüketicisi (ilk adaptör 0.9.0) — üç-hâl yüzeyi kendi
doğal dokunuşunda |
| Ostinato | SessionStore adopsiyonu YASAK (tüketici yüzeyi yok — M-F-236) |
