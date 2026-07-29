# Hasat Rig'i — Kurucusuz Veri Fabrikası (M-F-13)

Kamu eğitmen videolarından **provenance'lı** landmark/etiket hasadı. Video
kendisi ship edilmez; yalnız türevler (landmark fixture, transcript madenciliği)
kullanılır (katalog §6.0/6.2 + C-017 kurucu-kabul çerçevesi).

## Boru hattı

```
pull (yt-dlp, info-json ZORUNLU)
  → triage (M-O-02: süre≥90sn · yatay · tek-sahne · net · üst-gövde)
    → dedup (aHash imza dizisi, kütüphane indeksi)
      → extract (fixture_pipeline/extract_landmarks.py --file; fixture v2
                 provenance bloku manifest'ten zenginleşir)
        → transcribe (faster-whisper kuruluysa; koçluk-dili madenciliği)
```

Her aşama `manifests/<id>.json`'a kanıtla yazılır. Reddedilen klip de manifest
bırakır — "neden havuzda yok" sorusu hep cevaplanabilir.

## Kullanım

```bash
VENV=../fixture_pipeline/.venv/bin/python

# aday URL'i uçtan uca hasat et
$VENV harvest.py run --url "https://youtu.be/..." --app jablab \
    --library ~/harvest/jablab

# yerel dosyayı yalnız triyajdan geçir
$VENV harvest.py probe video.mp4
```

Kütüphane düzeni: `raw/` (video+info.json) · `landmarks/` (fixture v2 JSON) ·
`manifests/` · `transcripts/` · `signature-index.json`.

## Bağımlılık ve lisans denetimi (katalog §0)

| Araç | Lisans | Durum |
|---|---|---|
| yt-dlp (sistem binary'si) | Unlicense ✓ | zorunlu (`brew install yt-dlp`) |
| OpenCV / numpy / MediaPipe | Apache-2 ✓ | fixture_pipeline venv'inde hazır |
| PySceneDetect | BSD-3 ✓ | OPSİYONEL — yerleşik histogram kesme-tahmincisi varsayılan |
| imagededup | Apache ✓ | OPSİYONEL — yerleşik aHash varsayılan |
| faster-whisper | MIT ✓ | OPSİYONEL — yoksa aşama "skipped" |
| ❌ internetarchive | AGPL | bu rig'e GİRMEZ |
| ❌ SMPL-bağımlı mesh-recovery (4D-Humans/WHAM) | research-only | YASAK-varsayılan |

## Kaynak havuzları

Katalog §6.2'de app-başına kanal listeleri (≥3 bağımsız eğitmen/hareket kuralı).
App oturumları aday URL listelerini `--library` altına `queue.txt` olarak bırakır;
toplu koşum: `while read url; do $VENV harvest.py run --url "$url" ...; done`.

## Eşik notları

`TriageThresholds` parametrik: Ostinato el-yakın-çekim/kamera-açı özel eşikleri
kendi havuz koşumunda verir (M-O-02'nin açı-normalizasyon sorusu B4 pilotunda).
Üst-gövde sondası pose modeli `fixture_pipeline/models/` pinli dosyalarını
kullanır (`fetch_models.sh`).

### Duruş kapısı — "kadrajda mı" ≠ "hareketi yapıyor mu" (G-043)

Görünürlük sondaları kişinin kadrajda olduğunu doğrular, **aranan hareketi
yaptığını doğrulamaz**. Gravita'da ölçüldü: kimlik kapısı olmadan çıkarılan 85
push-up "tekrarının" **65'i (%76)** gövdesi 50-90° eğimli — yani ayakta konuşan
— kayıtlardan geldi (bir eğitmen tek videodan 58 "tekrar"). Tekrar FSM'i sinyal
ekleminin salınımını sayar, hareketi değil; konuşurken el hareketi de dirseği
155°↔100° arasında gezdirir.

```json
{
  "thresholds": {"min_posture_ratio": 0.25},
  "perMovement": {
    "push_up":          {"lower_body_ids": [23,24],       "trunk_angle_band_deg": [60, 90]},
    "bodyweight_squat": {"lower_body_ids": [23,24,27,28], "trunk_angle_band_deg": [0, 45]}
  }
}
```

* Bant **düşeyden sapma** derecesidir: `0` = dik gövde, `90` = yatay. Birim
  uygulamaların `torso_angle_from_vertical` metriğiyle aynıdır — rig eşiği ile
  motor ön koşulu arasında çeviri katmanı yok.
* Bant **harekete özeldir** (`perMovement`). Sabit bir "yatay" varsaymak L-080'in
  tekrarı olurdu: squat/curl gibi dik hareketleri sessizce reddederdi.
* Pencere kurtarması bu reddi **geri almaz**: pencere sondası görünürlük ölçer,
  kimlik ölçmez — ayakta-konuşma videosunda da kusursuz pencere bulunur.
* Bant verilmezse kapı **kapalıdır** (geriye uyumlu). `perMovement` girdisi hem
  çıplak liste (eski) hem nesne biçimini kabul eder.
