# Yula Motion — TAM KAPSAM ONAY RAPORU (kurucuya)

**Tarih:** 2026-07-28 · **Statü:** ✅ **KURUCU-ONAYLI (REVİZYONLU)** — nihai kapsam artık app-başına BLUEPRINT dosyalarındadır; bu rapor tarihsel temel + revizyon kaydıdır.

> **REVİZYON KAYDI (kurucu, 2026-07-28):** JabLab'dan Cardio-Kickboxing modu + Krav Maga ÇIKARILDI (❌'ler zaten dışarıda) · Ostinato ~35 çalgıya GENİŞLETİLDİ (modül-eşleme mimarisiyle; DJ/prodüksiyon ❌) · Choreia ~30 stile GENİŞLETİLDİ (Ballroom/Latin Solo ailesi, Tap/Flamenco/Irish onset-skorlamalı, Funk Styles paketi, Samba no Pé...; Hula ortaklık-şartlı beklemede) · Gravita fitness'ın profesyonel-önerili hareketleriyle GENİŞLETİLDİ (hareket-sınıfı kuralları A/B/C/D; makineler ❌; ~120-180 küratörlü hareket) · Lissom değişmedi. Ek araştırma korpusu: `2026-07-28-kapsam-genisletme-korpusu.md`.
> **KANONİK KAPSAM DOSYALARI (oturumlara verilecek):** motion-core `docs/30-URUN-BLUEPRINT-STANDARDI.md` (ortak omurga) + her app reposunda `docs/<APP>-BLUEPRINT.md`.
**Kaynak:** 7-ajanlık derin web araştırması (~590k token; korpus: `2026-07-28-tam-kapsam-arastirma-korpusu.md`); her iddia URL'li, zayıf kanıtlar işaretli.
**Direktif:** Her app TAM KAPSAMLI, bitmiş ürün olacak — dünya genelinde kurs talebi olan popüler her şey dahil; dalga dalga (sırayla) inşa serbest, dar odak yasak; mantıksız/çelişen/fiziksel-imkânsız hiçbir şey yok.

---

## 0. Okuma anahtarı
- ✅ = tek sabit telefon kamerası + on-device analizle tam yapılabilir · ⚠️ = yapılabilir ama adı konmuş kısıtla (yanında yazıyor) · ❌ = fiziksel/hukuki olarak yapılamaz (nedeni yazıyor) — ❌'ler kapsama GİRMEZ, uygulamada "neden yok" dürüstlük notuyla anılır.
- "Dalga" = inşa sırası. Dalga 1 çekirdek motorları kurar; sonraki dalgalar çoğunlukla İÇERİK + küçük motor ekidir. Kütüphane hasadı (referans çıkarımı) TÜM dalgalar için baştan paralel yürür.

## 1. JABLAB — "Solo Combat Training" (10 disiplin + 2 gerekçeli hariç)

| Dalga | Disiplin | Fizibilite | Not |
|---|---|---|---|
| V1 ✅ | Boks | ✅ | Mevcut motor (1-6 yumruk numaralandırması) |
| 1 | **Kickboks** | ⚠️ tekme blur/oklüzyon | Yumruk motoru + tekme sınıflandırıcı (chambering-diz tespiti); kardiyo-kickboks pazarı ABD'de en hızlı büyüyen fitness aktivitesi (+%8.5 SFIA) |
| 1 | **Tai Chi** | ✅ (en kolay!) | 78M-250M arası uygulayıcı; yavaş form = sıfır blur → **DTW uzun-sekans motorunun kurulacağı yer** |
| 2 | **Karate (kihon+kata)** | ⚠️ embusen/yer-deseni takibi | 50-100M uygulayıcı; kata skorlaması akademik emsalli (F-DTW %91); kemer müfredatı hazır yapı |
| 2 | **Muay Thai** | ⚠️ klinç YOK (simüle drill) | Dirsek+diz+teep sınıflandırıcıları; IFMA 128 federasyon |
| 2 | **Fitness/Cardio Kickboxing modu** | ✅ | Yeni motor yok — UI modu + BPM senkron katmanı |
| 3 | **Taekwondo (poomsae+tekmeler)** | ⚠️ EN ZOR: dönen/sıçrayan tekme blur | ~80-100M; poomsae = kata motoru; sıçrama tekmeleri görünür doğruluk-uyarısıyla |
| 3 | **MMA Striking modu** | ✅ | Boks+Kickboks+MT birleşimi — repaketleme |
| 3 | **Krav Maga "Combatives Conditioning"** | ⚠️ öz-savunma İDDİASI YOK | Yalnız solo vuruş drilleri; ad "conditioning" olarak çerçevelenir |
| 4 | **Wing Chun (solo formlar)** | ⚠️ ince el hassasiyeti | Siu Nim Tao neredeyse sabit — pose-dostu; kanıt en zayıf → Dalga 4 |
| ❌ | BJJ/Güreş/Judo | ❌ partner teması/direnci zorunlu | Yalnız dar "solo conditioning" (ukemi/stance drilleri) ileride opsiyonel |
| ❌ | Silahlı sanatlar (Kali/Kendo/HEMA) | ❌ tekniği SİLAH konumu tanımlar (pose-dışı) | Kapsam dışı |

