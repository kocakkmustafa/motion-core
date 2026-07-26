# Yula Motion — Cephanelik: Görüntü/Ses İşleme Araç Kataloğu

**Tarih:** 2026-07-26 · **Statü:** Aile-geneli bağlayıcı araç/lisans kararları (11-ajanlık web araştırması sentezinden; ~1.05M token, tüm iddialar URL'li kaynaklıdır)
**Hiyerarşi:** `00-AILE-MIMARISI.md` > `20-URETIM-SURECI.md` > bu dosya > app yol haritaları.
**Kural:** Buradaki ❌ kararları bir oturum tek başına deviremez — istisna, gerekçesiyle motion-core DEFTER'ine yazılır ve kurucu onayı ister.

---

## 0. Lisans kırmızı çizgileri (EN ÖNEMLİ BÖLÜM)

| Kural | Kapsam |
|---|---|
| ❌ **AGPL/GPL bağımlılık YOK** | Ultralytics YOLO (AGPL-3.0!), aubio (GPL-3.0), TarsosDSP (GPL-3.0), Essentia (AGPL-3.0), Piper'ın yeni forku `OHF-Voice/piper1-gpl` (GPL-3.0). Kapalı-kaynak ticari app'te bunlar kullanılamaz. İstisna = ücretli ticari lisans satın alımı (kurucu kararı). |
| ⚠️ **LGPL yalnız dinamik bağlama ile** | SoundTouch (LGPL-2.1) tempo/time-stretch için kabul edilebilir; statik gömme yasak. |
| ✅ **Güvenli liste** | Apache-2.0: MediaPipe (pose/hand/object), MoveNet, RTMPose/MMPose, RT-DETR/D-FINE, sherpa-onnx, Kokoro-82M. MIT: AudioKit, CREPE. BSD: camera/Pigeon. Apple/Google sistem API'leri. |
| ⚠️ **Veri seti lisansı ≠ kod lisansı** | Fine-tune edilen model "türev eser" riski taşır. Non-commercial veri setiyle SHIP EDİLEN model eğitilmez (bkz. §6). |
| ❌ **Non-commercial model/veri tuzakları (2026-07-26 araştırması)** | **NVIDIA LocateAnything-3B**: gerçek (HF `nvidia/LocateAnything-3B`, 3B VLM grounding) ama "NVIDIA License" **non-commercial** — offline oto-etiketleme dahi KULLANILMAZ (etiketler ticari ürüne akar; M-F-14). Offline teacher alternatifi: **D-FINE (Apache-2.0)** / PaddleDetection RT-DETR (Apache) — ⚠️ Ultralytics'in RT-DETR wrapper'ı AGPL! · **SMPL/SMPL-X vücut modeli**: research-only — 4D-Humans/WHAM/VIBE gibi mesh-recovery repoları kod-Apache görünse de bu modele bağımlı; Meshcapade ticari lisansı olmadan hatta girmez · **FLUX.1/2-dev self-host**: non-commercial (ticari çıktı yalnız BFL API'den) · **MPG veri setleri** (Human3.6M/3DPW/AMASS/MPI-INF-3DHP/BEDLAM): yazılı izinsiz iç-QA'da bile varsayılmaz (§6.3) |
| 📋 **Her yeni bağımlılıkta** | LICENSE dosyası okunur, DEFTER'e kaydedilir. "Popüler = güvenli" DEĞİLDİR (aubio/YOLO/LocateAnything/SMPL dersi). |

## 1. Pose (iskelet) katmanı — aile standardı

**KARAR: MediaPipe Pose Landmarker (Tasks API, BlazePose GHUM)** — birincil motor, 5 app'te.
- 33 landmark (ayak dahil), 2D + 3D world koordinat, per-landmark visibility → güven kapımızın hammaddesi. Apache-2.0. Google aktif bakımda (docs Mayıs 2026). https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- Varyant politikası: canlı koçluk = **full**; assessment/ölçüm modları = **heavy** (tek deneme, fps toleranslı); düşük-segment cihaz fallback = **lite**. Cihaz-adaptif seçim motion-core'da.
- ⚠️ Resmî statü hâlâ "Solutions Preview" (SLA yok) → model sürümü PİNLENİR, `ModelVersion` her kayıtta saklanır (planlardaki veri modeliyle uyumlu).
- fps beklentisi: topluluk ~22-32fps (orta Android, full/heavy) — **kendi cihaz matrisimizde ölçmeden hiçbir eşiğe taahhüt yok** (V0 kapılarının işi).

**Yedek merdiven** (V0 kapısı başarısızsa sırayla):
1. Giriş görüntüsünü döndürme hilesi (Gravita D1: 180° çevirip infer — kod-tek çözüm; BlazePose'un detector'ı zaten kişi-merkezli daire + omuz-kalça açısıyla rotasyon normalize eder, yapısal avantaj).
2. **RTMPose** (Apache-2.0, ONNX Runtime; hazır Flutter referansı: https://github.com/konyshevgmbh/pose_estimation_flutter) — kendi inference hattını sahiplenmek pahasına daha yüksek doğruluk.
3. ML Kit Pose Detection (33 landmark, BETA/SLA'sız — yalnız geçici köprü).
4. Landmark-üstü hafif rotasyon-dayanıklı düzeltici (VIRA-GCN deseni: çoklu-açı augmentasyon + inference'ta çoklu-görüş birleştirme, arXiv kanıtlı) — fine-tune gerektiren son çare.
- **iOS iyileştirme katmanı (G8+):** Apple Vision `VNDetectHumanBodyPose3DRequest` (per-joint confidence + Neural Engine; Simulator'da ÇALIŞMAZ — CI'da fixture, cihazda doğrulama). ARKit body tracking per-joint confidence VERMEZ → güven-kapılı mimarimize uygun değil.
- **El katmanı (Ostinato, ileride JabLab yumruk/gard):** MediaPipe Hand Landmarker (21 nokta, Apache-2.0). Pose+Hand birlikte çalıştırma maliyeti ÖLÇÜLMEMİŞ — Ostinato V0'ında zorunlu benchmark.
- MoveNet: 17 nokta/2D — ailenin hassasiyet ihtiyacına yetmez; yalnız düşük-segment kaba-takip fallback adayı.

## 2. Flutter ↔ native köprü mimarisi (aile standardı)

**KARAR: Kamera + inference %100 native; Dart'a yalnız sonuç akar.** (2026'da resmî MediaPipe Vision Flutter plugin'i YOK — `mediapipe_genai` yalnız LLM. Topluluk wrapper'ları bus-factor riski.)
- Android: CameraX `ImageAnalysis` → MediaPipe Tasks Vision (AAR) → state-machine → **Pigeon** event kanalı. iOS: `AVCaptureVideoDataOutput` → Tasks Vision pod → aynı sözleşme.
- **Kanal diyeti:** 30fps ham landmark Dart'a AKITILMAZ. Dart'a giden: state-machine geçiş olayları + skorlar + ~10-15fps'e desimasyonlu overlay iskeleti. Tam döngü native'de döner.
- State-machine'ler ve kural motoru **native tarafta** (landmark kaynağına yakın); Dart = UI + TTS tetikleme + program/persistans. Kural içerikleri versiyonlu config (JSON) — native motor yorumlar.
- **Impeller uyarısı:** ağır PlatformView/texture kullanımında bilinen performans pürüzleri var — kamera-önizleme ekranı G5'te İLK iş gerçek cihazda benchmark'lanır (orta-segment Android + eski iPhone).
- Termal/pil: özel Flutter paketi YOK → motion-core'a native termal monitör (Android PowerManager thermal API / iOS `ProcessInfo.thermalState`) + kademeli düşürme (çözünürlük→fps→model varyantı) yazılır. 20-40dk seans (JabLab/Choreia) gerçek risk.
- Dart-tarafı ML (`tflite_flutter`, `google_mlkit_pose_detection`): YALNIZ prototip/gerçek-zamanlı-olmayan ekranlar (ör. Lissom tek-çekim değerlendirme denemesi). Üretim döngüsüne girmez.
- **Çalınacak desenler:** `jinzishuai/fitnessPipe` (PoseDetector arayüz soyutlaması — backend değiştirilebilirlik), `reevald/ai-workout-assistant` (açı-eşikli faz state-machine şablonu), `nainarathore/pose-detection-flutter` (CustomPainter overlay boilerplate). Hepsi desen referansı — kod kopyalanmadan önce lisans+kalite kontrol.

## 3. Nesne algılama (Ostinato çello+yay; ileride ekipman)

**KARAR: MediaPipe Object Detector + Model Maker** (Apache-2.0, resmî mobil yol, transfer-learning ile az veri) birincil. Yay = ince/hızlı nesne → bbox yerine **2-keypoint (uç+topuk) hattı** planlanır; akademik emsal: erhu yay-takibi YOLO araştırması (HCI 2020 + MDPI Sensors 2025 — fizibilite kanıtı, cihaz-üstü kanıtı DEĞİL).
- Apache alternatif: RT-DETR / D-FINE (mobil export DIY; YOLO-nano kadar olgun değil — spike şart).
- ❌ Ultralytics YOLO ailesi: AGPL. Enterprise lisans fiyatlaması ancak kurucu isterse araştırılır.

## 4. Ses analizi (Ostinato pitch/onset; Choreia beat)

- **Pitch (Ostinato):** iOS = AudioKit `AKFrequencyTracker` (MIT, tuner-app'lerde kanıtlı). Android = kendi YIN/pYIN implementasyonu (Kotlin/C++; GPL'siz) VEYA **SwiftF0 pilotu** (arXiv 2508.18440, ~96K parametre, CREPE'den 42× hızlı iddiası — LİSANS DOSYASI DOĞRULANMADAN benimsenmez, çello frekans aralığında (C2≈65Hz) kendi testimiz şart). CREPE (MIT) ağır — yalnız offline referans/kalibrasyon.
- **Tempo/metronom hizası:** SoundTouch (LGPL-2.1, dinamik bağlama) veya kendi onset+click hizalayıcımız.
- **Beat tracking (Choreia):** KARAR — canlı takip DEĞİL, **offline/batch BPM analizi + önbelleğe beat-grid** mimarisi (daha doğru + daha az risk). V1 = dahili metronom + BPM'i bilinen royalty-free beat kütüphanesi (sıfır tespit + sıfır telif riski). Kullanıcının kendi müziği = yalnız yerel çalma + tek-seferlik offline analiz (V1.5). Canlı tespit şartsa: **Superpowered SDK** (ücretli, temiz lisans — fiyat kurucuya sorulacak). BeatNet = akademik referans/benchmark, mobil değil.
- Audio+motion **tek clock**: her iki akış aynı monotonic saatle timestamp'lenir (Ostinato/Choreia senkron temeli; motion-core sözleşmesi).

## 5. Sesli koç katmanı (5 app'in çekirdek vaadi)

**KARAR: Hibrit mimari** (aile-geneli bağlayıcı):
1. **Sabit repliklerin (~%80) voice-pack'i:** offline toplu üretim — TEK kanonik "Yula Motion koç sesi" tüm ailede (maliyet + marka tutarlılığı amortismanı). Üretici: ElevenLabs (ifade gücü; ✋ ToS/ticari-dağıtım maddesi BİRİNCİL kaynaktan okunmadan bütçe kilitlenmez) veya OpenAI TTS (ucuz, birinci-taraf ToS; AI-ses ifşa yükümlülüğü). Ortak replikler (sayaç, tebrik, dinlenme) aile-ortak pakette; alan-özgü replikler app paketinde.
2. **Dinamik içerik (sayılar, süreler):** V1 = sistem TTS (`flutter_tts`: iOS AVSpeechSynthesizer / Android TextToSpeech). Android OEM kalite parçalanması bilinen risk.
3. **V2 marka sesi yükseltmesi:** sherpa-onnx (Apache-2.0, resmî Flutter paketi `sherpa_onnx`) + **Kokoro-82M** (Apache-2.0, ~327MB) — iki platformda tutarlı nöral ses. Model TEK paylaşılan varlık olarak (5 app'e kopyalanmaz).
- ❌ Piper yeni forku GPL-3.0 (Eki 2025 MIT→GPL); eski MIT sürümü pinlenmeden kullanılmaz. ❌ Apple Personal Voice: yalnız erişilebilirlik kapsamı — plan yapılmaz.
- **Ducking:** motion-core'da TEK paylaşılan native modül — iOS `AVAudioSession .duckOthers` (cue süresince aktif/deaktif; iOS'ta duck derinliği ayarlanamaz — kabul), Android `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`. Flutter tarafı `audio_session` + `flutter_tts`.
- **Gecikme bütçesi:** cue ≤500ms (konuşma hissi ~200ms hedef); voice-pack ≈ 0ms; dinamik sayılar için synthesizer sıcak tutulur + sık sayılar önbelleğe.

## 6. Veri setleri & fixture stratejisi

> ⚠️ **2026-07-26 KURUCU KARARI — bu bölüm REVİZE EDİLDİ.** Önceki hüküm "BİRİNCİL = kendi kayıtlarımız" idi; kurucu bunu değiştirdi. Aşağıdaki §6.0 bağlayıcıdır ve **5 app için geçerlidir** — motion oturumları bu tartışmayı yeniden açmaz.

### 6.0 Referans kaynağı (kurucu kararı, aile-geneli bağlayıcı)

**KARAR: Doğru referans, kamuya açık gerçek eğitmen videolarından çıkarılır.** Kendi çekimimiz ve yapay-zekâ ile üretilmiş hareket, birincil referans kaynağı DEĞİLDİR.

Gerekçe ve sınırları — dördü de bağlayıcı:

1. **"Referans" iki ayrı şeydir, karıştırılmaz.**
   - **Skorlama referansı** = kullanıcının karşılaştırıldığı açı dizisi. **Doğru** olmak zorunda. Kaynağı: gerçek eğitmen videoları.
   - **Öğretim görseli** = kullanıcıya gösterilen kısa video. **İnandırıcı** olması yeter. AI üretimi serbesttir (Art.50 ifşasıyla).
2. **AI ile üretilmiş VİDEODAN landmark çıkarılmaz.** Üretken modelin anatomi motoru yoktur; makul kare üretir, doğru vücut değil. Uzuv boyu kayar, eklem geri bükülür — bunlar `StructuralValidator`'ın (M-019) reddetmek için var olduğu artefaktlardır. Referans **doğru** olmalı, makul değil.
3. **Skorlayıcı ÖĞRENİLMİŞ MODEL DEĞİLDİR — deterministik kalır** (katalog §7 BUILD hükmü ve açıklanabilir kural motoru korunur). Sebep hukuki değil, veriseldir: **eğitmen tutorial'ları yalnız DOĞRU icra içerir.** Etiketli yanlış örnek ve kalite derecelendirmesi yoktur; yalnız doğru cevaplardan "neyin yanlış olduğu" öğrenilemez. Tek-sınıf/anomali yaklaşımı zaten DTW+açı benzerliğinin yaptığı şeydir, üstelik açıklanabilirliği kaybederek. Öğrenilmiş katman, gerçek kullanıcı verisi + puanları biriktikten sonra V2 konusudur.
4. **Hatalı örnekler çıkarılan referansın kontrollü bozulmasından üretilir** (`SyntheticNoise` + açı perturbasyonu). Hatanın büyüklüğünü biz belirlediğimiz için **etiket bedavadır**. Fixture kuralı (≥1 doğru + ≥2 hatalı) böyle karşılanır: doğruyu gerçek eğitmenler, hatalıyı biz veririz.

**Çoklu-kaynak zorunluluğu — tek videodan referans üretilmez.** En az 3 (tercihen 6+) bağımsız eğitmen birleştirilir, çünkü:

- **Aynalama tek videoda çözülemez.** Eğitmenler izleyiciye göre aynalayarak öğretir ve landmark'ta bunu söyleyen hiçbir şey yoktur. N takede **konsensüsle** çözülür: her take iki yönde denenir, grup uyumunu en çoklayan atama seçilir (`ReferenceBuilder.resolveMirroring`). Çözülmezse ürün her kullanıcıya sistematik olarak ters taraf öğretir.
- **Eğitmenler arası varyans, TOLERANSIN KENDİSİDİR.** Çok sayıda eğitmen aynı şeyi yapıyorsa *o* adımdır; ayrıştıkları yer kişisel stildir. Tolerans bu dağılımdan türetilir (`CanonicalReference.toleranceAt`); eğitmenlerin kendi aralarında anlaşamadığı bir eklemde kullanıcıyı cezalandırmak dürüstlük ihlalidir. Tek eğitmenden bu bilgi ASLA elde edilemez — çoklu kaynağın asıl gerekçesi budur, hacim değil.

**Çıkarım hattı kalite kapıları (hepsi zorunlu):** aynalama konsensüsü · kamera açısı uygunluğu (normalizasyon fronto-paralel varsayar; eğik görüntüde `z` zayıf, açılar bozulur) · plan/kesme sınırı tespiti · `StructuralValidator` (M-019) · **beat anotasyonu** — video bunu VERMEZ ve içindeki müzik telifli olduğu için ondan türetilen ızgara ürüne konulamaz; elle anotasyon veya ayrı çözüm şarttır (Choreia için kritik).

**Hukuki pozisyon:** YouTube ToS ve türev-eser riski **kurucuya sunuldu ve kurucu kararıyla kabul edildi** (2026-07-26). Kayıt: Choreia DEFTER C-017. Oturumlar bunu yeniden tartışmaz; lansman öncesi IP görüşü manuel listede durur.

**Uzman doğrulaması:** eğitmenle sözleşme/anlaşma GEREKMEZ. Ship öncesi **tek seferlik kural-seti kontrolü** yeterlidir — ve yazılmış/çıkarılmış referans parametrik olduğu için uzman "şu 40ms erken olmalı" dediğinde bir sayı değişir, yeniden çekim gerekmez.

### 6.1 Açık veri setleri (kalibrasyon ve uç-vaka için)

Açık setler ikincildir: eşik kalibrasyonu, vücut-tipi çeşitliliği ve "çıkardığımız referans fazla temiz/robotik mi" kontrolü için kullanılır.

| Set | App | Lisans durumu | Kullanım |
|---|---|---|---|
| **AIST++** (Google türevi) | Choreia | ✅ CC BY 4.0 (motion verisi) — ⚠️ kaynak AIST videoları AYRI/kısıtlı | Fixture + beat-senkron testi. En temiz büyük set. |
| **InfiniteRep** (sentetik) | Gravita/JabLab/Lissom | ✅ ticari-kullanım beyanlı (indirme sayfasında teyit) | Fixture + vücut-tipi çeşitliliği |
| Unity Perception + Synthetic Humans | Gravita (ters-duruş!) | ✅ çıktı verisi bizim | Nadir poz sentetik üretimi — handstand seti YOK, kendimiz üretiriz |
| Fit3D | Gravita/Lissom | ❌ research-only (ticari için imar.ro'ya yazılır) | Yalnız metodoloji/eşik referansı |
| Yoga-82 | Lissom | ❌ NON-COMMERCIAL | Yalnız taksonomi/benchmark referansı — ship edilen model eğitilmez |
| 3D-Yoga/3DYoga90 | Lissom | ❓ sor (kalite-skoru etiketleri çok değerli) | Lisans çıkarsa eşik tohumu |
| BoxingVI / ShadowPunch / MPOSE2021 | JabLab | ❓ doğrulanmamış (BoxMAC arXiv'den ÇEKİLDİ — kullanma) | 6-yumruk taksonomisi + vahşi-koşul doğrulama |
| URMP | Ostinato | ❓ form-kapılı (bochen.li@rochester.edu'ya ticari izin sorulur) | A/V-senkron doğrulama; pedagojik hata içermez |
| FineDance / PhantomDance | Choreia | ❓ repo LICENSE kontrol | AIST++ arkasında ikincil |
| Motion-X/IDEA-400 | genel | ⚠️ CC BY-SA (share-alike model riski) | Fine-tune ÖNCESİ hukuk görüşü |
| BEDLAM | Gravita | ⚠️ karmaşık (asset lisansları NN-eğitim yasağı içerebilir) | Yalnız metodoloji referansı |

**Fixture JSON şeması (motion-core sözleşmesi):** `{schemaVersion, app, technique, recordingMeta{device, fps, lighting, bodyProfile, cameraSetup}, modelVersion, frames[{t, landmarks[33]{x,y,z,vis}}], labels[{tStart,tEnd,phase|errorCode,confidence,annotator}]}` — her app aynı şemayı kullanır; replay harness core'da tektir.

### 6.2 Kurucusuz Veri Fabrikası (kurucu direktifi 2026-07-26 — M-F-13, bağlayıcı)

**İLKE: Kurucu çekimi HİÇBİR kapının önkoşulu DEĞİLDİR.** Birincil veri = kamu-video hasadı (§6.0 çerçevesi) + kendi sentetik üretimimiz (§6.3; ücretli klip İPTAL — M-F-17). Kurucudan yalnız cihaz-benchmark'ı (beceri gerektirmez) ve onay/kapı kararları beklenir.
**GENİŞ KÜTÜPHANE DİREKTİFİ:** referans/içerik hasadı DAR başlamaz — her app kendi alanının geniş hareket/stil/çalgı envanterini çıkarır ve hasadı paralel yürütür; MOTOR rollout'u fazlı kalır ama kütüphane baştan geniş kurulur.

**Hasat boru hattı (offline rig — hepsi lisans-denetimli; kurulum koordinatör kuyruğunda):**
`yt-dlp` (Unlicense; `--write-info-json` provenance ZORUNLU: source_url/kanal/lisans/tarih/araç-sürümü) → YouTube Data API `videoLicense=creativeCommon` önceliği + resmî kanallar (CC-video gerçeği: anlamlı hacim YOK — ana hacim standart-YouTube, C-017 kurucu-kabul çerçevesinde) → `PySceneDetect` (BSD-3) klip kesimi → **MediaPipe Pose batch** (üretimle format-eş; birincil) + gerektiğinde RTMPose/mmpose (Apache; checkpoint lisansı TEK TEK denetlenir) → `imagededup` (Apache) + videohash tekilleştirme → in-house Laplacian blur filtresi + landmark-visibility eleme → `faster-whisper` (MIT, yerel) ile eğitmen konuşmasından koçluk-dili madenciliği.
⚠️ Tuzaklar: SMPL-bağımlı 3D mesh-recovery (4D-Humans/WHAM) YASAK-varsayılan (§0) · `internetarchive` pip paketi AGPL — yalnız offline rig'de bilinçli, hiçbir ship-artefakta değmez · hazır "exercise dataset builder" reposu YOK — rig kendi yapıştırma kodumuzdur.

**Kaynak havuzları (araştırma-kanıtlı; ≥3 bağımsız eğitmen/hareket kuralı):**
- **Gravita:** GMB, FitnessFAQs, Tom Merrick, THENX, Tapp Brothers, Antranik (handstand/pistol/crow/L-sit ≥3 ✓); planche/lever İNCE (Simonster + ek tarama görevi).
- **Lissom:** klinik/PT kümesi ÖNCELİKLİ — Physiotutors, E3 Rehab, Clinical Physio, Movement by David, NASM/Brookbush + Emmet Louis/Merrick; test-başına video-düzeyi teyit turu gerekli (hamstring reach/denge/ASLR kanal-düzeyinde kaldı).
- **JabLab:** Precision Striking, Tony Jeffries, ExpertBoxing (temel yumruklar ≥3 ✓); ⚠️ TEK-KİŞİ 240fps slow-mo footage İNCE — spor-bilim kanalları dahil özel tarama; gelecek-motor kickboks/Muay Thai ön-hasadı (teknik-başına tam tur sonra).
- **Choreia:** Hip-Hop foundations + Salsa shines ≥3 ✓ (yarım-tempo öğretim = doğal slow-mo); House/Afrobeats güçlü; Bachata solo yalnız 2 kanal (ek tarama); K-Pop ajans içeriği YÜKSEK-dikkat (hak-yönetimli); 8-count konvansiyonu motor hizasına girdi.
- **Ostinato:** CelloBello + tonebase-free birincil havuz; İLK ADIM kamera-açı triyajı (30-50 aday video elle etiketle: kullanılabilir sağ-ön-çapraz kadraj oranı ölçülür — tahminen azınlık); keman/gitar/piyano ön-hasat çapaları atıldı, tam tur motor kapsamıyla.

### 6.3 Kurucusuz Doğrulama Merdiveni (M-F-16 — kapı türüne göre)

| Kapı türü | Birincil | Destek | ❌ Yasak-varsayılan |
|---|---|---|---|
| **Doğruluk** (açı ölçümü) | **AIST++** (CC-BY anotasyon ✓ — kaynak videolar AYRI lisans!) + **MM-Fit** (CC-BY, Zenodo kaydında teyit et) | **Kendi sentetik setimiz**: Unity Perception (çıktı %100 bizim; SMPL-X Blender yolu SMPL lisansı yüzünden varsayılan DEĞİL). Sentetik = gerekli-ama-yetersiz; daima ≥1 gerçek-veri setiyle eşlenir | Human3.6M · MPI-INF-3DHP · 3DPW · AMASS · BEDLAM — "iç QA" bile yazılı izinsiz KULLANILMAZ (ps-licensing@tue.mpg.de); Fit3D `/legal` okunmadan kullanılmaz |
| **Güvenilirlik/çeşitlilik** (vücut tipleri, test-retest) | Kamu-video çeşitliliği (farklı vücut tipli eğitmenler) + sentetik vücut-tipi varyasyonu (Unity Perception) | TestFlight beta kohortu (kendi in-app rıza akışımızla) · üniversite biyomekanik lab teması (orta-vade lead) | ❌ **Ücretli klip (Fiverr/Upwork) İPTAL — kurucu kararı 2026-07-26 (M-F-17); önerilmez, bütçelenmez.** Goniometri eğitim videoları: yalnız elle göz-kontrol; ölçekli kazıma = telif ihlali |
| **Cihaz** (fps/termal) | Kurucu kendi telefonlarında app/benchmark koşar — beceri gerektirmez; **zamanlama: EN SONDA, deneme amaçlı (G8 sertleştirme fazında; erken fazlar bunu BEKLEMEZ — o güne dek muhafazakâr fps varsayımıyla ilerlenir, eşikler 'cihazda doğrulanacak' etiketli taşınır)** | — | — |

### 6.4 AI Eğitmen / Öğretim Görseli Prodüksiyon Hattı (kurucu direktifi — M-F-15)

**Katmanlı strateji (ucuzdan pahalıya; form-doğruluğu garantisi ancak T1'de yapısaldır):**
- **T1 — VARSAYILAN ($0, form-garantili): iskelet-sürümlü uygulama-içi koç avatarı.** Çıkarılmış referans dizisi (skorlama referansının KENDİSİ) uygulama içinde stilize avatar/iskelet olarak deterministik canlandırılır (Flutter/Rive/3D rig). Doğruluk yapısal olarak garanti — kaynak zaten konsensüs-referans; üretken model yok → anatomik artefakt yok, telif yok, marjinal maliyet sıfır. 5 app'in V1 öğretim görseli budur.
- **T2 — PİLOT-ŞARTLI cila: pose-driven üretken video.** Aday modeller: **Champ (Apache-2.0 ✓, SMPL-rehberli)** · EchoMimicV3 (Apache ✓ ama yüz/üst-gövde odaklı) · ❌ MimicMotion (SVD taban-ağırlık lisansı non-commercial — çözülmeden kullanılmaz) · AnimateAnyone (Apache ama resmî ağırlık yok). Karakter kimliği: **SDXL+LoRA (RAIL++-M ✓ ticari)**; ❌ FLUX-dev self-host. **ZORUNLU PİLOT:** 1 jab + 1 handstand referans iskeletiyle üret → form-denetiminden geçir; atletik-hareket doğruluk benchmark'ı LİTERATÜRDE YOK — kanıtsız taahhüt verilmez. Pilot geçerse T1 avatarın "giydirilmiş" versiyonu olur.
- **T3 — düşük-riskli görseller (intro/karşılama/ambiyans; form-kritik DEĞİL):** ücretli API (Kling ~$0.07-0.11/sn, Runway Gen-4 ~$0.12-0.25/sn, HeyGen ~$0.05/sn — atletik form için kanıtsız) yalnız kurucu-onaylı bütçeyle.
- **Art.50 uyumu (2 Ağustos 2026'dan itibaren yürürlükte — ŞİMDİ):** AI-üretimi görsel = makine-okur işaretleme (C2PA-tarzı metadata) + kullanıcıya açık ifşa; rehberlik kurgusal karakterde bile ifşa gerektiğini söylüyor. İfşa şablonu + işaretleme yardımcıları motion-core işi. **AI videodan landmark ASLA çıkarılmaz (§6.0 md.2 aynen).**

## 7. Hazır SDK'lar (build-vs-buy hükmü)

**KARAR: Üretim = BUILD** (MediaPipe + kendi kural motorumuz). Gerekçe: hiçbir vendor kendi egzersiz state-machine'ini self-serve tanımlatmıyor; 5-app portföyünde per-MAU faturalama katlanıyor; on-device iddiaları çoğunda doğrulanamadı; JabLab/Choreia için vendor HİÇ YOK (beyaz alan kanıtı).
- V0 hız spike'ı olarak İZİNLİ (atılabilir prototip): **KinesteX** (tek gerçek Flutter paketi — on-device mi ÖNCE doğrula) · **QuickPose** (iOS, MediaPipe-tabanlı, free tier). Sency = fiyat/ToS bakılabilir. Kemtai/Exer/Asensei = enterprise-satış kapılı, uğraşma. Onyx = yalnız rakip-UX referansı.

## 8. Fiyatlama girdileri (G9'da kullanılacak — nihai fiyat kurucu)

- Koridor: **$9.99-14.99/ay · $59.99-89.99/yıl** (tek-app). Kategori medyanı ~$9.70/ay (RevenueCat — birincil kaynaktan teyit edilecek).
- Paywall deseni: **GOWOD tarzı assessment-kapılı soft paywall** — ilk ölçüm/temel deneyim paywall ÖNCESİ (ölç-geliş ürününde değer önce kanıtlanır). Yıllık plan "Best Value" vurgusu (yıllık tutundurma 44.1% vs aylık 17.5% — 12 ay).
- Trial: 7 gün varsayılan; 14+ gün ciddi değerlendirilir (17-32 gün trial dönüşümü ~2× — beceri gelişimi 1 haftada görünmez).
- **Aile paketi LANSMANDA YOK**; 2+ app retention kanıtladıktan sonra Simply-modeli (~1.25× tek-app yıllığı) düşünülür, Down Dog'un zarar-lideri modeli DEĞİL.
- Billing altyapı adayı: RevenueCat SDK. FightCamp/Future fiyatları NON-comp (donanım/insan maliyeti).

## 9. App-başına özel notlar

- **Lissom:** Amazon Halo Movement doğrulama çalışması (npj Digital Medicine 2022; 5 hareket × 3D mocap × 150 katılımcı) = test bataryası ŞABLONU. FMS/OHS eleştirileri (öznellik, 2D sınırı) bizim "objektif CV skorlaması" konumlandırmamızın literatür dayanağı. FDA general-wellness dili = kopya kontrol listesi. Kamera-pozisyon etkisi çalışması (JMIR 2026, e82412) kalibrasyon sihirbazının kaynağı. GOWOD'un testinin CV mi öz-değerlendirme mi olduğu = elle teardown görevi.
- **JabLab:** 6-yumruk taksonomisi (jab/cross/lead+rear hook/lead+rear uppercut = klasik 1-6 numaralandırma). Hız = faz-süresi (D2; motion-blur literatürüyle dolaylı destekli — "kanıtlanmış" diye pazarlanmaz). Rakip alanında kamera-tek gerçek-zamanlı CV koçu YOK (FightCamp/PunchLab donanım; diğerleri scripted follow-along).
- **Gravita:** ters-duruş kanıtı zayıf → D1 kapısı pazarlanamaz-varsayım. En yakın rakipler: AI Handstand (Android, on-device+sesli — ELLE İNCELE; iOS boşluğu fırsat) ve Calisthenics AI (upload-tabanlı, muhtemelen cloud). Bilimsel çekirdek: bilek-stratejisi (Kerwin & Trewartha 2001) → landmark-salınım vekil metriği (torku ölçemeyiz — dürüst dil).
- **Ostinato:** Trala (keman, yalnız ses; postür verMİYOR) = en yakın emsal; kamera+ses birleşimi kanıtlı beyaz alan. Erhu yay-takibi araştırması metodoloji şablonu. SmartMusic = ses-tek notanın "yeterli iyi" çıtası.
- **Choreia:** Skorlama = normalize iskelet (kemik-boyu/gövde ölçekli veya eklem açısı: JPSS/JASS formülleri) + pencereli DTW — HAM koordinat DTW yapılmaz (vücut-oranı hassasiyeti). Just Dance Camera Controller (2025-26) ML skorlama yapıyor ama konsol+sessiz; STEEZY yalnız video+ayna; Everdance feedback'i insan-async. Koreografi telifi: adımlar/sosyal danslar korunmaz, ORİJİNAL dizilimler korunur → "learn [Artist]'s official choreography" pazarlaması YAPILMAZ; jenerik adım-müfredatı + kendi koreografilerimiz.

## 10. Bu katalogdan sapma prosedürü

Yeni araç/veri seti eklemek isteyen oturum: (1) LICENSE dosyasını birincil kaynaktan okur, (2) §0 süzgecinden geçirir, (3) motion-core DEFTER'ine M-kaydı düşer, (4) bu dosyayı günceller. AGPL/GPL istisnası ve para gerektiren her karar kurucuya.
