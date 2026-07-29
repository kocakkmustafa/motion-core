# 70 — Kamera Köprüsü Sözleşmesi (`motion_camera`)

> Durum: **TASARIM + İSKELET (PROVISIONAL)** — Dart katmanı 24/24 testle canlı;
> native katman (Swift+Kotlin) pinli API'lere karşı yazıldı ama **henüz derlenmedi
> ve cihazda koşmadı**. Beyan ≠ canlı: §7'deki canlılık listesi kapanana kadar bu
> köprü "var" DEĞİL, "yazılı". Sahibi: koordinatör. İlk sürüm: 2026-07-30.

## 0. Tek cümle

Kamera → MediaPipe → `PoseSourceDriver` hattının native yarısı: çekirdek asla
görüntü görmez, yalnız **monoton saatli, ölçülü-hızlı, isimli-retli** landmark
zarfları alır.

## 1. Katman sorumlulukları (ve sınırları)

| Katman | Yapar | ASLA yapmaz |
|---|---|---|
| Native (Swift/Kotlin) | kamera oturumu · PoseLandmarker (.video) · latest-wins + düşme SAYIMI · plan kadar geçiş (aynı buffer) · 180° ters-geçiş + geri-eşleme · zarf yayını | oryantasyon SEÇİMİ · eşik/karar · izin İSTEME · kare kuyruklama |
| Dart (`motion_camera`) | zarf çözümü · `EnvelopeDriver` dikişi · `PassPlan` yönetimi · ölçülü hız (`ThroughputMonitor`) · isimli hata çevirisi | görüntüye dokunma · landmark yorumlama |
| motion_core | oryantasyon stratejisi (`OrientationAwarePoseSource`) · yapısal doğrulama · güven kapısı · motor | kanal/platform bilgisi |

Gerekçe: ADR-001'in "karar mantığı test edilebilir ve platformlar-arası özdeş
kalır" ilkesi. Native katman aptal, pinli bir borudur.

## 2. Pinler (M-L-02)

