# Changelog — motion_core

Sürümleme: semver. App'ler pinli sürüm tüketir (git dependency, tag'li:
`motion_core-vX.Y.Z`). Breaking değişiklik = 5 app'in DEFTER'ine kayıt + duyuru.

## 0.6.1 — 2026-07-29 (tur 23)

- **Tolerans-kaynağı etiketi (G-050/M-F-55, Gravita'nın bulgusu):** ilk gerçek
  referansta 9/9 eklemin dağılımı (5,9-8,0°) 8° tabanının ALTINDA çıktı —
  yayımlanan her tolerans varyans kılığında tabandı. `ToleranceSource`
  (`variance|floor|ceiling|unmeasured`) + `toleranceSourceAt()` +
  `floorBoundShare()` (eklem-başına taban-bağlılık oranı; 1.0 = tolerans bir
  kez bile ölçülmüş ayrışmadan gelmedi). Yalnız `variance` "varyans-türetimli"
  iddiasını taşıyabilir; taban bağlıyorken G-014 kapanmaz. Test: 167/167
  (sıkı-küme=floor + stilli-kol=variance karşıt-çifti).

## 0.6.0 — 2026-07-29 (tur 22)

- **Fixture şema-v2 köprüsü (referans-CLI ön şartı):** Dart okuyucu ile Python
  hasat hattı (mocore SCHEMA_VERSION=2) iki lehçeye ayrışmıştı — Dart v2
  dosyayı REDDEDİYORDU. Algoritmayı Python'da yeniden yazmak M-F-21 sınıfı
  çifte-üretim olurdu; köprü tek sınırda kuruldu:
  * `readableSchemaVersions = {1,2}` (yazıcı v1'de kalır — Python'la aynı
    desen: okuyucu ileride, yazıcı güncel-yazdığında).
  * Kompakt kare lehçesi: `t` ms→µs · `lm[[x,y,z,vis,presence]]` →
    `PoseLandmark` (presence BİLİNÇLİ düşülür — tüm kapı eşikleri visibility
    ile kalibre; katlamak hepsini sessizce kaydırırdı).
  * Tespitsiz kare 33 sahte-sıfır landmark'la DOLDURULMAZ — düşülür ve
    `undetectedFrameCount` ile sayılır (boşluk zaman sıçraması + sayaçtan
    görünür; kapsam matematiği şişmez).
  * `ProvenanceInfo` (sourceUrl/license/channel/extractor + ham blok) —
    `sourceIdentity` = minSources kapısının "bir eğitmen" kimliği.
  * `RecordingMeta`: snake_case anahtar kabulü + `technique` + `resolution`
    → `frameSize` (J-028 izotropik düzeltme girdisi).
- Doğrulama: 166/166 test (6 yeni köprü testi) + 3 GERÇEK hasat fixture'ı
  (~/motion-harvest, 7.6k-11.7k kare) uçtan uca çözüldü; source alanı gerçek
  kanal kimliklerine bağlandı. Not: hasat dosyalarında technique=unknown —
  hareket kimliği manifest'tedir, CLI tekniği argümandan alacak.

## 0.5.1 — 2026-07-29 (tur 21)

- **`ReferenceBuilder.minSources` kapısı (M-F-53(2), Gravita'nın bulduğu sayım
  boşluğu):** `minTakes` TEKRAR sayar, M-F-38 EĞİTMEN sayar — tek eğitmenin 12
  tekrarı sayı-kapısını geçer ama eğitmenler-arası varyans (dispersiyon-türevli
  toleransın TEK kaynağı) hakkında sıfır bilgi taşır. İki kontrol noktası:
  * ham girişte distinct `source` < `minSources` (varsayılan 3) → `ArgumentError`
    (fail-closed; `minSources: 1` yalnız BEYAN EDİLMİŞ tek-eğitmen prototipi
    için — toleransı "stil" olarak okumayı üstlenerek).
  * M-F-47 anlaşma-kapısı SONRASI küme içinde de sayılır: aykırı-dışlama bir
    take değil bir İNSANI düşürdüyse (take sayısı hâlâ yeterli görünürken)
    `ReferenceAgreementError` — sayı-kapısının yapısal olarak göremediği durum.
- Test: 160/160 (3 yeni — aynı-kaynak reddi, prototip kaçış kapısı,
  küme-kaynak-çöküşü; süit sonucu sürüm notundan ÖNCE koşuldu ve görüldü).

## 0.5.0 — 2026-07-29 (tur 18)

- **ReferenceBuilder büyük yükseltme (M-F-47/48 + M-J-06):**
  * `resolveMirroring` GLOBAL atama problemi olarak çözülür (tam tarama n≤12,
    take-0 sabit; çift pair-cost tablosu) — "dosya sırasına bağlı uzlaşma
    uzlaşma değildir" (Choreia ölçümü). Mutlak konvansiyon: AZINLIK çevrilir;
    yakın-beraberede HİÇ çevrilmez + `confident:false` raporlanır.
  * `build(..., leadSidePrior:)` — ölçülmüş öncü-taraf önseli konsensüsü
    ezer, uyuşmazlık RAPORLANIR (n küçükken yanlış-çözülen konsensüs sessiz).
  * **M-F-47 anlaşma kapısı:** sayı kapısı anlaşmayı ölçmez — take-başına
    medyan-eklem sapması ≤14° kümesi ister; aykırı ADLA dışlanır
    (`excludedOutlierIds`), küme<minTakes → `ReferenceAgreementError`.
    İstatistik seçimi kuralın anlamını taşır: farklı-hareket çoğu eklemde
    sapar (medyan yüksek → dışla), stil azınlık eklemde (tolerans olur,
    dışlanmaz).
  * `CanonicalReference` yeni alanlar: mirrorConfident/excludedOutlierIds/
    priorDisagreements. 158/158.

## 0.4.3 — 2026-07-29 (tur 15)

- **G-038 (P1) bileşim kusuru:** `ConfidenceGate.evaluate` artık `xExtent`
  alır — izotropik uzayda x ∈ [0, aspect]; ham [0,1] sınırıyla kapılamak
  sağ-yarı deneği sessizce "kadraj dışı" sayıyordu (ölçüldü: %5-14 → %0).
  Bileşim testi eklendi. Ayrıca fixture `t` birim beyanı (G-040: birim de
  bir beyandır — ms). 155/155.

## 0.4.2 — 2026-07-29 (gece vardiyası, tur 12b)

- **M-J-07: `$` önekli anahtar her düzeyde yok sayılır** — "sayı kendi
  gerekçesini taşır" aile pratiği config'te yaşar; kural 8'in katılığı
  değişmedi (yazım hatası hâlâ sert hata — testli). 154/154.

## 0.4.1 — 2026-07-29 (gece vardiyası, tur 12)

- **Okuyucu, mühürlü şemaya hizalandı (M-O-10 + Gravita M-talebi):**
  `verdictGates` parse ediliyor (collectNoVerdict/discardWindow — atlanmıştı) ·
  `requires:{landmarks,signals}` iç-içe biçim + sinyal ön-koşulları op/value
  taşır (SNR ≥6dB artık düzyazı değil) · `measurementSpace: world|isotropic|
  pixel` (M-O-08/J-028) · `fastTransition` bayrağı + cutoffHz zorunluluğu
  ARTIK DOĞRULANIYOR (düzyazı-kural kod-kuralı oldu) · `ErrorSpec.cue`
  (koçun söyleyeceği söz — içeriksiz koçlanan hata sessizce düşer).
  5 yeni test; 152/152. Şema-tarafı kalanlar (quality yön-bilgisi,
  signalConditioning yuvası, evaluateAt doc netleşmesi) v3.1 kalemi.

## 0.4.0 — 2026-07-29 (gece vardiyası, tur 11)

- **`PhaseConfig` — mühürlü v3.0 şemasının kanonik okuyucusu (M-F-40):**
  model + KATI parser (bilinmeyen alan = sert hata; kare-başına delta parse
  anında red — L-069) + aile-değişmezleri doğrulayıcısı (#1 timeout/J-009 ·
  D1 cyclic/repCompletedOn · M-F-06 ham-taraf yasağı · tanımsız-metrik ·
  G-016 menzil · #9 uç-örtüşmesi/V11 · #11 perturbasyon≥noiseBand/C-011).
  Bu artırım = config linter'ı (5 app bugün koşabilir); PhaseStateMachine
  evaluator'ı sonraki artırım. 13 test; toplam 148/148.

## 0.3.0 — 2026-07-29 (gece vardiyası, tur 5)

- **`FrameSize` + `PoseFrame.toIsotropic` (M-F-30/J-028 kanonik API):** ham
  normalize uzay anizotropiktir; geometriye girmeden önce izotropik uzaya
  (kare-yüksekliği birimi) dönüşüm artık çekirdekte. Üç app'in gece bağımsız
  yazdığı düzeltme (JabLab FrameSize · Gravita toIsotropic · Choreia
  aspect-corrected lm) bu API'de birleşir; app-side kopyalar devredilir.
  Değişmezlik-deseni testli (eğik-açı sondası; eksene-hizalı açı ölçeklemede
  bükülmez — o tuzak testin kendisinde kapatıldı). Toplam: 135/135.

## 0.2.1 — 2026-07-29 (gece vardiyası, tur 4)

- **G-018 kalibrasyonu:** `StructuralValidator.bilateralTolerance` varsayılanı
  0.35 → 0.55 — eski değer Gravita D1 gerçek-kare setinde DOĞRU karelerin
  %32'sini reddediyordu (2D perspektif kısalması; model hatası değil). 0.55'te
  yanlış-red ~%8-11, #21 kendinden-emin takas hâlâ yakalanıyor (Gravita
  regresyon fixture'ı kanıt). Davranış değişikliği: yapısal denetimi ham
  varsayılanla kullanan app'ler daha az yanlış-red görür.
- Hasat rig'i: `--triage-profile` CLI (Lissom) + `movement_isolator`
  (Choreia terfisi — "bu kısım hareketin kendisi mi?" periyodiklik+enerji
  penceresi; anlatım-eleme). Rig testleri 17/17.

## 0.2.0 — 2026-07-29 (gece vardiyası)

- **`CycleAligner` (M-C-18, Choreia blokajı):** periyodik içerik için
  döngü-farkında hizalama — sabit-uçlu DTW'nin faz uyuşmazlığında dayattığı
  kötü hizalama yerine faz araması + döngü-başına bantlı `Dtw`. Belirsiz fazda
  (statik/faz-simetrik malzeme) `resolved:false` = hüküm yok; iki-döngü
  kararlılık sondası; periyotlar ÇAĞIRANDAN gelir (tahmin edilmez). 6 test.
  Kırılma yok — `Dtw` API'si aynen duruyor. Toplam: 132/132.

## 0.1.0 — 2026-07-29 (ilk etiketli sürüm)

Kanonik Dart çekirdeğinin ilk kararlı kesiti (M-017/M-F-03 hükmü: bu paket
çalışma-zamanı motorunun normatif referansıdır; Python `mocore` yalnız
video→fixture/G1-ölçüm aracıdır).

### Modüller
- **pose:** `PoseFrame` · `ConfidenceGate.forVariant` (M-018/M-020) ·
  `StructuralValidator` (M-019; `check(frame, expected:)` faz-eksen denetimi
  dahil — G-010) · `BodyOrientation`/`observedOrientation` ·
  `OrientationAwarePoseSource` (Gravita ADR-001: beklenti + histerezis +
  belirsiz fazda çift-geçiş) · smoothing.
- **geometry:** `Vec3` · normalizasyon (orta-hat referanslı) · eklem açıları.
- **scoring:** açı-benzerliği · bantlı DTW + `warpPenalty` (M-C-05 park-etme
  düzeltmesi) · `SequenceComparator` · `ReferenceBuilder` (M-C-04: ≥3 eğitmen,
  aynalama konsensüsü, varyans→tolerans).
- **rhythm:** `BeatGrid` · `PerceivedBeatTimeline` + `AudioLatencyProfile` ·
  `LatencyCalibrationStore`/`TapTestCalibrator` (M-F-08, route-başına) ·
  `CueGate` (koç-sesi analiz zaman-kapısı) · `TimingJudge`.
- **engine:** faz durum-makinesi çatısı · feedback önceliklendirici+cooldown ·
  `MotionClock` (audio+motion tek monotonic saat sözleşmesi) ·
  `AttemptProvenance` (M-F-07: karşılaştırılabilirlik kapısı).
- **fixture:** fixture/replay harness · sentetik iskelet üreticisi + gürültü.

### Test
123 test yeşil; `dart analyze` temiz.

### App'lere pinleme talimatı
```yaml
dependencies:
  motion_core:
    git:
      url: https://github.com/kocakkmustafa/motion-core.git
      ref: motion_core-v0.1.0
      path: packages/motion_core
```
