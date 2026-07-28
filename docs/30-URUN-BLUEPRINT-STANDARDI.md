# Yula Motion — Ürün Blueprint Standardı (5 app'in ortak omurgası)

**Tarih:** 2026-07-28 · **Statü:** Kurucu direktifiyle bağlayıcı — her app'in `<APP>-BLUEPRINT.md`'si bu standardı devralır; oturumlar ikisini birlikte okur.
**Hiyerarşi:** `00-AILE-MIMARISI` > `20-URETIM-SURECI` > `10-ARAC-KATALOGU` > **bu dosya** > `<app>-BLUEPRINT.md` > roadmap > plan.

---

## 1. Nihai ürün tanımı (hepsi için aynı çıta)

Uygulama "bitti" = kullanıcı store'dan indirir, onboarding'den geçer, **kütüphanenin TAMAMI düzenli sayfalarda gezilebilir**, kurs seçer, canlı seansta sesli koçluk alır, ilerlemesini grafiklerle görür, abonelik akışı çalışır, çökmez, offline çalışır — **pazarlamaya ve reklama hazır tam ürün.** Oturumlar uygulama bu tanıma ulaşana dek göreve devam eder; yarım özellik gizlenmez, kapsamdan çıkarılıp DEFTER'e yazılır.

## 2. Bilgi mimarisi (IA) — "her öğe kendi sayfası" (kurucu direktifi)

Hiçbir içerik dağınık listede yüzmez. Dört seviyeli standart hiyerarşi:

```
Ana Sayfa (bugünkü plan + devam eden kurs + hızlı başlat)
└── Kütüphane (disiplin/çalgı/stil/hareket-ailesi kartları — dalga dalga açılır)
    └── ÖĞE SAYFASI (her dövüş sanatı / çalgı / dans stili / beceri ailesi / test-program ailesi KENDİ sayfası):
        tanıtım + seviye haritası + KURS LİSTESİ + progresyon/istatistikleri + "bu öğede neler ölçülür/ölçülmez" dürüstlük kutusu
        └── KURS SAYFASI (ders listesi + hedef + süre + ön-koşul)
            └── DERS/SEANS AKIŞI (öğret → dene → canlı analiz + sesli koç → özet → sonraki adım)
```

