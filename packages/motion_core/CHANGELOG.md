# Changelog — motion_core

Sürümleme: semver. App'ler pinli sürüm tüketir (git dependency, tag'li:
`motion_core-vX.Y.Z`). Breaking değişiklik = 5 app'in DEFTER'ine kayıt + duyuru.

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
