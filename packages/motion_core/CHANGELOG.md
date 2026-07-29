# Changelog — motion_core

Sürümleme: semver. App'ler pinli sürüm tüketir (git dependency, tag'li:
`motion_core-vX.Y.Z`). Breaking değişiklik = 5 app'in DEFTER'ine kayıt + duyuru.

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
