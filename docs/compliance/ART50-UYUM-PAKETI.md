# Yula Motion — EU AI Act Art.50 Uyum Paketi (aile-geneli)

> **UYARI — hukuki tavsiye DEĞİLDİR.** Avukat-öncesi hazırlık dokümanıdır
> (LifeOS `ART50-BEYAN-TURU.md` deseninden uyarlandı). Kesin uyum hükmü için
> nitelikli AB hukuk danışmanı gerekir. **Tarih:** 2026-07-29 · **Yürürlük:**
> Art.50 yükümlülükleri **2 Ağustos 2026** (AI Act md.113; Komisyon Art.50
> rehberi 20 Temmuz 2026'da nihai).

**Kapsam:** 5 app (Gravita · Lissom · JabLab · Ostinato · Choreia) — kamera
tabanlı hareket analizi (on-device MediaPipe), deterministik kural motoru
(M-C-03), sesli koç (voice-pack + sistem TTS), öğretim görselleri (T1/T2/T3
katmanları, katalog §6.4).

---

## 1. Yükümlülük haritası (fıkra × aile yüzeyi)

| Fıkra | Aile yüzeyi | Durum |
|---|---|---|
| **50(1)** insanla etkileşen AI → "AI ile etkileşiyorsun" bildirimi | Sesli koç + canlı analiz | **KARŞILANIR (tasarımla).** Skorlayıcı deterministik kural motoru (md.3(1) "AI system" tanımı dışında güçlü argüman — Komisyon tanım rehberi: elle yazılmış kurallar tanım dışı). Poz modeli bir ML algılayıcıdır; ürün zaten "AI-powered coach" kimliğiyle pazarlanır → "makul kişi için apaçık" istisnası + onboarding'de açık cümle (aşağıda §3 kopya). Kurgusal koç karakteri kullanılırsa Komisyon rehberi gereği ifşa KORUNUR |
| **50(2)** sentetik ses/görüntü/video üreten AI → **makine-okunur işaret** | T2/T3 öğretim videoları/görselleri · voice-pack (ElevenLabs/OpenAI TTS) | **AKTİF YÜKÜMLÜLÜK — bu paketin varlık nedeni.** Her T2/T3 varlık + her AI-TTS ses dosyası üretim anında `tools/art50/mark_asset.py` ile işaretlenir (C2PA-tarzı sidecar + gömülü XMP); content-package CI kapısı işaretsiz AI varlığında KIRMIZI |
| **50(2)** — T1 iskelet-avatar | Referans dizisinin deterministik render'ı | **Yükümlülük DOĞMAZ (güçlü argüman):** üretken model yok; çıktı, gerçek-eğitmen konsensüs referansının stilize canlandırması. Dürüstlük fazlası: avatar "virtual coach" olarak etiketlenir (§3) |
| **50(3)** duygu tanıma / biyometrik sınıflandırma bildirimi | — | **UYGULANMAZ.** Duygu çıkarımı yok. Poz analizi "biyometrik sınıflandırma" değil (kişiyi kategorize etmiyor, hareketi ölçüyor); yüz tanıma yok, kimliklendirme yok, ham video cihazda |
| **50(4)** deepfake beyanı | T2/T3 karakter | **UYGULANMAZ + sert kural:** koç karakteri TAMAMEN kurgusal (SDXL+LoRA orijinal karakter). **Gerçek bir kişiye benzeyen görüntü/ses ÜRETİLMEZ** — bu, kırmızı çizgidir; ihlal deepfake yükümlülüğü doğurur |

## 2. Karar ağacı (varlık üretirken)

```
Varlık üretken AI'dan mı çıktı? (Champ/SDXL/Kling/ElevenLabs/OpenAI-TTS...)
├── HAYIR (T1 avatar render'ı, kendi çekimimiz, CC-müzik) → işaret gerekmez;
│     assets-manifest.json'da aiGenerated:false kaydı yine tutulur
└── EVET → ZORUNLU üçlü:
      1. mark_asset.py mark <dosya> --generator <model> → sidecar + XMP
      2. assets-manifest.json: aiGenerated:true + tier (T2/T3)
      3. UI'da insan-görünür ifşa (motion_core AiAssetDisclosure ile; §3 kopya)
      + Gerçek kişi benzerliği kontrolü: benziyorsa ÜRETİM İPTAL (50(4) çizgisi)
```

## 3. Uygulama-içi kopya şablonları (EN — ürün dili)

- **T1 avatar (gönüllü şeffaflık):** "Your coach is a virtual character.
  Movements are rendered from real instructor references."
- **T2/T3 görsel:** "This demonstration video was generated with AI." (varlığın
  ilk gösteriminde görünür rozet/altyazı; ayarlardan kalıcı görünür bilgi)
- **AI ses:** "Coach voice is AI-generated." (onboarding + ayarlar > hakkında)
- **50(1) onboarding cümlesi:** "[App] uses on-device AI to analyze your
  movement through the camera. Your video never leaves your phone."

## 4. Store/beyan notları

- Apple/Play gizlilik beyanlarıyla çelişki YOK: işaretleme metadata'sı kullanıcı
  verisi içermez (model adı + tarih + üretici).
- Store açıklamasında "AI coach" ifadesi 50(1) şeffaflığını destekler; abartı
  iddia (accuracy sayısı) 00-AILE-MIMARISI §7'ye tabidir — ayrı konu.
- Ostinato çocuk rejimi: Art.50 ifşa dili çocuk-okur sadelikte tekrarlanır
  (plan §13 bağlayıcı).

## 5. Süreç kancaları

1. **Üretim:** her T2/T3 üretim betiği `mark_asset.py mark` çağırmadan dosya
   teslim edemez (asset-üretim reçetelerine gömülü).
2. **CI kapısı:** content-package build'i `mark_asset.py scan <dir>` koşar —
   `aiGenerated:true` olup geçerli sidecar'ı (hash eşleşmeli) olmayan varlık =
   build KIRMIZI.
3. **G9 uyum turu:** `store-policy-officer` + `privacy-data-guardian` turlarına
   bu doküman girdi; lansman öncesi hukukçu görüşü kurucu manuel listesinde.
4. Komisyon rehberi güncellenirse bu doküman `guncelleme` ile revize edilir;
   madde değişikliği aile DEFTER'ine M-kaydı düşer.
