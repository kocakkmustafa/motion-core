# MOTIONSKILL — HANDSTAND VE VÜCUT BECERİLERİ KOÇU
## Claude Code için Ana Proje Tanımı

> Bu belge, MotionSkill ürününün hedefini, ürün sınırlarını, teknik yaklaşımını, kullanıcı deneyimini, veri modelini, risklerini ve geliştirme önceliklerini tanımlar. Claude Code bu belgeyi ürünün ana bağlamı olarak kullanmalı; burada belirtilen V1 sınırlarını izinsiz genişletmemeli ve mimari kararları açıklanabilir, test edilebilir ve cihaz üzerinde çalışabilir olacak şekilde vermelidir.

---

## 1. Projenin özeti

MotionSkill, tek bir telefon kamerası kullanarak kullanıcının handstand ve temel calisthenics becerilerini öğrenmesini, denemesini, ölçmesini ve geliştirmesini sağlayan mobil öncelikli bir fiziksel beceri eğitim platformudur.

Ürün genel fitness uygulaması değildir. Ana değer önerisi kullanıcının “bir antrenmanı tamamlaması” değil, gözle görülür ve ölçülebilir fiziksel beceriler kazanmasıdır.

İlk ürün vaadi:

> Telefonunu sabitle, seçtiğin beceriyi dene, sistem vücut hizanı ve denemeni analiz etsin, en önemli hatanı söylesin ve bir sonraki doğru çalışmayı önersin.

Ürün tek kişiyle, ekipmansız veya yalnızca duvar/mat gibi standart çevre desteğiyle çalışmalıdır. V1’de barfiks demiri, paralette, halka, ağırlık veya özel sensör zorunlu olmamalıdır.

---

## 2. Hedef kullanıcılar

### Birincil kullanıcılar

- Handstand öğrenmek isteyen başlangıç ve orta seviye kullanıcılar
- Evde calisthenics becerisi geliştiren kişiler
- Yoga/calisthenics arasında beceri odaklı çalışan kullanıcılar
- Sosyal medyada beceri ilerlemesini paylaşmak isteyen genç yetişkinler
- Spor salonuna gitmeden sistemli ilerlemek isteyen kullanıcılar

### İkincil kullanıcılar

- Calisthenics koçları ve öğrencileri
- Dansçılar, dövüşçüler ve jimnastik temelleri geliştirmek isteyen sporcular
- Mobilite ve denge çalışması yapan kullanıcılar
- İçerik üreticileri

### V1’de hedeflenmeyen kullanıcılar

- Profesyonel artistik jimnastik sporcuları
- Sakatlık rehabilitasyonu arayan kişiler
- Çocuklar için gözetimsiz ileri seviye akrobatik eğitim
- Tıbbi değerlendirme bekleyen kullanıcılar
- Düşme riski yüksek yaşlı kullanıcılar

---

## 3. Ürünün ana hedefleri

1. Kullanıcının beceri seviyesini standartlaştırılmış kamera testleriyle ölçmek.
2. Denemeler sırasında vücut hizası, süre, denge kaybı ve teknik aşamaları analiz etmek.
3. Kullanıcıya aynı anda yalnızca en önemli ve uygulanabilir düzeltmeyi vermek.
4. Kullanıcının beceri seviyesine göre doğru progresyonu seçmek.
5. Gelişimi günler ve haftalar boyunca ölçülebilir hâle getirmek.
6. Ham videoyu varsayılan olarak cihazdan çıkarmamak.
7. İnternet olmadan temel antrenman ve analiz akışını çalıştırmak.
8. İçerikten çok ölçülebilir ilerlemeyi ürünün merkezine koymak.

---

## 4. V1 kapsamı

### V1 ana becerisi

V1’in merkezinde handstand olmalıdır. Diğer beceriler ürün mimarisinde tanımlanabilir ancak ilk sürümde yalnızca sınırlı kapsamla açılmalıdır.

### V1 desteklenen beceriler

1. Duvara yüz dönük handstand
2. Duvara sırt dönük handstand
3. Serbest handstand denemesi
4. Crow pose / frog stand
5. Headstand temel tutuş
6. Hollow body hold
7. Arch body hold
8. Pistol squat hazırlığı
9. L-sit hazırlığı
10. Omuz ve bilek hazırlık testleri

### V1 dışı

