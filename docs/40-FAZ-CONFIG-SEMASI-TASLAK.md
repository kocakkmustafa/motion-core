# Faz-Config Şeması — v3.0 MÜHÜRLÜ (M-F-40)

**Tarih:** 2026-07-29 · **Statü:** 🔒 **MÜHÜRLÜ** — beş oturumun beşi onayladı
(Lissom hükmü: "v3 MÜHÜRLENEBİLİR", `docs/talepler/LISSOM-v3-ONAY.md`).
Bu şema artık aile sözleşmesidir: değişiklik = M-talebi + koordinatör kararı +
sürüm artırımı. Çekirdek `PhaseConfig` yorumlayıcısı bu şemaya yazılır;
yorumlayıcı ile şema ayrıştığında ŞEMA kazanır, yorumlayıcı düzeltilir.
İlk gerçek tüketici: Ostinato `voice@0.1.0-draft`.

**v2→v3:** hata kaydına `priority` (F1: safety>blocking>quality — aynı anda
ateşlenen hatalarda GÜVENLİK önce söylenir) ve `perturbation` (F2: tespit
kuralı + onu üreten bozulma AYNI kayıtta; değişmez #11) · varyant-atlanabilir
faz (F3: `skippableIn:[varyant...]`) · işaret taksonomisi bildirimsel (M-J-05.1:
`phase|combinationEnd|periodic{everyMs}|appEvent` — serbest-metin işaret YOK) ·
normatif ayrım (M-J-05.2: **`quality` = SKORLANAN faz-içi kalite; hata katmanı
= KOÇLANAN sorun** — drillId/cooldown taşır; skor ile konuşma farklı kanallar) ·
`verdictGates.effect: collectNoVerdict|discardWindow` (M-O-07: geçerli-ama-
aperiyodik veri TOPLANIR, kirli veri ATILIR — kirli pencereyi arşive toplayan
config sonraki analize temiz görünür) · göç maliyeti düzeltmesi (M-J-05.3:
yalnız baseline değil, metrik başına unit+range+noiseBand+baseline(+cutoffHz)
tam sözlük) · ölçülmüş noiseBand örneği: cent metriği ~20 (Ostinato G1-C).

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
işaret := { kind: phase|combinationEnd|periodic|appEvent,
            phaseId?, everyMs?, event? }
     // M-J-05.1: işaret sözlüğü BİLDİRİMSEL — serbest-metin işaret yasak;
     //   iki app uyumsuz sözlük icat edemez, yorumlayıcı hepsini ateşler.
     //   JabLab STANCE_SAMPLE = periodic{everyMs: 2000}

hata := {
  code,
  evaluateAt: işaret,           // hatalar fazda değil İŞARETTE değerlendirilir
  koşul,
  priority: safety|blocking|quality,   // F1: aynı anda ateşlenende GÜVENLİK
                                       //   önce söylenir; tek-düzeltme
                                       //   disiplini bu alansız kurulamaz
  perturbation?: { metric, targetValue },
     // F2: tespit kuralı + onu üreten bozulma AYNI kayıtta — nöbetçi ancak
     //   ikisini birlikte görünce C-011 sınıfını denetleyebilir
  cooldownMs?, maxPerRound?, suppressesJudgement?: bool, drillId?
}
// NORMATİF AYRIM (M-J-05.2): faz-içi `quality` = SKORLANAN kalite (skora
// akar); bu katman = KOÇLANAN sorun (sesli koça akar). Aynı hüküm iki yerde
// İFADE EDİLMEZ — çapraz-app araçlar tek biçimde akıl yürütür.

combinations := [ { id, sequence: [teknik-id...], maxGapMs?, errors?: [...] } ]
     // J-B: teknik DİZİSİ kavramı; WRONG_HAND/ORDER hataları buradan

faz.skippableIn?: [varyant...]  // F3: varyanta göre atlanabilir faz —
                                //   tek fazlık fark için zincir kopyalanmaz
```

## 4. Olay-tetikli hüküm pencereleri (O-A3 + CueGate politika notu)

```
verdictGates := [ { onEvent: <olay>, holdMs,
                    effect: collectNoVerdict | discardWindow } ]
```
- **`collectNoVerdict`** (Ostinato atak penceresi): veri GEÇERLİ, yalnız
  aperiyodik — toplanır, hüküm verilmez. **`discardWindow`** (koç sesi,
  mikrofon kirli): veri KİRLİ — toplanmaz; toplansaydı arşivdeki sonraki
  analiz onu temiz sanırdı (M-O-07).
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
11. **Perturbasyon hedefi eşiği en az `noiseBand` kadar aşmalı** (Gravita F2:
    `noiseBand` zaten zorunlu olduğundan bedava denetim — toleransın içinde
    kalan fixture hiçbir şey sınamaz, C-011).

## 7. Göç yolu (değişmedi + JabLab uyum notu)

- Mevcut formatlar çalışmaya devam eder; çeviriciler app-side.
- JabLab göç kalemi (planlı): oran-metriklerine `baseline` yazımı.
- Ostinato: kalibre motoru olmadığı için mühürden sonra DOĞRUDAN bu şemaya
  yazar (çevirici gerekmez) — tek şartı A1-A3 çözümüydü, v2'de çözüldü.
- Diff penceresi: **Lissom diff'i bekleniyor**; sonrasında bir onay turu ve
  MÜHÜR. Mühürden sonra çekirdek `PhaseConfig` yorumlayıcısı yazılır.