- iOS: `MediaPipeTasksVision` **= 0.10.21** (podspec'te TAM pin, `~>` değil)
- Android: `com.google.mediapipe:tasks-vision` **= 0.10.29**
- Sessiz minor-bump = model davranış değişikliği = YASAK; sürüm değişikliği aile
  kararıyla gelir ve `libraryTag` üzerinden her zarfa damgalanır.

## 3. Kanal sözleşmesi

Kontrol: `MethodChannel('motion_camera/control')` — `start` / `stop` /
`setPassPlan`. Veri: `EventChannel('motion_camera/frames')`.

Zarf (StandardMessageCodec map — kanonik tanım
`lib/src/frame_envelope.dart` doc-comment'inde):
`t`(µs) · `w`,`h` · `model`("<libraryTag>+<modelId>") · `clock`
("monotonic"|"unknown") · `infUs`(ölçülü) · `dropped`(sayılmış) ·
`up`/`inv`: `Float32List(132)` = 33 × [x,y,z,vis].

**Üç-değerli geçiş semantiği:** anahtar YOK = geçiş planlanmadı (istenirse
`StateError` — plan/beklenti ayrışması plumbing hatasıdır, J-056 sınıfı "null'a
kılık değiştirme" yasak) · anahtar var, değer null = geçiş koştu, model insan
görmedi · değer dolu = ölçüm.

**Ters-geçiş geri-eşleme:** 180° düzlem-içi dönüş → `x→1-x, y→1-y`,
**index takası YOK** (dönüş yansıma değildir — `orientation_aware_source.dart`
sözleşmesi). Geri-eşleme native'de yapılır ki iki geçiş tek koordinat dili
konuşsun.

## 4. Saat kuralı

- `t` monoton kaynaktan gelir: iOS'ta capture PTS (host clock — platform
  garantisi monoton) → `clock:"monotonic"`.
- Android'de `SENSOR_INFO_TIMESTAMP_SOURCE` OKUNUR: `REALTIME` →
  `"monotonic"`; aksi → `"unknown"` (vendor HAL keyfi sıfır kullanabilir).
- `"unknown"` akış kendi içinde tutarlıdır ama **ses/beat saatiyle ölçülmüş
  offset olmadan füzyonu YASAK** — `PoseFrame.tUs`'un "cihaz uyuduktan sonra
  sinsice yanlış" hata sınıfının panzehiri beyan değil rapordur.

## 5. İki-hız dürüstlüğü

- Geri-basınç = **latest-wins**: kare asla kuyruklanmaz — eski kare üzerinden
  koçluk, "şimdi"yi yalanlamaktır. Atılan her kare **sayılır** (`dropped`).
- `ThroughputMonitor` tüm oranları AYNI kayan zaman-penceresinden okur
  (pencereli hız × ömürlük oran karışımı yasak — erken bir takılma oturumun
  geri kalanının "şu an" okumasını zehirler); oturum toplamları ayrı,
  `session*` isimli alanlarda.
- fps hiçbir yerde beyan edilmez; ölçülemiyorsa **null** (sıfır değil).

## 6. İsimli retler

`camera-permission-denied` · `model-load-failed` · `already-running` ·
`not-running` · `no-such-camera` (+ `bad-arguments` protokol hatası). Plugin
izin İSTEMEZ — izin UX'i app kararıdır; plugin'in işi app'in yönlendirebileceği
İSİMLE reddetmektir. Tanınmayan platform hatası çevrilmeden yeniden fırlatılır
(catch-all yutma yasak). Model varlığı plugin'e GÖMÜLMEZ: app kendi `.task`
dosyasını pinler, `modelId` beyanı her zarfın provenance'ına girer.

## 7. Canlılık listesi (kapanmadan "köprü var" DENMEZ)

1. `pod install` 0.10.21'i çözer; Swift derlenir (API adları 0.10.21'e karşı
   yazıldı, derleyici doğrulaması YOK).
2. Gradle 0.10.29'u çözer; Kotlin derlenir (aynı çekince; CameraX 1.4.2).
3. Gerçek cihazda oturum: zarf akışı ≥ 30 sn, `judgedRatio` ve
   `meanInferenceUs` ölçülür (uydurma yok — ilk gerçek sayılar buradan gelir).
4. Dual-pass maliyeti ÖLÇÜLÜR (tek-geçişe oranı; ADR-001 "2× maliyet" varsayımı
   sınanır).
5. iOS buffer-tutma kontrolü: inference sırasında CVPixelBuffer tutmak capture
   havuzunu açlığa itiyor mu (stall → `dropped` patlaması olarak görünür).
6. `clock:"unknown"` yolu en az bir vendor cihazda gözlenir/raporlanır.
7. Ters-geçiş geri-eşlemesi el-standı fikstürüyle doğrulanır (UPR-S2 sınıfı
   çift-yönlü hata: rotasyonun YANLIŞ gövdeye uygulanması ölçülmüştü — 1/24).
8. Ön-izleme yüzeyi (aşağıda, açık kalem) bağlanmadan app'e UI entegrasyonu
   başlamaz.

Canlılık koşumu doğal sahibi: cihazı olan app oturumu (JabLab shell deseni) —
koordinatör iskeleti verir, app oturumu cihazda söker-takar, sayılar DEFTER'e.

## 8. Açık kalemler (isimli)

- **Ön-izleme dokusu:** kullanıcı kendini görmeli — `Texture`-tabanlı preview
  (registrar.textures) bilinçli ERTELENDİ; zarf hattı canlanmadan preview
  optimizasyonu prematüre. Kullanıcıya görünen yüzey olmadan hiçbir app
  "kamera çalışıyor" DEMEZ.
- **hysteresisMs köprü etkisi:** M-F-72 tasarımı (133ms + ≥2 kare tabanı)
  motor tarafında; köprünün ölçtüğü gerçek fps hysteresis'in kare→ms
  çevriminin girdisi olacak.
- **Lens değişimi:** oturum içi front↔back geçişi yok — stop/start ile;
  ihtiyaç doğarsa ölçülü gerekçeyle eklenir (araç ihtiyaçla doğar).
- **Çoklu kişi:** `numPoses=1` bilinçli — koçluk tek kişiye; ikinci kişi
  "görünmezlik" değil yapısal-doğrulama gürültüsü olarak görünür; gerçek
  malzemede ölçülmeden politika yazılmaz.