- Backflip, frontflip ve yüksek riskli akrobatik hareketler
- Planche, front lever, back lever gibi ileri yük becerileri
- Rings, paralette veya bar odaklı hareketler
- İnsan koçun yerini tamamen aldığı iddiası
- Sakatlık teşhisi
- Kullanıcının düşüşünü güvenli biçimde engelleme iddiası
- Çoklu kişi takibi
- Giyilebilir sensör
- LLM tabanlı gerçek zamanlı koçluk
- Sosyal ağ
- Kullanıcıların birbirine puan vermesi
- Canlı yarışma
- Koç pazaryeri

---

## 5. Kullanıcı deneyimi

### 5.1 Onboarding

Onboarding şu bilgileri toplamalıdır:

- Yaş aralığı
- Boy ve yaklaşık kilo
- Deneyim seviyesi
- Hedef beceri
- Haftalık çalışma sıklığı
- Bilek, omuz veya belde mevcut ağrı olup olmadığı
- Kullanıcının duvar ve güvenli zemin erişimi
- Baskın taraf
- Kamera cihazı ve işletim sistemi

Ağrı veya ciddi hareket kısıtlılığı bildiren kullanıcıya ürünün tıbbi değerlendirme sunmadığı açıkça belirtilmelidir.

### 5.2 Kamera kurulum sihirbazı

Sistem antrenman öncesinde şunları doğrulamalıdır:

- Tek kişi görünmesi
- Baş, eller ve ayakların kadrajda kalması
- Kamera yüksekliği
- Kamera mesafesi
- Yeterli ışık
- Zeminin uygun olması
- Arkada kırılabilir eşya bulunmaması
- Duvar kullanılacaksa duvarın kadrajda ve erişilebilir olması

Kalibrasyon geçmeden analiz başlamamalıdır.

### 5.3 Başlangıç değerlendirmesi

İlk değerlendirme:

- Omuz fleksiyon testi
- Bilek hareket açıklığı hakkında basit fonksiyonel test
- Hollow hold
- Plank
- Duvar handstand giriş denemesi
- Crow pose tutuş
- Tek ayak denge

Bu değerlendirme tıbbi ölçüm olarak sunulmamalıdır. Yalnızca uygulama içi başlangıç seviyesi belirlemek için kullanılmalıdır.

### 5.4 Antrenman akışı

Her beceri oturumu şu sırayı izlemelidir:

1. Güvenlik hatırlatması
2. Kısa hazırlık
3. Hareketin görsel anlatımı
4. Birinci deneme
5. Otomatik analiz
6. Tek ana hata
7. Düzeltici drill
8. Yeniden deneme
9. Deneme karşılaştırması
10. Seans özeti

---

## 6. Teknik mimari

### 6.1 Temel ilke

Gerçek zamanlı analiz LLM ile yapılmamalıdır.

Önerilen zincir:

```text
Kamera akışı
→ Pose Landmarker
→ Landmark güven filtresi
→ Temporal smoothing
→ Vücut oranı normalizasyonu
→ Beceri durum makinesi
→ Kural motoru
→ Skor ve hata önceliklendirme
→ Sesli/görsel geri bildirim
→ Yerel seans kaydı
```

### 6.2 İstemci

Önerilen teknoloji:

- Flutter kullanıcı arayüzü
- Android tarafında Kotlin yerel kamera/MediaPipe katmanı
- iOS tarafında Swift yerel kamera/MediaPipe katmanı
- Type-safe platform bridge
- Yerel SQLite/Drift veya Isar benzeri depolama
- Cihaz içi text-to-speech veya önceden kaydedilmiş sesler

### 6.3 Pose modeli

Başlangıç için MediaPipe Pose Landmarker önerilir.

Gerekli veriler:

- 33 landmark
- x, y, z koordinatları
- visibility/presence güveni
- frame timestamp
- orientation
- inferred body side

Pose modeli yalnızca algılama yapar. Beceri değerlendirmesi uygulamanın kendi deterministik koduyla yapılmalıdır.

### 6.4 Performans

Hedefler:

- Desteklenen cihazlarda en az 20 FPS analiz
- Tercihen 24–30 FPS
- Görsel geri bildirim gecikmesi 150 ms altında
- Sesli geri bildirim için toplam karar gecikmesi 500 ms altında
- Uzun oturumlarda cihaz ısısı ve pil tüketimi izlenmeli
- Model giriş çözünürlüğü cihaz performansına göre adaptif olmalı

---

## 7. Beceri motoru

### 7.1 Beceri durumu örneği: serbest handstand

```text
IDLE
→ PREPARING
→ KICK_UP_STARTED
→ INVERSION_ENTERED
→ HOLDING
→ BALANCE_LOST
→ EXITING
→ COMPLETED
```

