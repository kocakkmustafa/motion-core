# Faz-Config Şeması — UZLAŞTIRMA TASLAĞI v1 (M-F-35)

**Tarih:** 2026-07-29 (gece, tur 6) · **Statü:** TASLAK — üç implementasyoncunun
(Lissom · JabLab · Gravita) diff'i alındıktan sonra mühürlenir ve çekirdek
`PhaseConfig` yorumlayıcısı bu şemaya yazılır. Çelişkide çekirdek kazanır,
ama çekirdek üç ÇALIŞAN motoru okuyarak tasarlanıyor — mühürden önce itiraz
penceresi bu taslaktır.

**Girdiler:** Lissom şema önerisi (koşul cebiri + saniye-birimli delta + iki
değişmez) · JabLab `boxing@1.0.0.json` (localMax, fallback, abort semantiği,
requiredLandmarks, timeout pratiği) · Gravita `movement.schema.json`
(uç-tipi tanıma: `angleMin`=açık uç / `angleMax`=kapalı uç; isim-bağımsız
motor) · L-069/L-070 (P0) · J-009 · J-026 · G-025.

---

## 1. Çekirdek kavramlar

```
teknik/hareket := {
  id, phases: [faz...],
  abort?: { trackingLostMs?, peakNeverReached?, ... },   // JabLab semantiği
  fallback?: bool,        // J-026: spesifik makineyle aynı pencerede özet üretmez
  requiredLandmarks?: [..]  // teknik-düzeyi varsayılan; faz ezebilir
}

faz := {
  id, enter: koşul, exit?: koşul, abort?: koşul, abortCode?,
  timeoutMs?,            // ZORUNLU: terminal olmayan her fazda (değişmez #1)
  minDurationMs?, measureHere?: bool, terminal?: bool,
  requiredLandmarks?: [..]
}

koşul := { kind: metric|delta|timeInPhase|confidence|all|any|localMax, ... }
  metric    := { metric, op: lt|gt|lte|gte, value }
  delta     := { metric, op, valuePerSecond }     // KARE-BAŞINA YASAK (L-069)
                // işaret-tek delta (gt 0 / lt 0) fps-bağımsızdır, serbest
  localMax  := { metric }                          // JabLab PEAK deseni
  all|any   := { of: [koşul...] }
```

## 2. Normatif kurallar (üç motorun dersleriyle)

1. **Delta birimleri SANİYE-başına** (L-069/L-070): kare-başına değer hem
   genlik- hem fps-duyarlı — 60fps'te faz makinesi sessizce durur. Yorumlayıcı
   kare-başına `value` alanını REDDEDER. İstisna: işaret-tek delta (yön).
2. **Terminal olmayan her fazın timeout'u olmalı** (Lissom değişmez #1 +
   JabLab J-009 bağımsız kanıtı: timeout'suz "uzanıp bekleme" yumruk sayıldı).
   Şema doğrulayıcısı zorlar.
3. **"Doğru duruşta hiçbir guard tetiklenmez"** (Lissom A10) — şema değil
   HARNESS değişmezi: her hareketin kapı koşumu, test-özel doğru-duruş
   fixture'ında abort=0 kanıtı ister (L-072 ölü-guard sınıfını yakalar).
4. **Filtre + eşik birlikte pinlenir** (M-C-07/J-027): config
   `signalConditioning` bloğu taşır; eşik değişimi = filtre beyanıyla birlikte
   sürüm artırımı. Hızlı-geçişli metrik `cutoffHz` beyan etmek zorunda (G-V10).
5. **Uç-tipi tanıma korunur** (Gravita): `angleMin`/`angleMax` tarzı bildirimsel
   config, derleme katmanında bu şemanın `metric` koşullarına çevrilir — motor
   isim-bağımsız kalır, içerik yazarı bildirimsel yazabilir.
6. **Taban-değeri beyanı** (G-024 / M-F-34): tolerans taşıyan her metrik,
   kusursuz-durum taban değerini config'te beyan eder (`baseline`); tolerans
   TABAN-göreli yorumlanır. Taban "sıfır sanılıyorsa" ölçülmemiş demektir.
7. `fallback:true` tekniği, spesifik bir makine aynı pencerede tamamlanınca
   veya çalışırken özet üretmez (J-026 çifte-sayım dersi).
8. Bilinmeyen metrik/alan = SERT hata (sessiz yutma yok — M-J-03 dersi:
   beklenmeyeni sessizce boş dönen okuyucu yukarıda P0 üretir).

## 3. Göç yolu (bağlayıcı)

- Üç app MEVCUT formatlarıyla ÇALIŞMAYA DEVAM EDER — kalibre edilmiş çalışan
  motor gece zorla göç ettirilmez.
- Çekirdek `PhaseConfig` yorumlayıcısı bu şemaya yazılır (mühürden sonra);
  her app kendi formatından çekirdek şemaya İNCE çevirici yazar veya doğal
  dokunuş anında göçer. Çeviriciler app-side kalır (içerik sözlüğü çekirdeğe
  sızmaz — Ostinato sınır dedektörü ilkesi).
- Diff penceresi: Lissom/JabLab/Gravita kendi formatlarında bu taslağın ifade
  EDEMEDİĞİ bir şey bulursa M-talebiyle bildirir; sessizlik = onay.
