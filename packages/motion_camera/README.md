# motion_camera

Yula Motion ailesinin native kamera → MediaPipe pose köprüsü.
Sözleşme: [`docs/70-KAMERA-KOPRUSU-SOZLESMESI.md`](../../docs/70-KAMERA-KOPRUSU-SOZLESMESI.md).
Çekirdek görüntü görmez; yalnız landmark zarfları alır. Pinler aynı:
iOS MediaPipeTasksVision **0.10.21**, Android tasks-vision **0.10.29** (M-L-02).

## 0.2.0 kaynak ve kabul durumu

Dart katmanı testlidir. Swift/Kotlin production lifecycle helper'larının host
harness'i platform başına 7 senaryo/40 assertion geçmiştir. **Bu değişmiş native
plugin kaynakları henüz framework/plugin build veya cihaz kabulü görmedi.**
0.1.2'nin tarihsel compile kanıtı bu yeni kaynağı doğrulamaz. Gerçek izin/lifecycle,
CameraX/AVFoundation close, MediaPipe dual graph, timestamp, rotasyon, kaynak
bütçesi ve throughput sözleşme §7.3–7.7'de ayrı kabul kapılarıdır. Medya/model/form
kabulü ve production medya gate bu düzeltmeyle açılmaz.

## Sahipli lifecycle

İzin isteği ve model materialization **öncesinde** `createCaptureLease()` çağır.
Route/logout/background retirement callback'i önce `retire()` çağırmalıdır.
Bu senkron invalidation geç izin/model sonucunun native start yapmasını engeller.
`close()` aynı completion'ı döndürür; yalnız bu owner'ı durdurur, tek native frame
subscription'ını drain eder ve close ACK sonrası yeni nonce ile readback ister.
Owned stream, Flutter `receiveBroadcastStream` callback'inin iptal Future'ını
beklememesi nedeniyle ayrı single-subscription transport kullanır: aynı kanal,
codec ve binaryMessenger ile listen yanıtını ve ownerId+generation taşıyan cancel
RPC yanıtını açıkça bekler. Pending listen/cancel varken close/readback tamamlanmış
sayılmaz; successor start'ı yalnız başarılı `await lease.close()` sonrasında yap.
Listen/cancel hatası veya timeout, beklenmedik stream sonu ve bozuk/error zarfı
lease'i retire ve controller'ı quarantine eder; native capture ACK tek başına
frame transport kabulü değildir. Geç RPC yanıtı quarantine'ı açmaz.
Kimliksiz/eski plugin yanıtı, timeout veya closure hatası uncertain olur ve o
controller yeni owned start'ı reddeder. Belirsiz kapanışı başarı sayma; native
platform da uncertain halde replacement start'ı reddeder.

```dart
final controller = MotionCameraController();
final lease = controller.createCaptureLease(); // permission'dan önce
StreamSubscription<CameraFrameEnvelope>? subscription;

Future<void> open() async {
  final granted = await requestCameraPermission(); // uygulamanın UX'i
  if (lease.isRetired) return;
  if (!granted) { await lease.close(); return; }
  final modelPath = await materializePinnedModel();
  if (lease.isRetired) return;
  await lease.start(modelPath: modelPath, modelId: 'pose_landmarker_full');
  if (lease.isRetired) return;
  subscription = lease.frames().listen(consumeEnvelope);
}

Future<void> dispose() async {
  lease.retire(); // queued permission/model/start beklemesinin arkasına koyma
  await subscription?.cancel(); // yerel app stream'i; native handler'a sahip değil
  await lease.close(); // hatayı kapandı sayma; blocked UI'a taşı
}
```

Uygulama-facing frame bus broadcast'tır. Son app listener'ın iptali native capture
sahipliğini sona erdirmez; bunun için lease'i retire/close et. Eski app listener,
successor başladıktan sonra iptal edilse bile onun native kanal handler'ını
silemez. Owned native listen/cancel ownerId+generation taşır; lifecycle stop,
cancel ve tekrarlanan stop aynı resource close completion'ını bekler.

Android ACK için analysis unbind/readback, CameraState.CLOSED ve her iki
landmarker.close tamamlanır; failure yutulmaz. iOS stopRunning/isRunning readback
ve inference queue drain sonrası pinin public close API'si olmadığı için son
model referansları ARC ile bırakılır. İki orientation ayrı VIDEO graph'ları
kullanır ve aynı gerçek capture PTS'ini alır; timestamp offset eklenmez.

## Uyumluluk ve geçiş

Eski `start/stop/frames/setPassPlan` imzaları korunur. Global legacy `stop()` ve
legacy stream cancel oturum sahipliği sağlamaz; tüketici route fix'i yeni lease
API'sine geçmelidir. Yeni hata enum değerleri `ownedProtocolUnavailable` ve
`closeUncertain` exhaustive switch'lerde ele alınmalıdır. `CameraSessionInfo` ve
`CameraFrameEnvelope` constructor'larına opsiyonel `ownerId`/`generation` eklendi.

Core `f2ea161c` eski tüketici pininden `c8dd6a6d` tabanına camera/audio public API
değişmemiştir; `motion_media` ayrıca eklenmiştir. Bu **yerel WIP 0.2.0** ownership
API'si bu iki immutable Git pininde yoktur. Tüketici kabulü exact yerel patch/source
hash + test ve daha sonra yetkili immutable pin ister; pubspec sürümü registry
yayını veya adopted binary değildir.

Rollback: bu iki paket source patch'i ve tüketici adoption patch'i birlikte geri
alınır; eski plugin'e owned çağrılarda otomatik global fallback yapılmaz.
