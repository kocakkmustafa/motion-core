# Faz-Config v3 — LISSOM ONAYI (+ iki ifade boşluğu)

**Taslak:** motion-core `docs/40-FAZ-CONFIG-SEMASI-TASLAK.md` @ `f82d288` (M-F-37)
**Tarih:** 2026-07-29 · **Hüküm: ONAYLANDI — mühürlenebilir.**

Aşağıdaki iki kalem mührü bloke etmez; ikisi de **ek alan**, hiçbir mevcut yapıyı değiştirmiyor. Ama ikisi de bu gece Lissom'da **canlı kusur** olarak ortaya çıktığı için kayda geçiyor: şemanın ifade edemediği şey, sessizce ifade edilmemiş kalıyor.

## 1. v2 talebim karşılandı

`perSide`/`{side}` istemiştim; v3 bunu daha iyi bir mekanizmayla veriyor: `limb` (soyut zincir adı) + `sideResolution: visible|calibrated|explicit`. Konumsal değil **semantik** bağlama, ve ADR-001'imizle (taraf kimliği geometrik kurulur, model etiketinden okunmaz) doğal olarak örtüşüyor. `{side}` yer tutucusundan vazgeçiyorum.

## 2. BOŞLUK A — `limb` tekil; karşı-taraf zincirine atıf yapılamıyor

**Somut vaka:** `active_straight_leg_raise`. Ölçülen büyüklük kaldırılan bacağın kalça fleksiyonu; **geçerlilik ölçütü ise KARŞI bacağın yerde kalması.**

```
primaryMetric: hip_flexion_{side}        → limb: raised_leg
guardMetrics:  knee_flexion_{side}       → limb: raised_leg
               hip_flexion_{opposite}    → ??? ikinci zincir, v3'te adı yok
invalidation:  hip_flexion_{opposite} < 170 → OPPOSITE_LEG_LIFTED
```

v3'te `limb?` teknik düzeyinde **tekil**. Bir teknik ikinci bir zincire atıf yapamıyor, ve şemada bir metriğin `limb`'e NASIL bağlandığı da gösterilmemiş.

**Neden kozmetik değil:** bu guard olmadan ASLR ölçüm değil, yalnızca "kalçanı ne kadar kırabiliyorsun" olur — kullanıcı karşı bacağını da kaldırarak istediği skoru alır. Test bu gece tam bu yüzden kırıktı: `{opposite}` hiçbir yerde çözülmüyordu, yani guard **asla ateşlenemezdi** (L-081, L-072 ile aynı ölü-guard sınıfı). Şema tekil `limb` ile mühürlenirse aynı ifade boşluğu çekirdek seviyesine taşınır.

**Öneri (asgari):** zincir adları teknik düzeyinde çoğul, metrik atıfları adla nitelenir.

```
limbs: { primary: "raised_leg", contralateral: "support_leg" }
guardMetrics: [ { metric: "hip_flexion", limb: "contralateral", ... } ]
```

Ölçek dürüstlüğü: Lissom'un 12 testinin **yalnız 1'i** bunu istiyor. Ama Gravita'nın tek-taraflı hareketlerinde ve JabLab'ın duruş kontrolünde (arka el nerede) aynı şeklin çıkmasını beklerim — tek-app ihtiyacı diye bakmayın.

## 3. BOŞLUK B — zorunlu metrik sözlüğü geometrik-olmayan ölçülere oturmuyor

v3 §2 her metrikten `unit, range, noiseBand, baseline` istiyor. Lissom'un bataryası altı **geometrik olmayan** büyüklüğe atıf yapıyor:

| ölçü | birim | kaynak | kadraj ihtiyacı |
|---|---|---|---|
| `hold_duration` | s | faz makinesi | — |
| `supportContact` | bool | faz makinesi | 2 landmark |
| `footTouchdown` | bool | faz makinesi | 4 landmark |
| `confidence` | ratio | kare | — |
| `heelRiseDelta` | ratio | kare | 4 landmark |
| `yawDeg` | deg | kare | 4 landmark |

Boolean bir büyüklüğün `range`'i ve `noiseBand`'i yok; süre metriğinin `baseline`'ı yok. Bunlar zorunlu alanlarla ifade edilemedikleri için **hiçbir yere yazılmamışlardı** — ve yazılmadıkları için hiçbir doğrulayıcı onlara bakmıyordu. Bataryanın metrik referansları bu yüzden **tamamen doğrulanmamıştı**; `{opposite}` kusurunu gizleyen boşluk buydu.

**İkinci nokta, kendi düzeltmemden çıktı:** geometrik olmayan bir ölçü de **kadraj ister**. `footTouchdown` ayağı görmeden ayak inişini saptayamaz. Beyanı `requiredLandmarks`'sız yaptığımda triyaj `single_leg_balance` için ayak bileği aramayı bıraktı — düzeltmenin kendisi yeni bir sessiz boşluk açtı. v3'ün `requires:{landmarks,signals}` alanı teknik/faz düzeyinde; **ölçü düzeyinde** karşılığı yok.

**Öneri:** ayrı bir `derivedMeasures` bloğu — `{unit, source: phase|frame|signal, requiredLandmarks[], description}`; `range/noiseBand/baseline` bu blokta ZORUNLU DEĞİL. Lissom'da uygulandı ve CI değişmezi kuruldu (bataryanın andığı her ad ya metrik ya beyan olmak zorunda).

## 4. Benimsenenler (itiraz yok)

`priority: safety|blocking|quality` — aynı anda ateşlenen hatada güvenliğin önce söylenmesi bizde de gerekiyor (BENT_ELBOW ile LOW_CONFIDENCE aynı karede ateşlenebiliyor). · `perturbation` ve değişmez #11 — sentetik senaryo üretecimizin tam olarak kaçırdığı sınıf; toleransın içinde kalan fixture hiçbir şey sınamıyor. · `quality` ↔ hata-katmanı ayrımı · ölü-metrik yasağı (#10) — L-011'de bağımsız olarak aynı sonuca varmıştık (`angle_vertical`+`transverse` her yaw'da tam 90° dönüyordu). · `localMin`/`flag`/`category` · `checkpoint`.

## 5. Göç

`mocore/phases.py` taslak köprüsü, çekirdek yorumlayıcı çıkınca silinir. Lissom'un çevirici maliyeti: 12 test + 19 metrik. Metriklerimiz `points: [RIGHT_HIP, RIGHT_SHOULDER, ...]` yazıyor — M-F-06'nın "config'te LEFT_*/RIGHT_* YASAK" kuralı landmark adlarını da kapsıyorsa çevirici bunları soyut zincire çevirmek zorunda. **Kapsamı netleştirin:** kural yalnız teknik düzeyindeki `limb` adlandırmasını mı bağlıyor, yoksa metrik `points`'lerini de mi? İkincisiyse göç maliyetimiz 19 metriğin tamamı.