Her geçiş landmark ilişkileri ve zaman eşikleri ile tanımlanmalıdır.

### 7.2 Ölçümler

- Ters pozisyonda kalma süresi
- Omuz-kalça-ayak hizası
- Dirsek bükülmesi
- Omuz açısı
- Bel çukuru
- Kalça pik açısı
- Bacak açıklığı
- Diz bükülmesi
- Baş pozisyonu
- Denge kaybı yönü
- Kontrollü çıkış
- Kick-up aşırı veya yetersizliği
- Başarılı/başarısız deneme oranı

### 7.3 Normalizasyon

Ham piksel değerleri kullanılmamalıdır.

Ölçümler şu referanslara normalize edilmelidir:

- Omuz genişliği
- Gövde uzunluğu
- Kalça genişliği
- Tahmini tam vücut uzunluğu
- Kamera perspektifi
- Kalibrasyon sırasında kaydedilen nötr duruş

### 7.4 Güven kapısı

Aşağıdaki durumlarda teknik hata üretilmemelidir:

- Kritik landmark güveni düşükse
- Vücut kadrajdan çıkmışsa
- Kamera hareket etmişse
- Kullanıcı hareketi tamamlamamışsa
- Kullanıcı ile duvar/zemin ilişkisi algılanamıyorsa
- Birden fazla kişi görünüyorsa
- Hareket modeli ilgili aşamaya güvenle geçemiyorsa

Bu durumda sistem “analiz edemedim” demeli, yanlış teknik hüküm vermemelidir.

---

## 8. Skorlama

Tek bir genel skor yanıltıcı olabilir. Skorlar ayrı gösterilmelidir:

- Hizalama
- Kontrol
- Tutuş süresi
- Giriş tekniği
- Çıkış kontrolü
- Tutarlılık
- Güvenilir analiz oranı

Örnek handstand skoru:

```text
Hizalama: %72
Kontrol: %61
Tutuş: 4.8 sn
Dirsek stabilitesi: %88
Bel hizası: %54
Analiz güveni: yüksek
```

“Profesyonel seviye”, “güvenli” veya “sakatlanmazsın” gibi sonuçlar üretilmemelidir.

---

## 9. Geri bildirim motoru

Kullanıcıya aynı anda en fazla bir teknik düzeltme verilmelidir.

Öncelik:

1. Güvenlik
2. Hareketi imkânsızlaştıran hata
3. Denge
4. Büyük hizalama hatası
5. Küçük form hatası
6. Performans optimizasyonu

Örnek geri bildirim:

- “Ellerini omuz genişliğinde tut.”
- “Dirseklerini kilitlemeden düzleştir.”
- “Kalçanı omuzlarının üzerine getir.”
- “Bacaklarını birleştirmeye çalışma; önce dengeyi koru.”
- “Kick-up kuvvetini biraz azalt.”
- “Duvara fazla uzak başladın.”

Aynı uyarı cooldown süresi olmadan tekrar edilmemelidir.

---

## 10. Progresyon sistemi

Beceriler bir skill graph olarak modellenmelidir.

Örnek handstand grafiği:

```text
Wrist Prep
→ Shoulder Flexion
→ Hollow Body
→ Wall Plank
→ Wall Walk
→ Chest-to-Wall Hold
→ Heel Pulls
→ Controlled Kick-Up
→ Freestanding Hold
→ Shape Refinement
```

Bir sonraki seviye sadece ders izlenerek açılmamalıdır. Ölçülebilir kriterler kullanılmalıdır.

Örnek:

- Chest-to-wall handstand 20 saniye
- Dirsek stabilitesi %80 üzeri
- 3 oturumda en az 2 başarılı deneme
- Ağrı bildirimi olmaması

Kriterler uzman içeriği olarak yapılandırılabilir olmalıdır.

---

## 11. Veri modeli

Temel varlıklar:

- UserProfile
- DeviceProfile
- Skill
- SkillProgression
- Lesson
- Drill
- CalibrationProfile
- PoseFrame
- Attempt
- AttemptMetric
- DetectedIssue
- FeedbackEvent
- Session
- SafetyEvent
- ModelVersion
- RuleSetVersion

Ham video varsayılan olarak kaydedilmemelidir.

Yerel olarak saklanabilecekler:

- Pose özetleri
- Deneme süreleri
- Skorlar
- Hata kodları
- Kalibrasyon
- Kullanıcı tercihleri
- Beceri ilerlemesi

Kullanıcı açık izin verirse performans videosu kaydedilebilir.