**Yeni motor ihtiyaçları:** tekme sınıflandırıcı · **paylaşımlı DTW uzun-sekans motoru** (kata/poomsae/form — Choreia'nın dans motoruyla AYNI aile, bir kez yazılır) · dirsek/diz/teep sınıflandırıcıları · form-embusen yer-deseni takibi.

## 2. OSTINATO — "Music Practice" (13 çalgı, 6 dalga)

| Dalga | Çalgı | Fizibilite | Not |
|---|---|---|---|
| 1 | **Şan/Vokal** | ✅ en temiz | Monofonik pitch (mevcut motor) + vibrato metriği (rakip Yousician'ın itiraf edilmiş boşluğu!) + postür; ABD ders talebinin ilk 3'ü |
| 1 | **Piyano/Klavye** | ⚠️ polifoni sınırı | "Akor-sınıfı doğrulama + postür/el koçluğu" — nota-nota transkripsiyon İDDİA EDİLMEZ. **MIDI modu: klavye bağla → mükemmel veri** (BSD Flutter paketleri) |
| 1 | **Gitar (akustik+elektro)** | ⚠️ polifoni sınırı | 50M+ çalan; akor şekli el-landmark + Basic Pitch akor-sınıfı; ABRSM/RockSchool müfredat yapısı |
| 2 | **Ukulele** | ✅ | Gitar motorunun 4-tel konfigi — neredeyse bedava |
| 2 | **Bas gitar** | ✅ | Monofonik → gitardan KOLAY |
| 3 | **Keman** → **Çello** | ⚠️ yay hassasiyeti | Yaylı modül (monofonik pitch + yay-postür); çello keman motorunun oturan varyantı (mevcut V1 işi buraya oturur) |
| 4 | **Flüt → Saksofon → Klarnet → Trompet** | ⚠️ **embouchure GÖRÜLMEZ (❌ vaat edilmez)** | Nefesli modül: pitch + artikülasyon-onset + ton-sustain + postür; ağız-içi teknik kameraya fiziksel olarak kapalı (literatür: sensör gerektiriyor) |
| 5 | **Davul/Perküsyon** | ⚠️ tek-pad V1 | AYRI ses paradigması (onset, pitch değil); PAS 40 Rudiment müfredatı; tam-kit hangi-davul ayrımı tek mikrofonla güvenilmez → pad/trampet zamanlaması önce |
| 6 | Mızıka (opsiyonel) | ✅ temel melodi | Resmî müfredat yok — bonus |

**Yeni motor ihtiyaçları:** **Basic Pitch (Spotify, Apache-2.0 ✅ birincil-kaynak teyitli)** akor-sınıfı polifoni · **MIDI giriş modu** (flutter_midi_command/universal_ble, BSD) · perküsif onset motoru (in-house spectral-flux — GPL'siz) · **paylaşımlı RhythmEngine** (beat-grid + onset-sapma skoru; ses/MIDI/pose kaynağı fark etmez — 5 app'te yeniden kullanılır) · vibrato dedektörü (mevcut pitch-akışından, yeni bağımlılık yok).

## 3. CHOREIA — "Learn to Dance" (20 stil, 4 dalga + hukuk-katmanı)

| Dalga | Stiller | Not |
|---|---|---|
| 1 | **Hip-Hop foundations · Zumba-tarzı fitness dans · Line Dance · Salsa shines · TikTok-format (orijinal kombolar)** | En yüksek talep + en temiz ✅; Zumba-tarzı: 15M haftalık katılımcı kanıtı (marka adı KULLANILMAZ — "Latin fusion fitness"); Line Dance = step-sheet formatı kural-motoruna birebir oturur |
| 2 | **K-Pop point-choreo · Bachata solo · Afrobeats · Dancehall · Shuffle · Belly Dance · Bollywood** | K-Pop ayna-modu zorunlu; Dancehall'da boyun-riski hareketler (Dutty Wine) hariç; Afrobeats craze'lerinde köken atfı |
| 3 | **Jazz · Balet/Barre (sandalye-destek modu) · Contemporary (ayakta alt-küme) · Kizomba/Zouk solo · Tango solo tekniği · Twerk (3/4 açı modu)** | Barre yerine ev desteği yönergesi; Contemporary yer-çalışması demo-only bayrağı; cambré derinliği skorla zorlanmaz |
| 4 | **Heels (ayakkabı-güvenlik onboarding'i ZORUNLU) · Breaking (yalnız toprock/uprock skorlanır; power move = demo-only + güvenlik uyarısı)** | Breaking ❌/⚠️ ayrımı en net madde: baş-aşağı dönüşler tek kamerayla skorlanamaz + yaralanma riski |

**Hukuk-katmanı bayrağı (içerik hattına gömülür):** 🟢 halk/sosyal adımlar serbest · 🟡 stil-temsili ORİJİNAL kombolar (viral rutin kopyalanmaz) · 🔴 adlı ticari koreografi/marka adı (K-Pop ajans rutini, film koreografisi, yayımlı step-sheet, "Zumba" adı) YASAK.

## 4. GRAVITA — "Skills & Strength" (5 dalga; kitle-pazar + beceri ağacı)

| Dalga | İçerik | Not |
|---|---|---|
| 1 | **Kitle-pazar form koçluğu: şınav · barfiks · dips · squat · lunge · plank · burpee** (rep sayma + form hataları) | En yüksek talep, en düşük risk, ekipmansız — Gravita'yı niş beceri app'inden kitle-pazar app'ine taşır |
| 2 | **Handstand ağacı (duvar→serbest→HSPU) + Planche ağacı (tuck→straddle→full)** | En iyi belgelenmiş müfredatlar (GMB/FitnessFAQs); D1 çözülmüş |
| 3 | **Front/Back Lever · Muscle-up · Pistol squat** | ⚠️ YENİ AR-GE: **bar/kenar tespiti** (kapı barfiks demiri — pose modeli barı bilmez); muscle-up patlayıcı geçişi faz-checkpoint'le (blur — kare kare skorlanmaz, dürüst dil) |
| 4 | **Rings temelleri · Bridge/backbend · Crow · L-sit/V-sit** | Rings sallanma-toleranslı smoothing ister |
| 5 | **Aspirasyonel (rozet YOK, rehberli): tek-kol handstand · Manna · Human flag** | Elit beceriler — "mastered" iddiası kameraca doğrulanamaz + düşme riski; flag dikey direk ister (çoğu evde yok — açık yazılır) |
| ❌ | Flips/aerials | ❌ güvenlik/felaket-düşüş riski (kamera değil, sorumluluk) | 

## 5. LISSOM — "Mobility & Yoga" (4 dalga)

| Dalga | İçerik | Not |
|---|---|---|
| 1 | **Genişletilmiş değerlendirme bataryası** (tek-bacak denge, ASLR, overhead squat, plank/rotasyon-stabilite eklenir) + **Hatha/Vinyasa/Yin üçlüsü** + **splits/kalça/hamstring hedef programları** | FMS-tarzı ama KLİNİK İDDİASIZ; açı-trend grafiği = gerçek farklılaştırıcı |
| 2 | **Chair/Office yoga** (aylık 60k arama, hızlı büyüyen) + **masa-başı/koşucu/lifter paketleri** + **backbend/omuz-açma programları** | %80 masa-çalışanı ağrı istatistiği |
| 3 | **Ashtanga temel seri + AİLE-İÇİ ISINMA PAKETLERİ** (JabLab dövüşçü ısınması · Choreia dansçı · Gravita hazırlık — app'ler arası deep-link çapraz satış) + **nefes/meditasyon** (yalnız SES-rehberli — kamera nefes ÖLÇMEZ, iddia edilmez) | Pliability'nin kendi genişleme stratejisinin aynısı |
| 4 (temkinli) | **Senior mobility** (tanı-değil dili + doktor-onayı kapısı; tek-bacak-denge testinin akademik dayanağı var) + **Prenatal** (sert medikal kapı + güvenli-poz alt-kümesi: ACOG-hizalı) | ❌ **Çocuk paketi YAPILMAZ** — model yetişkin-doğrulanmış + reşit-olmayan sorumluluğu solo kurucu kapasitesini aşar |
| Poz kütüphanesi | Tier-1 ~150-250 ayakta/oturan/diz-üstü poz ✅ · Tier-2 yer/supine ⚠️ (oklüzyon — gevşek skorlama) · Tier-3 inversiyonlar avatar-demo-only | "Complete" = katmanlı tanım (klasik 84 → 900+ üst sınır) |

## 6. EKSİKSİZ-ÜRÜN PLATFORM KATMANI (bir kez yazılır, 5 app kullanır)

✅ Onboarding+hedef+kamera-kurulum sihirbazı · yapılandırılmış kurs+günlük plan · streak/rozet/challenge (yerel; leaderboard ERTELİ — aile kuralı, STEEZY'nin 2026 özelliği "izlenen boşluk" olarak defterde) · ilerleme istatistikleri+trend grafikleri · hatırlatıcılar · offline · profil+hesap-silme (store zorunluluğu) · paywall (riskli sınıf: Fable+Opus) · paylaşım kartı+referral (sosyal-graf'sız) · **Apple Health/Health Connect yazımı** (`health` Flutter paketi, MIT) · **Live Activities/widget** (JabLab round-timer!) + watchOS yalnız HR/timer-uzaktan-kumanda (kamerasız — pose watch'ta YOK) · review-prompt bütçesi (~3/yıl — pozitif-seans sinyaline bağlı) · **yarı-otomatik referans-konsensüs aracı = en yüksek kaldıraçlı altyapı yatırımı** (solo kurucu STEEZY'nin haftada-3-ders temposuna ancak bununla yaklaşır; içerik temposu dalga-bazlı/aylık, haftalık taklit edilmez).

**App-başına delta:** Ostinato öğretmen-paylaşım (iskelet-render'lı — ham video ihlal edilmeden) + MIDI modu · Choreia müzik: kullanıcı-yerel + lisanslı sabit parçalar (serbest "müzik seçici" ❌ hukuken) · JabLab round-timer/Live Activity · Lissom yeniden-test döngüsü · Gravita skill-tree UI.

## 7. Dürüstlük sınırları (pazarlamada da geçerli — değişmez)
Tork/güç ölçülmez (hız-vekili "power" dili) · polifonik nota-nota transkripsiyon iddia edilmez · embouchure görülmez · nefes kamerayla ölçülmez · klinik/tanı dili yok · elit beceriler rozetlenmez · blur'lu fazlar "checkpoint'le koçlanır" diye açık yazılır · federasyon katılımcı sayıları "aralık + kaynak" ile verilir.

## 8. Onay sonrası işlenecekler (onay gelmeden DOKUNULMAZ)
1. 5 roadmap'e "TAM KAPSAM" bölümü (dalga tabloları + ❌ listesi + yeni motor işleri) + kapsam direktifi notu 00-AILE-MIMARISI'na (V1=sıra ilkesi zaten uyumlu).
2. Katalog güncellemeleri: Basic Pitch/MIDI/RhythmEngine/bar-tespiti/DTW-paylaşımlı-motor kayıtları.
3. Aile DEFTER: M-F-18 (tam-kapsam onayı) + yeni motor R&D kayıtları (bar-tespiti, tekme-blur pilotu, kata-DTW).
4. Vault: pano+hub+promptlar tazelenir; 5 oturuma "yeni kapsamı öğren" paketi.
5. Choreia G-1 planı ve Ostinato/JabLab plan revizyonları bu kapsamla yazılır/güncellenir.
