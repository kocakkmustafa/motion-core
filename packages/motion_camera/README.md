# motion_camera

Yula Motion ailesinin native kamera → MediaPipe pose köprüsü.
Sözleşme: [`docs/70-KAMERA-KOPRUSU-SOZLESMESI.md`](../../docs/70-KAMERA-KOPRUSU-SOZLESMESI.md).

- Çekirdek görüntü görmez: yalnız monoton saatli landmark zarfları.
- Pinler (M-L-02): iOS MediaPipeTasksVision **0.10.21** · Android tasks-vision **0.10.29**.
- Durum: Dart katmanı testli; native katman **PROVISIONAL** (derlenmedi/cihazda koşmadı) — canlılık listesi sözleşme §7.

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
