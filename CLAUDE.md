# CLAUDE.md — motion-core

## 🔒 KOD KİLİDİ
Çekirdek kod, İLK app'in kurucu tetiğiyle birlikte yazılır ("<app>'e başlayalım"). O güne kadar yalnız docs/.

## Sözleşme
- `docs/00-AILE-MIMARISI.md` = 4 ürün için BAĞLAYICI (kapsam direktifi §1.1 dahil: sesli antrenör-vaadi çekirdek; V1 = sıra, tavan değil).
- Bu repo YALNIZ enstrüman/beceri-bağımsız altyapı taşır: app'e özgü kural/progresyon/içerik app reposuna gider; buraya app mantığı SIZMAZ.
- Sürümleme: semver + CHANGELOG; app'ler pinli sürüm tüketir (pub git-dependency, tag'li). Breaking değişiklik = 4 app'in DEFTER'ine kayıt + kurucu haberi.
- Test: her modül replay/fixture ile; app'lerden bağımsız yeşil kalır.

## Danışmanlar
`motion-cv-engineer` (birincil) · `movement-science-advisor` · fps bütçeleri: `game-tech-engineer`.

## Bağlam zinciri
`../VENTURE.md` → `../workspace/` (aile koordinasyon defterleri) → bu dosya → docs/.
