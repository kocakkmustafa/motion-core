# Yula Motion Ailesi — Mimari Sözleşme ve Bağlayıcı Plan Ekleri

**Tarih:** 2026-07-25 · **Statü:** Kurucu onaylı (monorepo + isim kararları AskUserQuestion ile)
Bu doküman 4 plan dokümanının ÜSTÜNDE bağlayıcıdır: çelişkide bu dosya kazanır. Planlar (GPT-5.6): `gravita-plan.md` · `lissom-plan.md` · `jablab-plan.md` · `ostinato-plan.md`.

## 1. Aile ve isimler (kurucu kararı, App Store taramasıyla doğrulandı)

| App | Ürün | Plan dosyası | Durum |
|---|---|---|---|
| **Gravita** | Handstand & vücut becerileri koçu | gravita-plan.md | hazırlık |
| **Lissom** | Esneklik/yoga/mobilite ölçüm + günlük program (kurucu: yoga+esneklik kapsamda) | lissom-plan.md | hazırlık |
| **JabLab** | Solo boks / shadow boxing koçu | jablab-plan.md | hazırlık |
| **Ostinato** | Genel enstrüman pratik koçu — **marka genel, V1 çelloda derinleşir** (plan şartıyla uyumlu) | ostinato-plan.md | hazırlık |

### 1.1 Kapsam direktifi (kurucu, 2026-07-25 — bağlayıcı)
**Vizyon kapsamı TAMDIR; V1 sınırları ürün tavanı DEĞİL, mühendislik sırasıdır.** Hiçbir V1 kısıtı vizyonu daraltma gerekçesi yapılamaz:
- Dört üründe de çekirdek vaat: **"karşında antrenörün/öğretmenin varmış gibi"** — kullanıcıya durması gereken pozisyonu söyleyen, antrenmanı/yogayı/esnemeyi/pratiği doğru formda yaptıran **sesli gerçek-zamanlı yönlendirme**. (Tek kişi + tek kamera senaryosu ürünlerin doğal avantajı: çoklu-kişi karmaşası yok.)
- **Ostinato çelloyla SINIRLI DEĞİLDİR:** fiziksel/teknik sınırları aşmayan TÜM çalgılara genişler; çello yalnız ilk motordur, mimari enstrüman-bağımsız kurulur (ortak çekirdek: pose+hand+audio+öğretmen akışı).
- Dört ürün **ayrı ayrı ürünlerdir ve ayrı yayınlanır** (kendi store kaydı, markası, sayfası) — kod paylaşımı bu bağımsızlığı etkilemez.

⚠️ **Ad rezervasyonu bekliyor:** İsimler mağazalarda taranıp temiz bulundu (2026-07-25) ama HENÜZ rezerve edilmedi. Kamuya açılmadan önce ASC/Play'de app kaydı açılmalı (kurucu-onaylı işlem). Site coming-soon dalı bu yüzden yayınlanmadan bekliyor.

## 2. Monorepo yapısı (kurucu kararı: tek monorepo `yula-motion`)

```
yula-motion/  (bu repo)
├── docs/                       # bu dosya + 4 plan (kanonik ürün bağlamı)
├── packages/
│   └── motion_core/            # ORTAK ÇEKİRDEK (aşağıda) — kod başlayınca ilk kurulan paket
└── apps/
    ├── gravita/ · lissom/ · jablab/ · ostinato/
```
Araç önerisi: Flutter + melos. Store'a 4 ayrı app çıkar; çekirdek tek kaynaktan akar.
**KOD BAŞLATMA KİLİDİ: kurucu "X'e başlayalım" demeden hiçbir app'te üretim kodu yazılmaz.** Bu repo o güne kadar yalnız doküman taşır.

