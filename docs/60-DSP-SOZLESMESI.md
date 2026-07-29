# DSP Sözleşmesi — Ses/Sinyal Analiz Parametreleri (aile-geneli)

Kaynak: Ostinato audiofix-1 ilk-gün bulguları (M-O-21..24, tur 25) + L-069
emsali. Bu doküman motion-core'un ritim/ses modüllerine VE app-side her
sinyal-analiz koduna bağlayıcıdır.

## 1. Birim kuralı — parametreler SÜRE/FREKANS cinsinden, örnek cinsinden ASLA

Örnek (sample) cinsinden sabitlenen her analiz parametresi **sessizce cihaza
bağımlıdır**: 2048-örneklik pencere 44,1 kHz'de ~46 ms, 48 kHz'de ~43 ms'dir
ve fark bir çello ifadesinde 3 notaya 17 hayalet onset üretecek kadar
büyüktür (ölçüldü, M-O-23). Aynı sınıfın poz düzlemi karşılığı kare-cinsinden
pencere/histerezisdir (30 fps varsayımı) — faz-config delta'larının SANİYE
cinsine mühürlenmesinin nedeni buydu (L-069).

- Pencere/hop/histerezis: **ms** (koşumda örneğe çevrilir: `n = rate * ms/1000`).
- Bant/bin hedefleri: **Hz**.
- Kare-pencereleri: **saniye** (koşumda kare sayısına çevrilir: `n = fps * s`).

## 2. İki-hız zorunluluğu

Sinyal-analiz fixture'ları **en az iki örnekleme hızında** (44,1 + 48 kHz;
poz için en az iki fps'te) koşulmadan yeşil sayılmaz. Tek-hız test, birim
kuralı ihlalini yapısal olarak GÖREMEZ — "bende çalışıyor, cihazların
yarısında bozuk" tam bu boşluktan çıkar.

## 3. Çözünürlük ve bant genişliği AYRI düğmelerdir

Sabit bin-sayılı bir dönüşümde çerçeve boyu hem frekans çözünürlüğünü hem
analiz bandını belirler. Tek düğme sanılırsa "düzeltme" kusuru registerin
öbür ucuna taşır (frame=4096: bastaki hayaletler sıfırlandı, tiz dizi 5→0
kayboldu — ölçüldü). Tasarımda ikisi bağımsız beyan edilir.

## 4. Zaman damgası penceren ortasını temsil eder

STFT karesinden türeyen her olay damgası pencere-ortası düzeltmesi almadan
kullanılamaz; alınmazsa her onset ~yarım pencere erken damgalanır ve üstüne
kurulan her ritim hükmüne sistematik sapma olarak geçer. Bu sapma bir başka
kusur (hayalet onset gürültüsü) tarafından maskelenebilir — kusurlar
teker teker susturularak aranır.

## 5. Motor limiti eşikle gizlenmez, zarf olarak İLAN edilir

Çalışma zarfı çok-tohum × çok-SNR süpürmesiyle ölçülür ve deklare edilir
(ör. onset: 20 dB'de 0 hayalet · 10 dB'de ≤1/3 sn · 5 dB'de 1-6). Tek
fixture'da 0 çıkana kadar eşik oynatmak fixture'a overfit'tir. Ürün kuralı:
Setup Check ortamın zarf içinde olduğunu doğrular (ör. ~10 dB SNR tabanı),
dışındaysa kullanıcıya dürüstçe "bu ortamda güvenilir ölçemem" der —
sessizce hayalet pencere üretmek yasak.

## 6. Kaskad sınaması — motorlar tek tek doğru, zincir yanlış olabilir

Her motoru tek başına doğrulayan test, bir motorun komşusunu zehirlediği
kaskadı göremez (O-019: perde motoru kusursuz, onset dedektörü çelloyu
63 pencerede 1 kullanılabilire düşürdü). Fixture'lar GERÇEK motor
zincirinden geçirilir; beklenen değerler motorun ölçtüğünden yazılır,
elle uydurulmaz — ve üretici kapısı oran-bazlıdır (`judged > 0` değil).

## 7. Dördüncü canlılık sorusu: "bu kapı hiç kırmızı yanabilir mi?"

M-F-56 üç-katman canlılık denetimine (motor var → ad sözlükte → faz
ateşleniyor) dördüncü katman: **kapı-yanlışlanabilirliği.** Hem pozitif hem
negatif malzemede aynı hükmü veren koşul (çalarken de sessizlikte de
ateşlenen faz; hiçbir girdiyle reddetmeyen kapı) yazılmış ama görev
görmüyordur — replay araçları bunu ⚠️ sınıfı olarak ayrıca raporlar.
