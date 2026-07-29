# Referans Tüketim Sözleşmesi (aile-geneli, M-F-46)

**Tarih:** 2026-07-29 · **Statü:** Bağlayıcı — `CanonicalReference` üreten/tüketen
her app bu kurallara uyar. Kaynak: JabLab ürün-bağlama kuralları (stance,
`a0483c8`, 6 değişmez testli) + Choreia tüketim kuralları (Running Man,
`0fdcf6c`, 6 okuma kuralı) — iki app AYNI sözleşmeyi bağımsız yazdı; bu
doküman yakınsamanın kanonik hali. App-side testler buraya atıf verir;
değişiklik = M-talebi + koordinatör kararı.

> Bir referans artefaktı VERİ değil HÜKÜM-YETKİSİ taşır: hangi eklemin
> skorlanabileceğini ölçümle söyler. Maskesini yok sayan tüketici, doğru
> hareket edeni yanlış sayar — üretilen her şey boşa gider.

## 1. Skorlama yetkisi ÖLÇÜMDEN gelir (M-F-41)

1. **Skorlanan eklem = ölçülen eğitmen-dispersiyonu muhafazakâr tabanda
   (≤14°) kalan eklem.** Anatomik sezgi ("bacaklar skorlanır") yetki VERMEZ —
   JabLab ölçtü: öncü kalça 27° ayrışırken arka omuz 13°'de uyuşuyor.
2. **Serbest bant, ölçülen ayrışmanın ALTINA inemez** — antrenörlerin kendi
   arasındaki farkı kullanıcının hatası saymak yasak. Artefakt bu değişmezi
   kendi içinde raporlar; tüketici testle zorlar.
3. **Dispersiyonu tavanda/geniş eklem `coached_only`:** gösterilir,
   söylenir, PUANLANMAZ. Kullanıcıya NEDENİ açıklanır (JabLab kopyası:
   "Experienced instructors disagree about these, so we point them out but
   do not grade them") — açıklamasız puan-yokluğu "sistem bozuk" okunur.

## 2. Faz/kapsam maskeleri (Choreia kuralları)

4. **`scoredPhases=false` fazda hüküm verilmez.** Geniş bant koyup skorlamak
   yetmez: o fazda eğitmenler uyuşmuyor, "doğru" diye bir şey ölçülmedi.
   (Şema karşılığı: `checkpoint` fazı — D3.)
5. **Hiçbir eklemin tüm çevrimde skorlanmaması EKSİKLİK değildir.**
   `coverage` veri-kalitesi göstergesi gibi okunmaz — hareket fazlıdır; aynı
   eklem duruşta sıkı, geçişte serbesttir (Running Man: bantlar tam tekme
   anlarında geniş — ölçüm kusuru değil, adımın özelliği).

## 3. Provisional ve belirsizlik işaretleri

6. **`provisional` referans kesin-hüküm veremez** ("ustalaştın" sınıfı yok);
   tolerans muhafazakâr yazılır ve `contributingTakes < 5` iddialı bir test
   yeniden-hesap gününü kendisi hatırlatır (JabLab deseni, M-F-38).
7. **Düşük ayna-marjlı take'in yön kaydı kesin değildir** — o take'ten türeyen
   taraf-bağımlı hüküm verilmez (M-C-15/M-J-06 hattı).
8. `provisional` İSTATİSTİKSEL zayıflığı işaretler; SİSTEMATİK yanlılığı
   işaretlemez — kaynak-uygunluk (M-F-43 romMode) referans KURULMADAN çözülür,
   provisional'a devredilemez.

## 4. Ürün yüzeyi

9. Seans özeti `coached_only` başlıkları AYRI gösterir ve nedenini söyler;
   skor yalnız skorlanan eklemlerden akar.
10. Sesli koç replikleri ölçülmeyen şeyi İDDİA EDEMEZ (JabLab G6 değişmezi:
    `power`/`force`/`kph` replikte geçemez) — dürüstlük kuralının ürünün
    ağzındaki karşılığı.

## 5. Uygulama notu

Her app, tüketicisinde bu kuralların testlerini taşır (JabLab 6-değişmez +
Choreia okuma-kuralları desenleri). Çekirdek `CanonicalReference` API'si
maske/işaret alanlarını taşır; evaluator geldiğinde 1/4/6 numaralı kurallar
çekirdekte de zorlanacak (koordinatör kuyruğu).
