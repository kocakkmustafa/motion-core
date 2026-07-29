# Faz-Config Şeması — UZLAŞTIRMA TASLAĞI v2 (M-F-35/36)

**Tarih:** 2026-07-29 (gece, tur 7) · **Statü:** TASLAK v2 — dört oturumun
diff'leri işlendi (Gravita D1-D5+2 değişmez · JabLab M-J-04 A-D · Ostinato
A1-A3 · Choreia M-C-24). **Mühür şartı:** Lissom diff'i (bekleniyor) + bir
onay turu. Çelişkide çekirdek kazanır; ama bu sürüm DÖRT çalışan/tasarlanan
motorun itirazlarıyla yazıldı.

**v1→v2 değişiklik özeti:** tekrar/döngü modeli (D1) · giriş-eşiği↔kalite-hedefi
ayrımı (D2) · checkpoint fazı (D3) · taraf-çözümü + `limb` (D4+J-A) ·
metrik sözlüğünde `range`/`noiseBand`/`baseline` zorunlu (D5+M-F-34) ·
`combinations` (J-B) · hata/geri-bildirim katmanı (J-C) · `branchProfiles`
(J-D) · aralık-ölçüm + sinyal-önkoşulu + olay-tetikli hüküm-penceresi
(O-A1/A2/A3) · `localMin`/boolean/kategorik koşullar (C) · değişmez #9/#10.

---

## 1. Çekirdek kavramlar

```
hareket/teknik := {
  id, limb?,                    // J-A: değerlendirilen zincir SOYUT adla
                                //   (lead_arm/rear_arm/visible_leg...);
  sideResolution,               // D4 ZORUNLU: visible|calibrated|explicit —
                                //   soyut adın L/R'ye NASIL bağlandığı.
                                //   M-F-06: config'te LEFT_*/RIGHT_* YASAK.
  cyclic?: bool,                // D1: tekrarlı teknik (şınav, jab dizisi)
  repCompletedOn?: "faz->faz",  // D1: tekrarın sayıldığı geçiş
  resetBetweenReps?: [alan...], // D1: tekrar arasında SIFIRLANAN durum —
                                //   açık liste; yoksa 2. tekrarın ROM hükmü
                                //   1.'nin uç değerini taşır (G ölçümü)
  phases: [faz...],
  abort?: { trackingLostMs?, peakNeverReached?, koşul? },
  fallback?: bool,              // J-026: spesifik makineyle aynı pencerede
                                //   özet üretmez
  requires?: { landmarks?: [..], signals?: [..] },
                                // O-A2: ses-öncelikli app'in ön-koşulu
                                //   sinyal kalitesidir (SNR, periyodiklik,
                                //   MIDI-bağlı) — landmark değil.
                                //   requiredLandmarks eski adıyla okunur.
  branchProfiles?: { <brans>: { <metrik>: {expected, tolerance} } }
                                // J-D: ADR-004 mekanizması — aynı ölçü,
                                //   branşa göre farklı beklenen değer
}

faz := {
  id,
  enter: koşul,                 // "bu faza GİRDİM mi" — sayım sorusu
  quality?: { <metrik>: hedef },// D2: "bu fazı İYİ yaptım mı" — hüküm sorusu.
                                //   G-027 dersi: giriş koşulu doğru ama
                                //   ayırt-etmez olabilir; iki soru ayrı yazılır
  exit?: koşul, abort?: koşul, abortCode?,
  timeoutMs?,                   // ZORUNLU: terminal olmayan her fazda (değ.#1)
  minDurationMs?, measureHere?: bool, terminal?: bool,
  checkpoint?: bool,            // D3: bu faz SKORLANMAZ, yalnız koçlanır —
                                //   "blur'lu fazlar checkpoint" aile kuralı
                                //   artık config'te ifade edilebilir
  requires?: {...}              // teknik-düzeyini ezebilir
}

koşul := { kind: metric|delta|timeInPhase|confidence|all|any|
                 localMax|localMin|flag|category|intervalOverlap, ... }
  metric   := { metric, op: lt|gt|lte|gte|eq, value }
  delta    := { metric, op, valuePerSecond }  // KARE-BAŞINA YASAK (L-069);
                                              // işaret-tek delta serbest
  localMax := { metric } · localMin := { metric }        // C: alt-faz uçları
  flag     := { metric, is: true|false }                 // C: boolean metrik
  category := { metric, in: [değer...] }                 // C: kategorik metrik
  intervalOverlap := { of: [olay-ref, olay-ref], minOverlapMs? }
             // O-A1: ölçümler NOKTA değil ARALIK taşıyabilir
             //   (değer + tStartUs/tEndUs); füzyon koşulu ("yay yönü değişti
             //   VE ses kesildi") aralık-kesişimidir, an-eşitliği değil
  all|any  := { of: [koşul...] }
```

