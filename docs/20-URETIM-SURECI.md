# Yula Motion — Üretim Süreci Sözleşmesi (Faz-Kapı Modeli)

**Tarih:** 2026-07-26 · **Statü:** Aile-geneli bağlayıcı süreç şablonu (5 app'in yol haritaları bu sürece referans verir)
**Hiyerarşi:** `00-AILE-MIMARISI.md` > bu dosya > app yol haritaları (`<app>-roadmap.md`) > app planları (`<app>-plan.md`). Çelişkide üstteki kazanır.

> Bu doküman "app üretimi büyük şirketlerde nasıl işliyorsa" sorusunun aileye uyarlanmış cevabıdır: **stage-gate (faz-kapı) modeli**. Her faz, bir sonrakine geçmeden önce KANIT ister. Solo kurucu + Claude ajan filosu için roller ajanlara eşlenmiştir.

---

## 0. Yetki modeli (her oturumun ilk kuralı)

- **Oturum, kurucu adına karar ALIR** — projenin vizyonu (00-AILE-MIMARISI §1.1: tavansız) ve kapsamı dahilindeki tüm ürün/teknik/sıralama kararları oturumda verilir, gerekçesiyle DEFTER'e yazılır. Kurucuya soru biriktirmek değil, karar + gerekçe üretmek esastır.
- **Kurucu-kapılı istisnalar (değişmez):** remote push / main'e merge (feat/* dalına YEREL commit serbest — §2.6 gece politikası) · para harcama (domain, SDK lisansı, TTS API, cihaz alımı, reklam bütçesi) · store submission/promote · fiyatın NİHAİ ilanı (öneri oturumda hazırlanır) · hukuki taahhüt (ToS/Privacy yayını) · D1/D2/D3/C-V0 kapı SONUÇLARININ onayı (kapı ölçümü oturumda yapılır; eşiği NET geçen sonuçta "şartlı geçti" ile ilerlenebilir — §2.6, kurucu onayı sabah retrospektif).
- **Dil:** ürün (UI, içerik, sesli koç, store metni) TAMAMEN İNGİLİZCE. Çeviri katmanı (i18n anahtarları) baştan kurulur ama V1 yalnız `en`. İç dokümanlar Türkçe.

## 1. Faz-kapı haritası (G0→G10)

| Faz | Adı | Çıktı | Kapı kanıtı (geçmeden sonrakine başlanmaz) |
|---|---|---|---|
| **G0** | Derin araştırma & bilgi kütüphanesi | `docs/research/` altında: rakip teardown, domain bilimi, müfredat kaynakları, hata taksonomisi, veri seti envanteri | Her iddia URL'li; rakip listesi canlı store taramasıyla doğrulanmış; müfredat kütüphanesi uzman-kaynaklara dayalı |
| **G1** | V0 fizibilite kapısı (app'e özgü D-kapısı) | Gerçek kayıtlarla ölçüm raporu | Kayıtlı videolar + landmark güven metrikleri + eşik kararı; **kurucuya sunulur** |
| **G2** | PRD + teknik tasarım | `docs/PRD.md` + mimari karar kayıtları (ADR) | PRD, plan+roadmap+araştırmayla tutarlı; ADR'ler 00-AILE-MIMARISI'yla çelişmiyor |
| **G3** | Veri & fixture kütüphanesi | Kayıt protokolü + etiketli landmark JSON fixture seti + replay harness | Her hedef teknik için ≥1 doğru + ≥2 hatalı fixture; harness CI'da yeşil |
| **G4** | Motor (engine) inşası | motion-core tüketimi + app state-machine'leri + versiyonlu rule-set | TÜM motor kodu fixture-replay testli; UI'sız çalışan analiz CLI/test çıktısı |
| **G5** | İskelet uygulama (alpha) | Tüm akışlar çalışır, cilasız UI; İngilizce | Simülatör/gerçek cihazda uçtan uca akış videosu/ekran görüntüleri; ölü buton = 0 |
| **G6** | İçerik üretimi | Müfredat (ders/drill/progresyon), sesli koç repliği seti, TTS/ses varlıkları | İçerik motoru versiyonlu config'te; uzman-doğrulama ihtiyaç listesi çıkarılmış |
| **G7** | UI giydirme | Claude Design ile tasarım → uygulanmış tema/token sistemi | design-review-auditor + visual-polish-critic turu; dark/light + büyük font + taşma temiz |
| **G8** | Sertleştirme (beta) | Performans/ısı/pil ölçümü, cihaz matrisi, a11y, observability, analytics | fps/ısı ölçüm tablosu gerçek cihazlarda; crash raporlama canlı; accessibility-specialist turu |
| **G9** | Monetizasyon + uyum | Paywall/IAP (kurucu-onaylı fiyat), privacy/KVKK beyanları, store metadata | privacy-data-guardian + store-policy-officer turları; IAP sandbox kanıtı; Art.50 değerlendirmesi |
| **G10** | Pazarlama & lansman hazırlığı | ASO seti (başlık/anahtar kelime/ekran görüntüsü anlatısı), lansman planı, reklam kreatif brief'leri | marketing-aso-specialist + growth-marketing-strategist çıktıları; store sayfası taslağı tam; **submission kurucu tetiğiyle** |

**Fazlar %100 seri değildir:** G3↔G4 iteratiftir (fixture→motor→yeni fixture); G6 içerik üretimi G4-G5 ile paralel yürüyebilir. Ama hiçbir kapı KANITSIZ "geçti" sayılmaz — L-033 dersi: kapı zayıflığı sonradan pahalıya patlar.

## 2. Oturum ritmi ve loop protokolü

1. Her geliştirme oturumu **`/loop`** (dinamik) ile kendi kendini tempolar: LOOP.md = iş kuyruğu; her iterasyon: kuyruktan iş al → yap → DOĞRULA (kanıt) → PROGRESS.md'ye kanıtla yaz → kuyruğu güncelle → devam.
2. **Kanıt disiplini:** "yaptım" ≠ bitti. Bitti = test yeşil ÇIKTISI / ekran görüntüsü / ölçüm tablosu / dosya diff'i. Doğrulanamayan iş LOOP.md'de "doğrulama bekliyor" olarak kalır.
3. **Defter disiplini:** bulgular DEFTER.md'ye (P0 açıkken yeni kapsam yok); kararlar gerekçesiyle DEFTER'e; oturum kapanışında Obsidian devir notu (`/oturum-kapanisi` skill).
4. **Alt-ajan ekonomisi (bağlayıcı memory kuralı):** düşünme/sentez ana oturumda; fan-out alt-ajanlarına açıkça `model:'sonnet'` (+kritik doğrulamalara opus); keşif yasak, bağlam prompt'a gömülü; alt-ajanlara git-YAZMA yasağı; adversarial doğrulama ÖNCESİ iş dala commit'li olmalı (kurucudan commit onayı istenerek).
5. **Manuel işler sona:** oturum, kurucu eli gerektiren işleri (uzman doğrulaması, cihazla fixture çekimi, satın alma, submission) biriktirip oturum sonunda TEK listede sunar; akışı bunlar için durdurmaz.
6. **OTONOM GECE MODU (kurucu direktifi 2026-07-26):** kurucu ekran başında değilken oturum SORMADAN, kendi kararlarını alarak, projeyi uçtan uca üretmeye devam eder. Kurallar:
   - **Şartlı kapı geçişi:** kapı eşikleri ölçümden ÖNCE yazılır; sonuç eşiği NET geçiyorsa "ŞARTLI GEÇTİ" ilan edilir (kanıt DEFTER'e), ilerlenir — kurucu onayı sabah retrospektif. Sınırda/altında sonuçta o hatta üretim koduna girilmez; kapıya bağımlı olmayan işler öne çekilir. Boşta kalmak yasak, kapı-atlamak da yasak.
   - **Git gece politikası:** iş feat/* dalında YEREL commit'lenir (adversarial doğrulama öncesi zaten zorunlu; feat dalı deploy tetiklemez); remote push / main'e merge SABAH kurucu onayıyla. Harcama, submission, nihai fiyat, D3 derin-yatırım kararı gece de kurucu-kapılıdır — bekleyen-onay listesine yazılır, geçilir.
   - **Token ekonomisi + PMI:** iş, proje-yönetim disipliniyle kırılır (WBS/iş kırılımı, bağımlılık sırası, kilometre taşı=G-kapıları, risk kaydı=DEFTER). Oturum, gerektiğinde projeye özel OPTIMUM alt-ajan tanımları (.claude/agents/; açıkça model:'sonnet', dar bağlam, keşif yasak, git-yazma yasağı) ve Workflow script'leri OLUŞTURABİLİR; yeni ajan/skill kurulunca AGENTS.md + registry sessizce güncellenir. Düşünme/sentez ana oturumda kalır.
   - **İleriye dönük mimari:** her karar, ürünün ileride kapsamlı/büyük olacağı varsayımıyla alınır — darboğaz üretecek kısayol yasak: versiyonlu şema/config, içerik=paket (kod değil), alan-bağımsız motorlar (beceri/branş/enstrüman/stil-bağımsız), i18n-hazır katman, genel parçalar motion-core'a.
   - **DEFTER yöntemi zorunlu:** /loop iterasyonları doğrulanmış-test edilmiş-gerçek bilgiyle ilerler; bulgular DEFTER formatında (ID+şiddet+kanıt; P0 açıkken yeni kapsam yok; kapanış kanıtı zorunlu); sabah kapanışında /oturum-kapanisi + gece kararlarının özeti + bekleyen-kurucu listesi.

## 3. Rol → ajan eşlemesi (RACI'nin solo-stüdyo hali)

| Büyük-şirket rolü | Bu ailede | Ne zaman |
|---|---|---|
| Ürün müdürü + mimar | **Ana oturum (Fable, yüksek effort)** | PRD, mimari, sentez, kapı kararları |
| CV/ML uzmanı | `motion-cv-engineer` | Model seçimi, V0 kapıları, fps/normalizasyon, fixture tasarımı |
| Spor bilimci | `movement-science-advisor` | Kural-seti/eşik/progresyon fizyolojik denetimi; uzman-öncesi ilk geçiş |
| Oyunlaştırma tasarımcısı | `game-design-architect` + `behavioral-insight-analyst` | Progresyon/retention döngüleri, skor psikolojisi |
| Performans mühendisi | `game-tech-engineer` + `mobile-platform-engineer` | fps bütçesi, ısı/pil, arka plan/izin |
| UX → UI | `uiux-designer` (akış) → **Claude Design** (görsel) → `design-systems-architect` (token) | G5 akış, G7 giydirme |
| QA | `qa-test-engineer` + `mobile-runtime-tester` + `flutter-reviewer` | G4 sonrası her faz; runtime sweep G5/G8 |
| Güvenlik/gizlilik | `security-compliance-auditor` + `privacy-data-guardian` | G8-G9 |
| Store uyum | `store-policy-officer` | G9; submission öncesi zorunlu |
| Pazarlama | `marketing-aso-specialist` + `growth-marketing-strategist` + `brand-identity-designer` | G10 (+G0'da konumlandırma girdisi) |
| Fiyatlama | `pricing-monetization-strategist` | G9 (öneri; nihai fiyat kurucu) |
| Ses/TTS | `comms-infra-engineer` (ses oturumu yönetimi) + `ai-integration-architect` (TTS hattı) | G6 |
| Release | `release-devops-engineer` | CI, signing, build hattı (LifeOS/BF reçeteleri devralınır) |
| Ostinato özel | `audio-dsp` danışmanı (başlarken yaratılacak — önce-katalog) | Ostinato G1+ |

## 4. Model & effort yönlendirme politikası

| İş sınıfı | Model | Effort | Not |
|---|---|---|---|
| Yol haritası/mimari/PRD/kapı analizi/sentez | **Fable (ana oturum)** | high | ultracode açık; Workflow fan-out serbest |
| Motor kodu (state machine, kural, test) | Fable ana oturum + `sonnet` alt-ajan fan-out | main high / sub default | TDD; fixture önce |
| Mekanik işler (l10n anahtarı, boilerplate, asset) | `sonnet` alt-ajan | low-medium | betikli kontrol > LLM-denetim |
| Riskli sınıf (IAP/para, güvenlik, store submission, dürüstlük-metrikleri) | Fable yönetir + **Opus bağımsız doğrular** | high | holding sert kuralı |
| Web araştırması fan-out | `sonnet` + WebSearch | medium | sentez ana oturumda |
| UI görsel tasarım | **Claude Design** (oturum dışı) | — | iskelet → giydirme sırası |

## 5. Ölçüm dürüstlüğü + pazarlanabilirlik standardı

- Pazarlanan HER sayı (doğruluk, gelişim yüzdesi) 00-AILE-MIMARISI §7'ye tabidir: zaman-doğru, out-of-sample, koşullarıyla etiketli.
- "Pazarlamaya hazır ürün" tanımı: G10 kapısından geçmiş = store sayfası tam + ekran görüntüsü seti + ASO metinleri + lansman planı + reklam kreatif brief'i + çalışan paywall + kanıtlı çekirdek deneyim. Yarım özellik gizlenmez, kapsamdan çıkarılır (dürüstlük > vitrin).

## 6. Değişiklik yönetimi

Bu sürece istisna gerektiğinde: istisna + gerekçe app DEFTER'ine yazılır; aile-genelini etkiliyorsa motion-core DEFTER'ine (M-serisi) taşınır ve bu dosya güncellenir (`guncelleme` tarihi + değişiklik notu).