- Kütüphane içinde arama + filtre (seviye, süre, ekipman) + "tüm kurslar" dizini ZORUNLU.
- Henüz açılmamış dalga içerikleri sayfada "yakında" olarak görünür (kapsamın tamamı kullanıcıya baştan görünür — dar app algısı yaratılmaz), ama SAHTE/boş kurs asla listelenmez.
- ❌ kapsam-dışı öğeler için tek "Neden yok?" sayfası (dürüstlük notları — ör. JabLab'da grappling).

## 3. UI ilkeleri — basit, kolay, dikkat çekici

- **2-tık kuralı:** ana sayfadan aktif kursa ≤2 dokunuş; kütüphaneden herhangi bir kursa ≤3.
- **Canlı seans ekranı ürünün yıldızı:** kamera + iskelet-avatar + tek-düzeltme; metin minimal, ses birincil (telefon uzakta).
- Tek elle kullanım; alt-tab navigasyon (Ana · Kütüphane · İlerleme · Profil); dark/light; %200 font taşmasız.
- Görsel kimlik G7'de Claude Design ile — iskelet önce, cila sonra; her app kendi karakterinde ama aile DNA'sı ortak (design-system token'ları motion-core desenli).
- Öğretim görseli: §6.4 T1 iskelet-avatar; skorlar açıklanabilir bileşenlerle (tek kara-kutu sayı yok).

## 4. Uçtan uca yürütme (oturum sözleşmesi)

1. Blueprint'i oku → roadmap'ine dalga tablolarını + görev backlog'unu İŞLE (roadmap yaşayan belge; blueprint kapsam otoritesi).
2. G-fazlarını (20-URETIM-SURECI) dalga-bazlı döngüyle koş: **Dalga N için G3→G6 içerik/motor döngüsü, platform katmanı bir kez** (G5'te). Kapı kanıtsız faz atlanmaz; şartlı-geçiş (§2.6) geçerli.
3. **/loop + DEFTER yöntemi:** her iterasyon doğrulanmış-test-edilmiş-gerçek bilgiyle; bulgular ID+şiddet+kanıtla; P0 açıkken yeni kapsam yok.
4. **Vault kaydı:** her önemli ilerleme/karar Obsidian'a (`20 Şirketler/Motion/` pano satırı + app oturum-devri); teknik detay repo docs/DEFTER'de kalır, vault özet+işaretçi taşır.
5. **Manuel işler sona:** kurucu-eli gerektirenler (onaylar, harcamalar, cihaz-benchmark G8, uzman turu, submission) biriktirilir; akış durmaz.
6. Kurucuya SORU YOK — kapsam bu blueprint'te kesin; boşluk bulursan blueprint çerçevesinde kendin karar ver, DEFTER'e yaz.

## 5. Token-optimal ajan düzeni (bağlayıcı)

| İş | Koşum |
|---|---|
| Sentez, mimari, kapı analizi, kod tasarımı | Ana oturum (Fable, high) |
| İçerik hasadı (kaynak listesi→çıkarım→config), l10n, boilerplate, tekil modül kodu | Alt-ajan `model:'sonnet'` — bağlam gömülü, keşif YASAK, git-yazma YASAK |
| Çok-parçalı taramalar (kurs envanteri, kaynak doğrulama) | Workflow fan-out (sonnet), sonuç ana oturumda damıtılır |
| Riskli sınıf (IAP, gizlilik, çocuk-verisi, store submission) | Fable + **Opus bağımsız doğrulama** |
| Mekanik denetim | Betik/CI (LLM-denetim değil) |
Projeye özel kalıcı alt-ajan/Workflow gerekiyorsa `.claude/agents/`e tanımla + AGENTS.md/registry güncelle (PMI: WBS, kilometre taşı=G-kapıları, risk kaydı=DEFTER).

## 6. Cephanelik (ortak — app blueprint'leri buna ekleme yapar)

**Motorlar (motion-core):** pose state-machine çatısı · StructuralValidator · ConfidenceGate.forVariant · ReferenceBuilder (≥3-eğitmen konsensüs) · Dtw.warpPenalty **→ paylaşımlı DTW uzun-sekans motoru** (kata/form/dans) · **RhythmEngine** (beat-grid+onset-sapma; ses/MIDI/pose kaynak-bağımsız) · TTS/ducking · termal monitör · fixture/replay harness · Drift/SQLCipher depolama.
**Araçlar:** MediaPipe Pose/Hand/ObjDet (Apache) · Basic Pitch (Apache) · AudioKit (MIT) · SwiftF0 (MIT) · sherpa-onnx+Kokoro (V2 ses) · `health` paketi (HealthKit/Health Connect) · flutter_midi_command/universal_ble (BSD) · Pigeon · hasat rig'i (yt-dlp+PySceneDetect+MediaPipe-batch+dedup+faster-whisper+provenance).
**Danışmanlar:** motion-cv-engineer · movement-science-advisor · audio-dsp (Ostinato) · game-design-architect · uiux-designer · design-systems-architect · qa-test-engineer · mobile-runtime-tester · privacy-data-guardian · store-policy-officer · marketing-aso-specialist · pricing-monetization-strategist.
**Skills:** flutter-* ailesi, riverpod, mocktail, patrol-e2e-testing, /loop, /oturum-kapanisi.
**Yasaklar:** katalog §0 (AGPL/GPL, LocateAnything, SMPL, FLUX-dev self-host, MPG setleri) — değişmedi.

## 7. Platform katmanı (bir kez, 5 app'te)

Onboarding+hedef+kamera-sihirbazı · kurs/plan motoru · streak/rozet/challenge (yerel; leaderboard erteli) · ilerleme grafikleri · hatırlatıcı · offline · profil+hesap-silme · paywall (assessment-kapılı; fiyat kurucu) · paylaşım kartı/referral · HealthKit/Health Connect yazımı · Live Activities/widget (+watchOS yalnız HR/kumanda) · review-prompt bütçesi (~3/yıl, pozitif-seans sinyaline bağlı) · **referans-konsensüs aracı** (içerik temposunun bel kemiği; kadans dalga-bazlı/aylık — haftalık rakip temposu taklit edilmez).

## 8. Dürüstlük + güvenlik değişmezleri

Tork/güç yok ("hız/tempo" dili) · nota-nota polifonik transkripsiyon iddiası yok · embouchure yok · nefes ölçümü yok · klinik/tanı dili yok · elit beceriler rozetsiz · blur'lu fazlar "checkpoint koçluğu" olarak açık · düşük güvende hüküm yok · her sayfada "neler ölçülür/ölçülmez" kutusu · güvenlik uyarıları (düşme, boyun, backbend, heels) kırpılmaz · Art.50 AI-görsel ifşası.
