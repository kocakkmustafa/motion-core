# motion_camera

Yula Motion ailesinin native kamera → MediaPipe pose köprüsü.
Sözleşme: [`docs/70-KAMERA-KOPRUSU-SOZLESMESI.md`](../../docs/70-KAMERA-KOPRUSU-SOZLESMESI.md).

- Çekirdek görüntü görmez: yalnız monoton saatli landmark zarfları.
- Pinler (M-L-02): iOS MediaPipeTasksVision **0.10.21** · Android tasks-vision **0.10.29**.
- Lifecycle sözleşmesi: `stop()` idempotenttir; iOS sonucu ancak kuyruğa alınmış
  `stopRunning()` tamamlandıktan sonra döndürür. Event stream iptali, Android
  Activity `onStop`/detach/config-change, iOS `willResignActive` ve iki
  platformda engine detach aynı teardown yolunu kullanır. iOS yalnız uygulama
  aktifken yeni oturum başlatır. Her başlangıç yeni bir
  generation alır; eski bind/inference/emit callback'leri yeni oturuma veri
  taşıyamaz.
- Durum: Dart katmanı testli; native katman **COMPILED-NOT-RUN** — iOS ve
  Android İKİSİ DE pinli sürümlere karşı DERLENDİ (J-071; §7.1-7.2 geçti),
  ama **hiçbir cihazda KOŞMADI**. "Derleniyor" ile "çalışıyor" ayrı
  beyanlar: gerçek sayılar (judgedRatio · meanInferenceUs · dual-pass
  maliyeti · buffer-tutma · clock-domain · ters-geçiş fikstürü) sözleşme
  §7.3-7.7'de AÇIK.

```dart
final controller = MotionCameraController();
final driver = EnvelopeDriver();
final source = OrientationAwarePoseSource(driver);
final monitor = ThroughputMonitor();

await controller.start(
  modelPath: modelFile.path,
  modelId: 'pose_landmarker_full',
);
await for (final envelope in controller.frames()) {
  monitor.record(envelope);
  driver.load(envelope);
  final resolution = source.next(envelope.tUs, expectation);
  // resolution.frame == null → "hüküm yok": görünürlük koçluğu, tahmin değil.
}
```
