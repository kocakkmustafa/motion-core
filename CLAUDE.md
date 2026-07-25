# CLAUDE.md — yula-motion (monorepo)

## 🔒 KOD BAŞLATMA KİLİDİ
Kurucu "**<app>'e başlayalım**" demeden bu repoda üretim kodu YAZILMAZ. O güne kadar yalnız docs/ yaşar.
Başlama anında ilk iş: `docs/00-AILE-MIMARISI.md` OKU (bağlayıcı: D1-D4 düzeltmeleri + V0 kapıları) → ilgili `docs/<app>-plan.md` OKU → V0 fizibilite kapısını koş (Gravita: ters-duruş landmark testi · JabLab: fps/blur ölçümü · Lissom: test seti güvenilirliği · Ostinato: veri protokolü) → sonra plan.

## Yapı (kod başlayınca)
Flutter + melos: `packages/motion_core` (ortak çekirdek — kalibrasyon, pose bridge, güven kapısı, state-machine çatısı, rule-engine, replay-harness) + `apps/{gravita,lissom,jablab,ostinato}`. Çekirdeğe app-özel mantık SIZMAZ; app'lere çekirdek kopyası GİRMEZ.

## Sert kurallar (4 planın ortak sözleşmesi)
- Gerçek-zamanlı karar zincirinde LLM YOK. Ham video varsayılan cihazda. Yüz tanıma YOK.
- Düşük landmark-güveninde teknik hüküm ÜRETME ("analiz edemedim" de).
- Kuralları koda gömme: versiyonlu rule-set config. Her skor bileşeni açıklanabilir.
- Replay/fixture testleri olmadan yeni teknik ekleme. Tıbbi/sağlık iddiası dili YASAK (wellness).
- Danışmanlar: `motion-cv-engineer` (pose/CV) + `movement-science-advisor` (biyomekanik/progresyon) + submit öncesi `privacy-data-guardian` + `store-policy-officer`.

## Bağlam zinciri
`../VENTURE.md` → `../workspace/{PLAN,PROGRESS,DEFTER}.md` → bu dosya → docs/.