### motion_core kapsamı (4 planın kesişimi, ~%70 ortak)
Kamera kalibrasyon sihirbazı · pose bridge (Kotlin/Swift ↔ MediaPipe) · landmark güven kapısı · temporal smoothing · vücut-oranı normalizasyonu · state-machine çatısı · versiyonlu rule-set motoru · feedback önceliklendirici + cooldown · skor bileşenleri · replay/fixture test harness · yerel depolama (Drift/SQLCipher deseni LifeOS'tan) · gizlilik katmanı (ham video cihazda) · TTS/ses geri bildirim.
App'e özgü kalanlar: beceri/teknik state-machine tanımları, rule-set içerikleri, progresyon grafikleri, içerik. Ostinato ek olarak: nesne algılama (YOLO çello/yay) + ses analizi + ses-hareket senkronu — **bunlar core'a değil ostinato'ya aittir** (aile bunlarsuz yaşar).

## 3. Bağlayıcı plan düzeltmeleri (D1-D4)

**D1 — Gravita / ters-duruş fizibilitesi (P0 kapı):** MediaPipe Pose ağırlıkla dik insan görüntüsüyle eğitilmiştir; handstand = baş aşağı vücut → landmark güveni ciddi düşebilir. Planda bu risk YOK. **V0 kapısı:** üretim koduna başlamadan, kayıtlı ters-duruş videolarında landmark güven/isabet ölçümü; eşik altıysa model alternatifi (MoveNet varyantları / custom fine-tune / görüntüyü 180° çevirip infer etme hilesi) kararı kurucuya gelir.

**D2 — JabLab / hızlı yumruk örnekleme problemi:** Jab peak-extension 20-30fps'te 1-2 kare + motion blur. Hız metrikleri kare-arası pikselden DEĞİL faz-süresinden (state-machine timestamp'leri) türetilir; fixture setine "hızlı yumruk + düşük fps + blur" senaryoları zorunlu; cihaz-adaptif fps politikası V0'da ölçülür.

**D3 — Ostinato farklı ağırlık sınıfı:** Özel nesne algılama (çello+yay) + veri seti toplama/etiketleme + ses-hareket senkronu + çocuk verisi rejimi = diğer app'lerin 3-5 katı efor. **Sıralamada SON; V0'ı "veri toplama protokolü + öğretmen kanalı doğrulaması"dır**, kod değil. B2B (öğretmen/müzik okulu) sinyali alınmadan derin yatırım yapılmaz.

**D4 — Lissom kapsam güncellemesi (kurucu):** Ürün yalnız mobilite ölçümü değil; **yoga + esneklik içerik katmanı** kapsama dahil. Planın "Mobility Age" indeks-adlandırma uyarısı geçerli: yaş dili YOK; "Lissom Score / hareket kapasitesi" dili kullanılır. Ölç-programla-yeniden-ölç döngüsü çekirdek kalır; yoga akışları program motorunun içerik paketleridir (ayrı ürün değil).

## 4. Sıralama tavsiyesi (teknik risk artan sırada; başlangıç tetiği daima kurucu)
**Lissom → JabLab → Gravita → Ostinato.**
Gerekçe: Lissom = yavaş/statik pozlar (pose modeli en güvenilir bölgesi) + en geniş pazar + ailenin ortak değerlendirme katmanı (Gravita bilek/omuz ön-şartları, JabLab ısınması buradan beslenir). JabLab = dik vücut ama hızlı hareket (D2). Gravita = ters-duruş riski (D1). Ostinato = D3.

## 5. Uyum kapıları (her app, V1 submit ÖNCESİ zorunlu)
1. `privacy-data-guardian` turu: KVKK/GDPR — kamera+vücut analizi; on-device işleme + yüz-tanıma-yok + ham-video-yok üçlüsü her beyanda açık.
2. Store beyanları: wellness dili (tıbbi iddia sıfır — Lissom planı §13 kaçınılacak ifadeler AİLE GENELİ geçerli); Apple 5.1.1 veri; kamera izin gerekçe metinleri.
3. Art.50 (EU AI Act) değerlendirmesi LifeOS şablonundan uyarlanır (`ART50-BEYAN-TURU.md` deseni).
4. Ostinato ek: çocuk verisi (ebeveyn izni, saklamama varsayılanı, model-eğitimi ayrı rıza) — plan §13 bağlayıcı.
5. Ortak hesap gerçeği: aynı Apple Team (T5HZGYBWK8) + Play hesabı → hesap-geneli politika olayları 4 app'i birden etkiler (`holding/registry/connections.yaml`).

## 6. Aile-içi ve aile-dışı bağlar
- Lissom → LifeOS "hareket sağlığı modülü" ADAYI (uzun vade; plan §21). Kod bağı yok, kayıt `connections.yaml`'da.
- Lissom skorları → Gravita/JabLab ön-koşul kapıları (aile-içi API, motion_core sözleşmesiyle).
- Planlarda **Solo Dance** referansı var — 5. ürün planı henüz yok; kurucu karar verirse aynı monorepo'ya `apps/` altına eklenir.

## 7. Ölçüm dürüstlüğü (BF mirası — pazarlanan her sayı için)
Doğruluk/başarı iddiası yayınlanacaksa: zaman-doğru, out-of-sample, koşullarıyla etiketli (BF'nin "eğitim backtest'i" dersi). "Analiz edemedim" demek, yanlış hüküm vermekten HER ZAMAN üstündür — bu ilke 4 planda da var, korunur.
