## 0.1.2 — 2026-09-03

Kamera lifecycle sahipliği fail-closed hale getirildi. Android sentetik
always-RESUMED owner yerine gerçek Activity `LifecycleOwner` kullanıyor;
Android/iOS ortak idempotent teardown ve generation guard ile pending start,
bind, capture, inference ve emit yarışlarını geçersiz kılıyor. iOS
`willResignActive` anında kapanır ve aktif olmayan uygulamada yeni başlangıcı
reddeder. `stop()` artık zaten durmuş oturumda da başarıyla döner; iOS aktif
oturumda sonucu fiziksel `stopRunning()` tamamlanmadan bildirmez. Native bridge iki platformun pinli
toolchain'inde yeniden derlendi; fiziksel cihaz canlılık kapısı hâlâ açıktır.

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
