# Motion hesabı — 13+ yaş, veli onayı ve kısa saklama profili

21 Ekim 2026 kurucu kararlarının Core uygulaması: beş Motion app'i global pazarda
13+ gençler dahil; saklama kısa profil. **Bu belge hukuki görüş değildir.** Ülke
yaş tablosu mühendislik varsayılanıdır; mağaza başvurusundan önce hukuk
incelemesi gerekir. Kaynak: `packages/motion_account/lib/src/motion_age_policy.dart`
ve `supabase/migrations/20261021190000_motion_age_consent_retention.sql`
(tablo eşliği paket testinde denetlenir).

## Yaş kapısı

| Kural | Uygulama |
|---|---|
| 13 altı | Hiçbir ülkede hesap yok (ABD COPPA dışı). İstemci kapısı kayıt isteği göndermez; sunucu tetikleyicisi 13 altı beyanla kaydı reddeder (`P0013`). Host `onAgeBlocked` ile sonucu saklar, `ageBlocked: true` ile geri verir. |
| 13 ≤ yaş < ülke rıza yaşı | Hesap açılır ama **kısıtlı**: ortak profil yazımı RLS ile kapalı, veli/vasi onayı istenir. Cihazdaki pratik çalışır. |
| rıza yaşı ≤ yaş < 18 | Genç: pazarlama yok, kişiselleştirilmiş reklam yok, analitik yalnız açık katılımla (`MotionAgePolicy.marketingAllowed`, `analyticsNeedsOptIn`). |
| 18+ | Yetişkin. |

Nötr yaş ekranı: ön seçili değer yok, eşik ipucu yok, gün sorulmaz (yalnız `YYYY-MM`).
Doğum ayı içinde doğum günü "geçmemiş" sayılır (yaş asla büyütülmez). Ülke:
host'un verdiği bölge (ör. mağaza storefront) yoksa cihaz bölgesi; bilinmiyorsa
16 (GDPR Art. 8 en sıkı değeri). Beyan bir kez yapılır; düzeltme destek
üzerinden (reddedilen gencin yaşı yeniden yazması engellenir). Rıza yaşına
ulaşan genç, sunucu bandı tarihle yeniden hesapladığı için kendiliğinden açılır.

Ülke tablosu (rıza yaşı): AB/AEA üye ülke GDPR Art. 8 değerleri; GB 13; US 13;
CA 14 (Quebec); BR 16 (ECA Digital); MX 18; AR 16; KR 14; CN 14; JP 16;
IN 18 (DPDP); ID 18; SA 18; AE 18; TR 18; AU 16; CH 16; diğer → 16.

## Veli/vasi onayı

1. Genç oturum açıkken veli e-postasını girer → `motion-parental-consent`
   (`request`). Sunucu: hesap gerçekten kısıtlı mı, kendi adresi mi, 10 dk
   yeniden gönderim / günde 5 sınırı. Bağlantı 7 gün geçerli.
2. Veli adresi **açık metin saklanmaz** (yalnız SHA-256 özet); bağlantı jetonu
   yalnız özet olarak saklanır ve URL fragment'inde taşınır (sunucu loguna düşmez).
3. Veli sayfası (`https://yulalab.com/motion/consent#token=…`, YULALAB sitesi)
   `view` ile maskeli genç e-postasını gösterir, `decide` ile onay/ret gönderir.
