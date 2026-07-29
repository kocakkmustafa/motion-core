## 0.1.1 — 2026-07-30

iOS Swift katmanı 0.10.21'e karşı İLK KEZ DERLENDİ (J-071) ve iki gerçek
kırık düzeldi: `ImageProcessingOptions` bu sürümde HİÇ YOK; rotasyon
`MPImage(pixelBuffer:orientation:)` ile (.down = 180°). Semantik korunmuş
(geri-eşleme aynen). Android tarafı ilk denemede derlendi (jni .so üç
ABI'de ölçüldü). "Derleniyor ≠ çalışıyor": cihaz koşumu hâlâ §7 canlılık
listesinde.

## 0.1.0 — 2026-07-30

İlk iskelet. Dart katmanı (zarf codec'i, EnvelopeDriver dikişi, PassPlan,
ThroughputMonitor, isimli hata çevirisi) testli; iOS/Android native katman
pinli API'lere karşı yazıldı, PROVISIONAL — canlılık listesi sözleşme §7.
