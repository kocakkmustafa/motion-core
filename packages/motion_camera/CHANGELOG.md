## 0.3.0 — 2026-10-27 — Flutter Built-in Kotlin

Android eklentisi Kotlin Gradle Plugin'i (`kotlin-android`) artık uygulamıyor;
`kotlinOptions` yerine `kotlin.compilerOptions` (JVM 17) kullanılır (Flutter
"migrate to built-in Kotlin — plugin authors" kılavuzu; `in_app_purchase_android`
0.5.3 ile aynı desen). Asgari sürüm Flutter 3.44 / Dart 3.12. Dart API'si ve
native davranış değişmedi.

## 0.2.0 — 2026-10-02 — yerel kaynak, native kabul açık

`CameraCaptureLease` ve ek `startOwned/stopOwned/readback/setPassPlanOwned`
protokolü eklendi. İzin/model beklemesinden önce oluşturulan lease hemen retire
edilebilir; denied/stale owner successor'ı durdurmaz. Kapanış tek native stream
subscription'ını da drain eder, native ACK ardından yeni nonce ile exact owner
readback ister. Eski global `start/stop/frames/setPassPlan` API'leri korunur;
route sahipliği için yeni lease'e tüketici geçişi gerekir. Yeni failure enum
değerleri `ownedProtocolUnavailable` ve `closeUncertain` exhaustive switch'lerde
ele alınmalıdır; eski plugin'e sessiz fallback yoktur.

İki platformun stop/cancel/lifecycle yolu tek fiziksel/model close completion
paylaşır; hata sticky uncertain olur. Android CameraState.CLOSED/unbind ve bütün
landmarker.close çağrıları beklenir. iOS stopRunning readback ve inference drain
ardından pinin public close API'si olmadığı için son model referansları bırakılır.
Dual pass ayrı VIDEO graph'larıyla aynı gerçek capture timestamp'ini kullanır.

Swift ve Kotlin gerçek helper kaynakları host harness'te ayrı ayrı 7 senaryo/40
assertion geçti. Bu değişmiş plugin dosyaları henüz pinli framework/plugin build,
MediaPipe çalışması veya fiziksel cihaz kabulü görmedi; geçmiş 0.1.2 compile
kanıtı bu kaynağa aktarılmaz. Production medya gate kapalı kalır.

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
