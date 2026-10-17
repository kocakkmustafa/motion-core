## 0.13.0 — 2026-10-17 — Provider contract v1

- Additive MotionProviderManifest/Requirement and explicit in-memory selection.
  Exact input space, ABI, model/calibration hashes and app-reviewed acceptance
  gate each capability; unsupported and calibrationRequired remain non-ready.
- Replay declarations cannot enter production selection. Incompatible candidates
  preserve the active provider; explicit rollback checks current receipts again.
- No existing pose, camera, account or assessment API changed. No consumer pin
  changed. This is metadata/selection infrastructure, not model accuracy proof.

## 0.9.0 — 2026-07-30 — SessionStore çekirdek-terfisi (üçler kuralı)

- `SessionRecord`/`SessionStore`/`JsonlSessionStore` çekirdekte (M-F-193
  hakemliği; karar: workspace/SESSION-STORE-TERFI-KARARI.md). Nötr iş-birimi
  + KAYIT-başına unitLabel (Gravita ölçümü: iki birim aynı app'te) ·
  yazım-anı lessonClass AÇIK sözlük + en-az-yetki okuması (yalnız 'scored'
  skorlanmış okunur) · unmeasuredUnits ("sessizlik yalandır"; tamamlama
  ATTEMPTED üzerinden — ölçülemeyen deneme ilerleme düşürmez) · staticHold
  tekrarı kabul-ve-belgeli · J-064 depo değişmezleri aynen (JSONL ·
  satır-şema v:2, v1-mirası okunur · tmp+rename · bozuk-satır toleransı ·
  mutable-liste) · kurucu File alır (kablolama app'te). İlk tüketici Lissom;
  diğer üç app kendi turlarında adopte eder.

# Changelog — motion_core

Sürümleme: semver. App'ler pinli sürüm tüketir (git dependency, tag'li:
`motion_core-vX.Y.Z`). Breaking değişiklik = 5 app'in DEFTER'ine kayıt + duyuru.

## 0.8.8 — 2026-07-30 — medoidTakeId

- `CanonicalReference.medoidTakeId` + artefakta `result.medoidTakeId`
  (G-082): tüketiciler medoidi kare-sayısı eşitliğinden geri-mühendislikle
  buluyordu — hizalama tabanı isim taşır, çıkarım değil. G-082 ölçümü
  0.8.7'nin kare-denominatör seçimini geriye dönük doğruladı: DTW KARE
  hizalar, süre-tavanı 7 take'te aşılıyor (fps heterojenliği) yani tavan
  değil; kare-tavanı yapısal olarak aşılAMAZ.

## 0.8.7 — 2026-07-30 — capFillShare: uzunluk-vekili ayrıştırması

- İki bağımsız aile ölçümü (Ostinato hold-sınıfı §2d + Gravita
  movement-sınıfı G-081) aynı sonucu verdi: ham `alignedDistinctShare`
  medoide-göre UZUNLUK ORANININ vekili (kısa take tavanına çarpar, her
  örneği gerçek). `TakeEvidence.capFillShare` = share / min(1,
  frames/medoidFrames) — take'in CEVAPLAYABİLECEĞİNİN ne kadarını
  cevapladığı. ~1,0 = dürüst-kısa; belirgin <1,0 = park/kopyalama sınıfı
  (M-F-68 HIGH-1'in gerçek imzası burada görünür). Aile ölçümü: push_up
  medyan 1,000 · squat 0,922 · 0/72 take <0,70 — gerilme sınıfı henüz
  hiçbir gerçek artefaktta gözlenmedi.

## 0.8.6 — 2026-07-30 — evidenceThickness zayıf-take alanı (M-F-68 HIGH-1)

- `CanonicalReference.takeEvidence` + artefakta `evidenceThickness.takes`
  bloğu: take başına `{frames, durationS, alignedDistinctShare}`. DTW'nin
  eğim-normalize koridoru uzunluk oranını TASARIMI GEREĞİ kabul eder
  (tempo esnekliği) — 1-karelik take tek örneğini tüm medoid zaman
  çizgisine gererek "hizalanır" ve enjekte ettiği varyans tolerans
  etiketini floor→variance çevirebilir (kimsenin ölçmediği eğitmen
  anlaşmazlığı iddiası; kopyalama ≠ ölçüm — G-078 dersinin hizalama
  düzeyi). RAPOR, kapı değil: kapının eşiği bu alanın gerçek
  artefaktlardaki ölçülmüş dağılımından türeyecek.

## 0.8.5 — 2026-07-30 — beyan-edilen kapı-eklem-kümesi + zaman-histerezisi

- **gateJoints/gateBasis (M-O-56 dördüncü sınıf):** M-F-47 kapısının
  take-medyanı artık BEYAN EDİLEN eklem kümesinde koşabilir — postür/hold
  malzemesinde kapı, ürünün skorlamadığı serbest uzuvlarda anlaşma arayıp
  skorlanan metriğe 0,3° uyan take'i reddediyordu. Daraltma gateBasis
  olmadan İSİMLİ reddedilir (coached_only kararı bir kez, isimli
  tüketilir); artefakta `agreementGateJoints`/`agreementGateBasis`
  damgalanır; varsayılan tam-küme davranışı DEĞİŞMEDİ.
  `build_reference.dart`: `--gate-joints`/`--gate-basis`. Sonuç: guitar
  3→5 take (gerekçe düzeldi, 22° özel-barı öldü) · İLK ŞAN (4) · İLK
  PİYANO (3) referansları, üçü de varsayılan 14°'de.
- **hysteresisMs (M-F-72):** OrientationAwarePoseSource'a zaman-tabanlı
  histerezis (133ms + ≥2 kazanan kare tabanı; kare-damgalarından ölçülür,
  fps varsayımı yok; bayat-boşluk kuralı sabitsiz). Varsayılan null =
  eski kare-sayısı davranışı.
- **priorDisagreements semantiği (J-063):** alan yalnız KARARLI aramaya
  karşı sayar — yakın-beraberede bestMask atılmış yazı-turadır; "prior
  boşluğu doldurdu" artık "prior konsensüsü ezdi" diye okunmaz.
- `--lead-side-prior` (M-J-06 resmi kanalı, JabLab): ölçülmüş öncü-taraf
  önseli build ANINDA verilir; bozuk/bayat prior dosyası isimli reddedilir.

## 0.8.4 — 2026-07-29 — NaN→null artefakt kodlaması

- 0.8.3'ün kapısı dürüst NaN üretince JSON kodlama çöktü (NaN JSON'da
  yok). Ölçülmemiş hücre artık `null` (meanRad/dispersionRad/floorShare/
  meanAgreement). Eski artefaktlarda HİÇ NaN hücre olmaması J-056'nın
  ayrı belirtisiydi: çöp numerikler her hücreyi dolduruyordu. Gerçek-veri
  kanıtı (stance 0.8.4 yeniden-üretimi): 57.334/399.279 hücre (%14,4)
  dürüst null; meanAgreement 0,737→0,788 İYİLEŞTİ (çöp temizlenince
  anlaşma sıkılaştı). NOT: uzak tag-silme guard'ı gereği v0.8.3 tag'i
  yalnız kapı-düzeltmesini içerir ve artefakt yazımında çöker —
  **tüketiciler v0.8.4 kullanmalı.**

## 0.8.3 — 2026-07-29 (yeni vardiya) — ÇÖP-ÖLÇÜM-GİBİ P0

- **J-056 (JabLab kanıtladı): `prepareTake` görünürlük-kapısını HİÇ
  çağırmıyordu.** `JointAngleExtractor.extract()` saf geometridir ve
  görünürlüğe bakmaz; NaN'lama ayrı `gate()` metodundadır. Canlı ürün
  yolları (replay, sequence_comparator) gate'i hep çağırıyordu — YALNIZ
  kanonik referans-üretme hattı atlamıştı. Sonuç: MediaPipe'ın görünmez
  eklem için ürettiği düşük-güvenli-ama-sıfır-olmayan tahmini pozisyonlar
  numerik açıya dönüşüp konsensüse GERÇEK ÖLÇÜM gibi giriyordu
  (mcleodscott'un "en kötü outlier" bacakları buydu: ±π çevresinde
  instabil, 2802/2802 numerik, 0 NaN — ampirik kanıt J-056'da).
  Kısmi-görünür kaynaklı HER artefakt bu riski taşıyordu. Düzeltme:
  prepareTake artık canlı yollarla AYNI gate'i çağırır
  (landmarkThreshold). Regresyon testi: görünmez-ayak karesinde shin NaN,
  upper_arm numerik (kapı eklem-başına). ⚠️ ETKİ: kanonik CLI'yle
  üretilmiş TÜM artefaktlar 0.8.3'le yeniden üretilmeli — düşük-görünürlük
  eklemleri artık dürüstçe NaN olur ve per-cell count guard'a düşer.
  Test: 197/197.

## 0.8.2 — 2026-07-29 (yeni vardiya, tur 2)

- **M-J-09 (JabLab ölçtü, J-046 kapanışı): `searchDecisive` /
  `mirrorSearchDecisive`** — `confident` iki dayanağı karıştırıyordu:
  "prior'a güvenildi" ve "arama adayları ayırdı". Gerçek stance verisinde
  ölçüldü: prior'la `confident=true` iken arama gap'i 0,0038 << marj 0,02
  — tüketici "veri çözdü" diye okurdu. Yeni alan prior'dan BAĞIMSIZ arama
  kararlılığını taşır (`gapMeasured && runnerUpGap > mirrorMargin`);
  `confident` semantiği değişmedi (geriye uyumlu). CLI artefaktına
  `mirrorSearchDecisive` eklendi. Bayrak dayanağını taşır (M-O-25
  doktrininin ayna-katmanı tamamlaması). Test: 196/196.

## 0.8.1 — 2026-07-29 (yeni vardiya, tur 1 devamı)

- **`Dtw` koridoru ZAMANSAL oldu (wf_dfb1dcd3 doğrulanmış çekirdek bulgu /
  doc 60 §1):** `bandRadius: 24` kare, yalnız 30 fps'te 0,8 s demekti —
  60 fps'te aynı sürüklenme toleransı sessizce yarıya iniyordu. Yeni:
  `bandRadiusS` (SANİYE, beyan edilen anlam) + `align(..., dtUs:)` —
  kare yarıçapı çağrı başına ÖLÇÜLMÜŞ kare aralığından türetilir
  (`Dtw.medianDtUs`); dt bilinmiyorsa eski kare-yolu beyanlı fallback.
  Kablolandı: ReferenceBuilder (medoid/warp/sapma yolları, öğrenen-taraf
  dt) · CycleAligner (`align(dtUs:)`; ayrım formülü ETKİN yarıçapı
  kullanır; kendi Dtw'si `bandRadiusS: 0.267` = 8 kare @30) ·
  ReferenceCli (take-başına ölçülmüş dt). İki-hız testleri: 0,6 s
  sürüklenme 30 VE 60 fps'te aynı tolere edilir; eski kare-yolunun tam
  kusuru pinli; periyot tahmini hız-bağımsız (75↔150 kare = aynı 2,5 s).
- **Rig `_motion_energy` saniye-birimli** (4 doğrulanmamış iddiadan #4
  DOĞRULANDI+DÜZELTİLDİ): kare-başına delta 60 fps'te aynı hareketi yarı
  "enerji" okuyor, sabit taban gerçek hareket penceresini reddediyordu →
  `min_energy_per_s: 0.30` (= eski 0.010/kare @30 fps, davranış-koruyucu).
  Rig testleri + izolatör öz-testi yeşil.
- Kalan iddialar: `hysteresisFrames` (#2) DOĞRULANDI — kare-sayımlı
  histerezis 60 fps'te 2× hızlı taahhüt eder; zaman-tabanlı tasarım
  (133 ms + ≥2 kare tabanı) DEFTER'de, ayrı sürümde uygulanacak.
  `analyze_d2 wr_jump` (#3) DOĞRULANDI-nüanslı — eşik glitch/hareket
  ayrıştırıcı, hareket tarafı dt ile ölçekleniyor (24 fps'te gerçek hızlı
  yumruk 0,56'ya çıkar > 0,55) — diagnostik-yalnız, JabLab'a sevk.
- Test: 194/194.

## 0.8.0 — 2026-07-29 (yeni vardiya, tur 1)

- **L-139 / ÇEVRİM-SEGMENTASYONU (kanonik CLI):** tam videolar arası DTW,
  farklı tekrar-sayılı take'lerde çevrim sınırlarını ezerek büküyor (4
  tekrarı 9'a) ve bükmeyi 34-43° "eğitmen anlaşmazlığı" diye raporluyordu.
  Yeni hat: `CyclePeriodEstimator` (M-C-25 Dart'ta — ortalanmış ACF,
  YALNIZ belirgin iç yerel tepe, global-max yasak; sınırlar SANİYE
  cinsinden, kare çevrimi take'in ÖLÇÜLMÜŞ medyan dt'sinden) → periyodik
  take'ler faz-hizalı TEK tekrara indirilir (take-içi çevrimler aynı fazda
  ⇒ sabit uç doğru; take'ler ARASI faz `CycleAligner` aramasından).
  Dürüst yollar: hiçbir take tekrarlamıyorsa `notApplied` beyanı
  (bütün-take yolu değişmeden korunur — stance yeniden-koşumu eski
  artefaktla BİT-BİT AYNI çıktı); periyodik havuzdaki aperiyodik take
  İSİMLE dışlanır. Artefakt: `cycleSegmentation` bloğu + take başına
  `periodFrames`/`periodicity`/`cycleCount` (artık GERÇEK sayı) /
  `cycleStartFrame`/`phaseMargin`/`secondCycleCost` (raporlanır,
  eşiklenmez — ölçülmemiş sınır kapı kurmaz). Araç: `--no-cycle-segmentation`.
  Kabul (Lissom sınaması): aynı kaynaktan iki rep-segmenti temiz malzemede
  <0,5° (3 karelik faz hatası ~11° okurdu).
- **CycleAligner runner-up ayrımı düzeltildi (ölçülen sessiz-yanlış):**
  eski `periyot/8` ayrımı, rakip fazı hizalayıcının KENDİ warp menzilinin
  içinde bırakıyordu — band 8'de 9 kare uzaktaki aday 0,005'e geri
  warplanıyor, "margin" faz netliğini değil warp kapasitesini ölçüyor,
  TEMİZ periyodik malzeme "belirsiz" okunuyordu (yanlış-negatif). Yeni
  ayrım: `max(periyot/8, band+minBand+1)`; kalıntı 4 karede margin 0,086
  ölçüldü. Ayrım yükselmesi runner-up maliyetini yalnız yükseltir — önceden
  çözülen çözülü kalır. Periyot < 2·ayrım ise dürüst yeni sebep: "warp
  menzili dışında aday yok" (eski kod aynı malzemeye zaten yanıltıcı
  sebeple 'ambiguous' diyordu).
- **0.7.3 adversarial inceleme bulguları (Opus, 3 HIGH):** (HIGH-2) CLI
  ön-kapısı hiçbir dışlama yokken de ateşlenip builder'ın gerekçeli
  mesajlarını (M-F-38 + tek-öğretmen kaçış kapısı) gölgeliyordu → yalnız
  gerçek dışlama varken konuşur. (HIGH-3) tek-take havuzu yapısal olarak
  imkânsızken "no measurable overlap with peers" diye anlaşma-kapısı reddi
  gibi raporlanıyordu — L-143'ün hâlâ açık bir yüzü → build n=0/n=1'i
  gerçek sebeple reddeder. (MEDIUM-2) `--min-takes 0` + boş havuz çöküşü
  kapandı. (MEDIUM-3) araçta argüman/girdi hataları isimli yüzey aldı
  (ARGÜMAN HATASI 64 / GİRDİ HATASI 65), yükleme try-dışı tuzağına yorum.
  (MEDIUM-1) araç çıkış kodları + "no measurable overlap" metni + RangeError⊂
  ArgumentError öncülü artık testli. (LOW-3) `resolveMirroring` n<2'de
  `gapMeasured: false` (M-O-25 disiplini komşusuna uygulandı). ⚠️ AÇIK:
  (HIGH-1) 1-karelik take bütün-take yolunda sahte "variance" toleransı
  üretebiliyor — periyodik malzemede segmentasyon isimle kapatıyor
  (testli); statik yol için ölçümlü tasarım işi DEFTER'de.
- Test: 191/191 (+14). Gerçek-veri: boxing_stance 3 fixture yeniden koşuldu
  — segmentasyonsuz bit-bit aynı; varsayılanla 3/3 take dürüstçe
  "moving but not repeating" + `notApplied` beyanı.

## 0.7.3 — 2026-07-29 (yeni vardiya, tur 1)

- **L-143 P0 düzeltmesi (Lissom buldu):** her karesi tespitsiz/kapı-düşen
  bir fixture BOŞ take olarak builder'a giriyor, çöküş konsensüs
  matematiğinin derinliğinde patlıyordu — tek fixture'ta `StateError: No
  element` (`base.first`), çoklu koşumda `RangeError: Invalid value`
  (boş warp yolu). Ve `RangeError extends ArgumentError` olduğu için araç
  bunu "REDDEDİLDİ (sayı/kaynak kapısı)" diye basıyordu: **kod kusuru,
  politika reddi kılığında** — saat kaybettiren sınıf. Üç katman:
  (1) `ReferenceBuilder.build` boş-kareli take'i SAYIM ÖNCESİ isimle
  reddeder; (2) `ReferenceCli.buildArtifact` boş take'i isimle dışlar
  (`excludedNoMeasurableFrameIds` + take raporunda
  `excluded: noMeasurableFrames`) ve havuz kapıların altına incelirse
  DIŞLAMA SEBEPLERİYLE birlikte reddeder ("ret isimli+sebepli" kuralı);
  (3) araçta `RangeError`/`StateError` artık "İÇ HATA — kod kusuru, kapı
  reddi DEĞİL" (exit 70), kapı retlerinden ayrı. Ek:
  `ReferenceAgreementError` sonsuz sapmayı "Infinity°" diye değil "no
  measurable overlap with peers" diye yazar (yapısal boşluğa sayı
  elbisesi giydirilmez). Test: 177/177 (+4: builder guard'ı · isimli
  dışlama + devam · tek-fixture repro · incelen-havuz sebepli ret).

## 0.7.2 — 2026-07-29 (tur 26-ek2)

- **M-O-29 / beşinci canlılık sorusu ("bu kapıya soran var mı?"):** rig
  M-F-43 gereği her hasat fixture'ına `referenceEligible` yazıyordu ve HİÇBİR
  tüketici okumuyordu — bu CLI'nin ilk sürümü dahil. `TakeEligibility`
  (attested/firstParty/unattested/ineligible) + fail-closed kabul:
  ineligible DAİMA dışarı (isimle) · hasat-ama-beyansız varsayılan dışarı,
  `--allow-unattested` ile girebilir ama artefakt `measurementProvenance:
  PROVISIONAL` damgalanır (Ostinato'nun M-C-01 disiplini şemaya alındı) ·
  ilk-parti kayıtlar rig sınıflandırması dışında, serbest. Artefakta
  `excludedIneligibleIds` + `excludedUnattestedIds` + take-başına
  `eligibility`. Test: 173/173 (karma-uygunluk + PROVISIONAL + açlık-reddi).

## 0.7.1 — 2026-07-29 (tur 25-ek2)

- **M-O-25 P0 düzeltmesi (Ostinato buldu):** n>12 fallback yolunda
  `runnerUpGap` 2×marj SENTİNEL'iyle kodlanıyordu → `confident` tam da
  ölçülemediği yerde DAİMA true (kanıt: iki bağımsız havuzda birebir aynı
  yuvarlak 0,04000; tükenmeli yoldan geçen tek havuz dürüst `false` verdi).
  Düzeltme: bilinmeyen bilinmeyen olarak okunur — fallback'te
  `runnerUpGap = NaN`, yeni `gapMeasured` alanı (bayrağın DAYANAĞI),
  `confident` yalnız ölçülmüş gap ya da prior ile true; per-take marjı
  geçen flip'ler uygulanmaya devam eder (güven iddiası ayrı, atama ayrı).
  `CanonicalReference.mirrorGapMeasured` + CLI artefaktına eklendi.
- **M-O-26 eşik-çakışması:** aile kalite hedefi (havuz başına ≥12 kabul)
  tükenmeli-arama sınırıyla (n≤12) çakışıyordu — kalite barını TUTTURAN her
  havuz ölçülmüş gap'ini kaybediyordu. Sınır 12→18 (ölçüldü: n=18 uçtan uca
  777 ms, build-zamanı işi). n>18 hâlâ fallback = artık dürüstçe unmeasured.
- Test: 172/172 (2 yeni: unmeasured-gap dürüstlüğü n=19 + ölçülmüş-yol n=13).

## 0.7.0 — 2026-07-29 (tur 25)

- **KANONİK REFERANS-CLI (M-F-46 üretim yanı):** `tool/build_reference.dart` +
  `ReferenceCli` (lib/src/tooling/) — mantık kütüphanede yaşar, araç yalnız
  argüman ayrıştırır: app-side çağıran da AYNI fonksiyonu koşar ("kanonik"
  ancak böyle doğru kalır; Gravita'nın 3-kapılı tasarımı temel).
  Boru: fixture decode (v1+v2) → J-028 izotropik (frameSize varsa; yoksa
  artefakt bunu SÖYLER) → güven kapısı (yumuşatılmış: required'ın ≥%60'ı +
  gövde güvenilir + kadraj-içi; düşen kare SAYILIR) → normalize → açı-uzayı →
  ReferenceBuilder (minTakes/minSources/M-F-47).
  Artefakt `motion-core/reference@1`: gates bloku · take-başına
  frames/undetected/gateDropped/`cycleCount: null` (ÖLÇÜLMEDİ demek —
  makul sayı uydurulmaz, Choreia thinEvidence dersi tersinden) ·
  mirrored/excluded/priorDisagreements · eklem-başına tolerans KAYNAĞI
  (G-050: yalnız `variance` "varyans-türetimli" iddiası taşır) +
  floorBoundShare · meanRad/dispersionRad + tolerans parametreleri.
  Retler yutulmaz: sayı/kaynak kapısı=65, anlaşma kapısı=66 çıkış kodu.
- Test: 170/170 (3 yeni: iddia-artefakt eşleşmesi · tel-formatı gidiş-dönüş
  değişmezliği · tek-eğitmen-altı-kanal reddi) + gerçek dosyalarla CLI duman
  testi (6 fixture → 17 eklem × 64 kare artefakt).

## 0.6.1 — 2026-07-29 (tur 23)

- **Tolerans-kaynağı etiketi (G-050/M-F-55, Gravita'nın bulgusu):** ilk gerçek
  referansta 9/9 eklemin dağılımı (5,9-8,0°) 8° tabanının ALTINDA çıktı —
  yayımlanan her tolerans varyans kılığında tabandı. `ToleranceSource`
  (`variance|floor|ceiling|unmeasured`) + `toleranceSourceAt()` +
  `floorBoundShare()` (eklem-başına taban-bağlılık oranı; 1.0 = tolerans bir
  kez bile ölçülmüş ayrışmadan gelmedi). Yalnız `variance` "varyans-türetimli"
  iddiasını taşıyabilir; taban bağlıyorken G-014 kapanmaz. Test: 167/167
  (sıkı-küme=floor + stilli-kol=variance karşıt-çifti).

## 0.6.0 — 2026-07-29 (tur 22)

- **Fixture şema-v2 köprüsü (referans-CLI ön şartı):** Dart okuyucu ile Python
  hasat hattı (mocore SCHEMA_VERSION=2) iki lehçeye ayrışmıştı — Dart v2
  dosyayı REDDEDİYORDU. Algoritmayı Python'da yeniden yazmak M-F-21 sınıfı
  çifte-üretim olurdu; köprü tek sınırda kuruldu:
  * `readableSchemaVersions = {1,2}` (yazıcı v1'de kalır — Python'la aynı
    desen: okuyucu ileride, yazıcı güncel-yazdığında).
  * Kompakt kare lehçesi: `t` ms→µs · `lm[[x,y,z,vis,presence]]` →
    `PoseLandmark` (presence BİLİNÇLİ düşülür — tüm kapı eşikleri visibility
    ile kalibre; katlamak hepsini sessizce kaydırırdı).
  * Tespitsiz kare 33 sahte-sıfır landmark'la DOLDURULMAZ — düşülür ve
    `undetectedFrameCount` ile sayılır (boşluk zaman sıçraması + sayaçtan
    görünür; kapsam matematiği şişmez).
  * `ProvenanceInfo` (sourceUrl/license/channel/extractor + ham blok) —
    `sourceIdentity` = minSources kapısının "bir eğitmen" kimliği.
  * `RecordingMeta`: snake_case anahtar kabulü + `technique` + `resolution`
    → `frameSize` (J-028 izotropik düzeltme girdisi).
- Doğrulama: 166/166 test (6 yeni köprü testi) + 3 GERÇEK hasat fixture'ı
  (~/motion-harvest, 7.6k-11.7k kare) uçtan uca çözüldü; source alanı gerçek
  kanal kimliklerine bağlandı. Not: hasat dosyalarında technique=unknown —
  hareket kimliği manifest'tedir, CLI tekniği argümandan alacak.

## 0.5.1 — 2026-07-29 (tur 21)

- **`ReferenceBuilder.minSources` kapısı (M-F-53(2), Gravita'nın bulduğu sayım
  boşluğu):** `minTakes` TEKRAR sayar, M-F-38 EĞİTMEN sayar — tek eğitmenin 12
  tekrarı sayı-kapısını geçer ama eğitmenler-arası varyans (dispersiyon-türevli
  toleransın TEK kaynağı) hakkında sıfır bilgi taşır. İki kontrol noktası:
  * ham girişte distinct `source` < `minSources` (varsayılan 3) → `ArgumentError`
    (fail-closed; `minSources: 1` yalnız BEYAN EDİLMİŞ tek-eğitmen prototipi
    için — toleransı "stil" olarak okumayı üstlenerek).
  * M-F-47 anlaşma-kapısı SONRASI küme içinde de sayılır: aykırı-dışlama bir
    take değil bir İNSANI düşürdüyse (take sayısı hâlâ yeterli görünürken)
    `ReferenceAgreementError` — sayı-kapısının yapısal olarak göremediği durum.
- Test: 160/160 (3 yeni — aynı-kaynak reddi, prototip kaçış kapısı,
  küme-kaynak-çöküşü; süit sonucu sürüm notundan ÖNCE koşuldu ve görüldü).

## 0.5.0 — 2026-07-29 (tur 18)

- **ReferenceBuilder büyük yükseltme (M-F-47/48 + M-J-06):**
  * `resolveMirroring` GLOBAL atama problemi olarak çözülür (tam tarama n≤12,
    take-0 sabit; çift pair-cost tablosu) — "dosya sırasına bağlı uzlaşma
    uzlaşma değildir" (Choreia ölçümü). Mutlak konvansiyon: AZINLIK çevrilir;
    yakın-beraberede HİÇ çevrilmez + `confident:false` raporlanır.
  * `build(..., leadSidePrior:)` — ölçülmüş öncü-taraf önseli konsensüsü
    ezer, uyuşmazlık RAPORLANIR (n küçükken yanlış-çözülen konsensüs sessiz).
  * **M-F-47 anlaşma kapısı:** sayı kapısı anlaşmayı ölçmez — take-başına
    medyan-eklem sapması ≤14° kümesi ister; aykırı ADLA dışlanır
    (`excludedOutlierIds`), küme<minTakes → `ReferenceAgreementError`.
    İstatistik seçimi kuralın anlamını taşır: farklı-hareket çoğu eklemde
    sapar (medyan yüksek → dışla), stil azınlık eklemde (tolerans olur,
    dışlanmaz).
  * `CanonicalReference` yeni alanlar: mirrorConfident/excludedOutlierIds/
    priorDisagreements. 158/158.

## 0.4.3 — 2026-07-29 (tur 15)

- **G-038 (P1) bileşim kusuru:** `ConfidenceGate.evaluate` artık `xExtent`
  alır — izotropik uzayda x ∈ [0, aspect]; ham [0,1] sınırıyla kapılamak
  sağ-yarı deneği sessizce "kadraj dışı" sayıyordu (ölçüldü: %5-14 → %0).
  Bileşim testi eklendi. Ayrıca fixture `t` birim beyanı (G-040: birim de
  bir beyandır — ms). 155/155.

## 0.4.2 — 2026-07-29 (gece vardiyası, tur 12b)

- **M-J-07: `$` önekli anahtar her düzeyde yok sayılır** — "sayı kendi
  gerekçesini taşır" aile pratiği config'te yaşar; kural 8'in katılığı
  değişmedi (yazım hatası hâlâ sert hata — testli). 154/154.

## 0.4.1 — 2026-07-29 (gece vardiyası, tur 12)

- **Okuyucu, mühürlü şemaya hizalandı (M-O-10 + Gravita M-talebi):**
  `verdictGates` parse ediliyor (collectNoVerdict/discardWindow — atlanmıştı) ·
  `requires:{landmarks,signals}` iç-içe biçim + sinyal ön-koşulları op/value
  taşır (SNR ≥6dB artık düzyazı değil) · `measurementSpace: world|isotropic|
  pixel` (M-O-08/J-028) · `fastTransition` bayrağı + cutoffHz zorunluluğu
  ARTIK DOĞRULANIYOR (düzyazı-kural kod-kuralı oldu) · `ErrorSpec.cue`
  (koçun söyleyeceği söz — içeriksiz koçlanan hata sessizce düşer).
  5 yeni test; 152/152. Şema-tarafı kalanlar (quality yön-bilgisi,
  signalConditioning yuvası, evaluateAt doc netleşmesi) v3.1 kalemi.

## 0.4.0 — 2026-07-29 (gece vardiyası, tur 11)

- **`PhaseConfig` — mühürlü v3.0 şemasının kanonik okuyucusu (M-F-40):**
  model + KATI parser (bilinmeyen alan = sert hata; kare-başına delta parse
  anında red — L-069) + aile-değişmezleri doğrulayıcısı (#1 timeout/J-009 ·
  D1 cyclic/repCompletedOn · M-F-06 ham-taraf yasağı · tanımsız-metrik ·
  G-016 menzil · #9 uç-örtüşmesi/V11 · #11 perturbasyon≥noiseBand/C-011).
  Bu artırım = config linter'ı (5 app bugün koşabilir); PhaseStateMachine
  evaluator'ı sonraki artırım. 13 test; toplam 148/148.

## 0.3.0 — 2026-07-29 (gece vardiyası, tur 5)

- **`FrameSize` + `PoseFrame.toIsotropic` (M-F-30/J-028 kanonik API):** ham
  normalize uzay anizotropiktir; geometriye girmeden önce izotropik uzaya
  (kare-yüksekliği birimi) dönüşüm artık çekirdekte. Üç app'in gece bağımsız
  yazdığı düzeltme (JabLab FrameSize · Gravita toIsotropic · Choreia
  aspect-corrected lm) bu API'de birleşir; app-side kopyalar devredilir.
  Değişmezlik-deseni testli (eğik-açı sondası; eksene-hizalı açı ölçeklemede
  bükülmez — o tuzak testin kendisinde kapatıldı). Toplam: 135/135.

## 0.2.1 — 2026-07-29 (gece vardiyası, tur 4)

- **G-018 kalibrasyonu:** `StructuralValidator.bilateralTolerance` varsayılanı
  0.35 → 0.55 — eski değer Gravita D1 gerçek-kare setinde DOĞRU karelerin
  %32'sini reddediyordu (2D perspektif kısalması; model hatası değil). 0.55'te
  yanlış-red ~%8-11, #21 kendinden-emin takas hâlâ yakalanıyor (Gravita
  regresyon fixture'ı kanıt). Davranış değişikliği: yapısal denetimi ham
  varsayılanla kullanan app'ler daha az yanlış-red görür.
- Hasat rig'i: `--triage-profile` CLI (Lissom) + `movement_isolator`
  (Choreia terfisi — "bu kısım hareketin kendisi mi?" periyodiklik+enerji
  penceresi; anlatım-eleme). Rig testleri 17/17.

## 0.2.0 — 2026-07-29 (gece vardiyası)

- **`CycleAligner` (M-C-18, Choreia blokajı):** periyodik içerik için
  döngü-farkında hizalama — sabit-uçlu DTW'nin faz uyuşmazlığında dayattığı
  kötü hizalama yerine faz araması + döngü-başına bantlı `Dtw`. Belirsiz fazda
  (statik/faz-simetrik malzeme) `resolved:false` = hüküm yok; iki-döngü
  kararlılık sondası; periyotlar ÇAĞIRANDAN gelir (tahmin edilmez). 6 test.
  Kırılma yok — `Dtw` API'si aynen duruyor. Toplam: 132/132.

## 0.1.0 — 2026-07-29 (ilk etiketli sürüm)

Kanonik Dart çekirdeğinin ilk kararlı kesiti (M-017/M-F-03 hükmü: bu paket
çalışma-zamanı motorunun normatif referansıdır; Python `mocore` yalnız
video→fixture/G1-ölçüm aracıdır).

### Modüller
- **pose:** `PoseFrame` · `ConfidenceGate.forVariant` (M-018/M-020) ·
  `StructuralValidator` (M-019; `check(frame, expected:)` faz-eksen denetimi
  dahil — G-010) · `BodyOrientation`/`observedOrientation` ·
  `OrientationAwarePoseSource` (Gravita ADR-001: beklenti + histerezis +
  belirsiz fazda çift-geçiş) · smoothing.
- **geometry:** `Vec3` · normalizasyon (orta-hat referanslı) · eklem açıları.
- **scoring:** açı-benzerliği · bantlı DTW + `warpPenalty` (M-C-05 park-etme
  düzeltmesi) · `SequenceComparator` · `ReferenceBuilder` (M-C-04: ≥3 eğitmen,
  aynalama konsensüsü, varyans→tolerans).
- **rhythm:** `BeatGrid` · `PerceivedBeatTimeline` + `AudioLatencyProfile` ·
  `LatencyCalibrationStore`/`TapTestCalibrator` (M-F-08, route-başına) ·
  `CueGate` (koç-sesi analiz zaman-kapısı) · `TimingJudge`.
- **engine:** faz durum-makinesi çatısı · feedback önceliklendirici+cooldown ·
  `MotionClock` (audio+motion tek monotonic saat sözleşmesi) ·
  `AttemptProvenance` (M-F-07: karşılaştırılabilirlik kapısı).
- **fixture:** fixture/replay harness · sentetik iskelet üreticisi + gürültü.

### Test
123 test yeşil; `dart analyze` temiz.

### App'lere pinleme talimatı
```yaml
dependencies:
  motion_core:
    git:
      url: https://github.com/kocakkmustafa/motion-core.git
      ref: motion_core-v0.1.0
      path: packages/motion_core
```