4. Onay → kısıt kalkar. **Ret → hesap silinir** (silme makbuzu yazılır; beş
   app'teki hesap dosyaları çevrimiçi açılışta temizlenir).
5. Onaylanmayan hesap 30 gün sonra `motion_purge_unconsented_accounts()` ile
   silinir (zamanlama ayrı onaylı operasyon).

**Satın alma (0.8.0, app başına `MotionTeenPurchasePolicy`):** varsayılan
`parentalConsentRequired` — onay bekleyen gence satın alma teklifi gösterilmez
(geri yükleme açık). `storeFamilyControls` seçen app'te teklifler açık kalır ve
ödeme kararı mağazanın aile/ebeveyn denetimine (Ask to Buy, Google Play ebeveyn
onayı) bırakılır; sayfa 18 yaş altı notunu gösterir. Hesap özellikleri iki
politikada da onaya kadar kapalıdır; 13 yaş altı bandı hiç satın alamaz; sunucu
doğrulaması değişmez. **Kurucu K-2 (2026-10-27):** beş app de
`storeFamilyControls` seçer; Core varsayılanı (`parentalConsentRequired`) API
için aynen kalır, hiçbir app'te kullanılmaz. **Dikkat:** onaylanmayan hesap 30 gün sonra silinir
(madde 5); mağaza aboneliği bununla iptal olmaz ve yeni hesapta geri yüklenir —
K-2 ile bu durum beş app'te de oluşabilir (veli onayı almadan mağaza
denetimiyle satın alan genç); etkileşim hukuk/ürün kararına açıktır.

E-posta 14 dilde (`_shared/motion_consent_copy.ts`). Gönderim sağlayıcısı
yapılandırılmadıysa istek `503 mail_unavailable` döner ve kayıt oluşturulmaz.

## Kısa saklama profili

| Veri | Süre | Core mekanizması |
|---|---|---|
| Hesap + ürün verisi | Silmede hemen | `motion-delete-account` → Auth kullanıcı silme; `motion_profiles`, `motion_entitlements`, `motion_age_declarations`, `motion_parental_consents` FK cascade; anonim makbuz (UUID özeti) |
| Diğer cihaz/app yerel verisi | Sonraki çevrimiçi açılış | Makbuz okuma → yalnız onaylı UUID dosyaları silinir; çevrimdışı cihaz bağlanana kadar dosyayı tutar (silme kanıtı yoksa silmez) |
| Uygulama/altyapı logları | ≤ 30 gün | Supabase plan log saklaması (Pro 7 gün); Core istemcisi kimlik/şifre/token loglamaz |
| Yedekler | 30 gün döngü | PITR/yedek penceresi ≤ 30 gün (proje ayarı, ayrı onay) |
| Restore sonrası | Restore'dan hemen sonra | `motion_reapply_deleted_accounts(digests)` — veritabanı dışı silme günlüğündeki özetler yeniden uygulanır: makbuz yeniden yazılır, dirilen Auth kullanıcıları silinir |
| Onaylanmamış genç hesabı | 30 gün | `motion_purge_unconsented_accounts()` |
| Kapanan destek kaydı | 90 gün | Destek kutusu (`support@yulalab.com`) operasyonu; Core dışında |
| Fatura/abonelik | Yalnız yasal süre | Apple/Google mağaza kayıtları (abonelik satışı açık: kurucu kararı 23 Eki 2026, `motionSubscriptionSalesAvailable = true`); Core yalnız `motion_entitlements` hak kaydını tutar, hesap silmede cascade ile gider. Mağaza aboneliği silmeyle iptal olmaz |
| Motion+ deneme defteri (`motion_trial_ledger`) | Hesapla birlikte (silmede cascade) | Hesap başına tek Motion+ ücretsiz denemesi; yalnız uygulama/mağaza/işlem referansı ve başlangıç zamanı, istemci yalnız kendi satırının app/zaman alanlarını okur |

**Silme günlüğü veritabanı dışında tutulmalıdır**: aksi halde restore, restore
noktasından sonraki makbuzları da geri alır. Önerilen: her gün yeni makbuz
özetlerinin (yalnız özet, kişisel veri yok) ayrı, şifreli, ≥ 30 gün saklanan bir
konuma dışa aktarımı. Konum ve iş zamanlaması ayrı servis kararıdır.

## Tek hesap, beş app

Tek Motion hesabı beş app'te ortaktır; silme hepsini etkiler (silme iletişim
kutusu bunu ve diğer cihazların çevrimiçi açılışta temizleneceğini söyler).
Bir app'teki satın alma diğerini açmaz; mağaza aboneliği silmeyle iptal olmaz.
Yaş kısıtı ve veli onayı hesap düzeyindedir: bir app'te verilen onay beşinde
geçerlidir.