## 2. Ölçüm sözlüğü (metrik başına ZORUNLU alanlar)

```
metrik := {
  id, unit,
  range: [min, max],       // D5: fiziksel aralık — G-016 sınıfı (206° diz)
                           //   config yazım anında reddedilir
  noiseBand,               // D5: bu bandın altındaki fark hüküm üretmez
  baseline,                // M-F-34: kusursuz-durum taban değeri; tolerans
                           //   TABAN-göreli. Ses tarafında taban sabit değil
                           //   REFERANS olabilir (beklenen nota) →
                           //   baseline := value | {ref: "..."} (O uyarlaması)
  interval?: bool,         // O-A1: değer pencere-aralıklı mı (tStart/tEnd)
  cutoffHz?,               // hızlı-geçişli metrikte ZORUNLU (G-V10/J-027)
}
```

## 3. Hata/geri-bildirim katmanı (J-C — fazların DIŞINDA)

```
hata := {
  code,
  evaluateAt: ANY | <faz-id> | COMBINATION_END | <işaret>,
     // hatalar fazda değil İŞARETTE değerlendirilir — sesli koçun tur-içi
     // tek-düzeltme disiplini buna dayanır
  koşul, cooldownMs?, maxPerRound?, suppressesJudgement?: bool
}
combinations := [ { id, sequence: [teknik-id...], maxGapMs?, errors?: [...] } ]
     // J-B: teknik DİZİSİ kavramı; WRONG_HAND/ORDER hataları buradan
```

## 4. Olay-tetikli hüküm pencereleri (O-A3 + CueGate politika notu)

```
verdictGates := [ { onEvent: <olay>, holdMs, effect: collectNoVerdict } ]
```
- Üçüncü durum: **ölç ama hüküm verme** — faz-yapısal değil OLAY-tetikli
  (yay değişimi sonrası ~100 ms; Ostinato üç-durumlu kapısı).
- **CueGate politika notu (JabLab dersi):** çekirdek `CueGate` yalnız ZAMAN
  penceresi verir; pencerede NEYİN susturulacağı app politikasıdır —
  Ostinato'da her şey susar (mikrofon kirlenir), JabLab'da tespit sürer
  hüküm susar (kamera kirlenmez; kullanıcı düzeltmeye tepki veriyordur).
  Körlemesine kopya iki yönde de yanlış üretir.

## 5. Normatif kurallar (v1'den — değişmedi)

1. Delta birimleri SANİYE-başına (L-069/L-070); işaret-tek delta serbest.
2. Terminal olmayan her fazın timeout'u ZORUNLU (Lissom değ.#1 + J-009).
3. "Doğru duruşta guard=0" HARNESS kanıtı (Lissom A10; L-072 ölü-guard sınıfı).
4. Filtre + eşik birlikte pinlenir (`signalConditioning`; M-C-07/J-027 —
   Ostinato YIN-eşiği×pencere-boyu ile ses tarafında da doğrulandı).
5. Bildirimsel katman (angleMin/angleMax) derlenerek korunur (Gravita).
6. Taban-değeri beyanı (M-F-34).
7. `fallback` çifte-sayım koruması (J-026).
8. Bilinmeyen alan/metrik = SERT hata (M-J-03).

## 6. Doğrulayıcı değişmezleri (yeni: #9-#10)

9. **Karşıt uç koşulları birbirini dışlamalı** (Gravita V11: iki uç eşiği
   örtüşürse her kare iki uçta birden sayılır, motor durmadan tekrar üretir).
10. **Ölü-metrik yasağı** (M-L-05): sabit değer üreten metrik yükleme anında
    reddedilir.

## 7. Göç yolu (değişmedi + JabLab uyum notu)

- Mevcut formatlar çalışmaya devam eder; çeviriciler app-side.
- JabLab göç kalemi (planlı): oran-metriklerine `baseline` yazımı.
- Ostinato: kalibre motoru olmadığı için mühürden sonra DOĞRUDAN bu şemaya
  yazar (çevirici gerekmez) — tek şartı A1-A3 çözümüydü, v2'de çözüldü.
- Diff penceresi: **Lissom diff'i bekleniyor**; sonrasında bir onay turu ve
  MÜHÜR. Mühürden sonra çekirdek `PhaseConfig` yorumlayıcısı yazılır.