---

## 12. Güvenlik

Handstand ve calisthenics becerilerinde düşme riski vardır.

Zorunlu güvenlik kuralları:

- Güvenli zemin ve boş alan kontrolü
- Yeni başlayanlarda duvar destekli progresyon
- Ağrı varsa oturumu durdurma
- İleri becerileri kilitleme
- Boyun yükü içeren headstand hareketlerinde belirgin uyarı
- Kullanıcının yaşına ve seviyesine göre hareket sınırı
- Uygulamanın tıbbi veya profesyonel koç yerine geçmediğini açıklama
- Acı ile zorlanma arasındaki farkı kullanıcıya öğretme

Uygulama düşmeyi fiziksel olarak engelleyemez.

---

## 13. Test stratejisi

### Unit test

- Açı hesapları
- Normalizasyon
- State machine geçişleri
- Skor hesapları
- Feedback cooldown
- Güven eşikleri
- Progresyon açma koşulları

### Fixture test

Önceden kaydedilmiş landmark dizileri:

- Doğru handstand
- Aşırı bel çukuru
- Bükülü dirsek
- Yetersiz kick-up
- Aşırı kick-up
- Kadraj dışı
- Düşük güven
- Kamera hareketi

### Cihaz testi

- Düşük segment Android
- Orta segment Android
- Güncel iPhone
- Farklı ışık
- Farklı kıyafet
- Farklı vücut tipi
- Duvar renkleri
- Küçük oda

### İnsan doğrulaması

En az bir calisthenics/handstand uzmanı, kural setini ve geri bildirimleri doğrulamalıdır.

---

## 14. Başarı ölçütleri

V1 başarı göstergeleri:

- Kullanıcıların kalibrasyonu %90 oranında tamamlaması
- İlk denemeye geçiş süresinin kısa olması
- Analiz edilemeyen denemelerin izlenmesi
- Yanlış pozitif geri bildirim oranının düşük olması
- Kullanıcının aynı seans içinde ölçülebilir iyileşme görmesi
- 7 ve 30 günlük beceri devamlılığı
- Kullanıcının video paylaşma isteği
- İlk başarılı serbest handstand’a kadar geçen süre

---

## 15. Claude Code için çalışma kuralları

- V1 kapsamını izinsiz genişletme.
- Genel fitness uygulamasına dönüşme.
- LLM’yi gerçek zamanlı karar zincirine koyma.
- Sağlık teşhisi üretme.
- Ham videoyu varsayılan olarak buluta gönderme.
- Skoru açıklanamaz kara kutu hâline getirme.
- Önce veri sözleşmelerini ve test fixture’larını oluştur.
- Kamera/pose katmanını ürün motorundan ayır.
- Beceri kurallarını kod içine dağınık sabitler olarak gömme; yapılandırılabilir rule set kullan.
- Her teknik kararın neden verildiği loglanabilir olmalı.
- Desteklenmeyen durumda sessizce tahmin üretme.
- Her geliştirme aşamasında performans ve cihaz ısısını ölç.
- UI geliştirmeden önce analiz motorunun replay testleri çalışmalı.

---

## 16. V1 tamamlanma kriterleri

V1 ancak aşağıdakiler çalışıyorsa tamamlanmış sayılır:

- Tek kişi kamera kalibrasyonu
- Tam vücut pose takibi
- Handstand denemesi başlangıç/bitiş tanıma
- En az beş güvenilir teknik hata
- Tutuş süresi
- Hizalama skoru
- Denge kaybı yönü
- Oturum geçmişi
- En az bir tam progresyon yolu
- Düşük güven durumunda hata vermeme
- İnternetsiz temel çalışma
- Kamera görüntüsünün varsayılan olarak kaydedilmemesi
- Android ve iOS temel desteği
- Replay tabanlı otomatik testler
- Uzman tarafından doğrulanmış kural seti

---

## 17. Ürün vizyonu

Uzun vadede MotionSkill şu becerilere genişleyebilir:

- L-sit
- Pistol squat
- Muscle-up hazırlıkları
- Press handstand
- Handstand push-up
- Planche hazırlıkları
- Front lever hazırlıkları
- Jimnastik temel şekilleri

Ancak ürünün kimliği “her egzersizi yapan fitness uygulaması” olmamalıdır.

Ürünün kalıcı vaadi:

> Bir fiziksel beceriyi rastgele tekrarlarla değil, ölçülebilir denemeler, doğru progresyon ve açıklanabilir hareket analiziyle öğren.
