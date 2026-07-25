# INSTRUMENT MOTION COACH — MÜZİK ALETİ POSTÜR VE HAREKET EĞİTİM PLATFORMU
## Claude Code için Ana Proje Tanımı

> Bu belge Instrument Motion Coach projesinin genel ürün ve teknik çerçevesidir. Proje bütün enstrümanları aynı anda desteklemeye çalışmamalıdır. V1 için önerilen odak çellodur; alternatif olarak keman seçilebilir. Claude Code, enstrüman bağımsız ortak çekirdeği kurmalı ancak V1 deneyimini tek enstrümanda derinleştirmelidir.

---

## 1. Projenin özeti

Instrument Motion Coach, telefon veya tablet kamerası ve mikrofonu kullanarak müzik öğrencisinin enstrüman çalarken postürünü, temel hareket tekniğini ve zamanlamasını analiz eden dijital pratik yardımcısıdır.

Temel problem:

Müzik öğrencisi öğretmeniyle haftada sınırlı süre geçirir. Hataların büyük bölümü yalnız pratik sırasında tekrar edilir. Öğretmen öğrencinin günlük oturuşunu, omuz gerginliğini, yay yolunu veya bilek pozisyonunu göremez.

Ürün vaadi:

> Öğretmenin yanında olmadığı pratik saatlerinde kamerayı aç; sistem temel postür ve hareket hatalarını tespit etsin, kısa düzeltme versin ve ilerlemeni öğretmeninle paylaşılabilir hâle getirsin.

Ürün müzik yorumunu, sanatsal ifadeyi veya profesyonel öğretmeni ikame etmez.

---

## 2. V1 enstrüman seçimi

### Önerilen: Çello

Neden:

- Kullanıcı çoğunlukla oturur.
- Tam üst gövde ve enstrüman kadrajlanabilir.
- Yay hareketi belirgin ve takip edilebilir.
- Postür hataları görsel olarak anlamlıdır.
- Öğrenciler düzenli yalnız pratik yapar.
- Kamera sabit tutulabilir.

Alternatif: Keman

Keman pazarı daha geniş olabilir; fakat baş, omuz, çene, sol el ve yay ilişkisi daha karmaşıktır. Kamera açısı daha hassastır.

V1 için tek enstrüman kesinleştirilmelidir. Aşağıdaki kapsam çello üzerinden yazılmıştır.

---

## 3. Hedef kullanıcılar

### Birincil

- Başlangıç ve erken orta seviye çello öğrencileri
- Evde yalnız pratik yapan öğrenciler
- Online ders alan kullanıcılar
- Çocuğunun pratiğini takip etmek isteyen ebeveynler
- Müzik okulu öğrencileri

### İkincil

- Çello öğretmenleri
- Müzik okulları
- Online kurs üreticileri
- Konservatuvar hazırlık öğrencileri

### V1 dışı

- Profesyonel performans değerlendirmesi
- İleri müzikal yorum
- Sınav notu verme
- Klinik kas-iskelet değerlendirmesi
- Tüm enstrümanlar
- Orkestra senkronizasyonu
- Çoklu kişi

---

## 4. Ürün modları

### 4.1 Setup Check

Kullanıcı çalmaya başlamadan:

- Sandalye yüksekliği
- Ayak yerleşimi
- Gövde dikliği
- Çello konumu
- Endpin tahmini
- Omuz seviyeleri
- Kamera yerleşimi
- Yay ve enstrümanın görünürlüğü

kontrol edilir.

### 4.2 Technique Drill

Belirli teknik:

- Açık tel yay
- Uzun yay
- Yayın köprüye paralelliği
- Yayın tel üzerindeki bölgesi
- Sağ dirsek yüksekliği
- Sol el temel şekli
- Parmak yerleşimi
- Yay değişimi

çalışılır.

### 4.3 Guided Practice

Ekranda egzersiz/metronom bulunur. Kamera ve mikrofon kullanıcıyı izler.

### 4.4 Review

Pratik sonunda:

- En sık postür hatası
- Yay yolu tutarlılığı
- Zamanlama
- Çalışma süresi
- Hatalı bölüm zamanları
- Sonraki drill

verilir.

### 4.5 Teacher Share

Kullanıcı izin verirse öğretmen:

- Seans özeti
- Seçilmiş kısa klip
- Teknik metrikler
- Öğrenci notu

görebilir.

V1’de öğretmen paneli basit veya sonraki faz olabilir.

---

## 5. Teknik bileşenler

Instrument Motion Coach, diğer Motion projelerinden daha karmaşıktır.

Gerekli katmanlar:

1. Body Pose Tracking
2. Hand Tracking
3. Instrument Detection
4. Bow Detection/Tracking
5. Audio Analysis
6. Motion-Audio Synchronization
7. Technique Rule Engine

Önerilen zincir:

```text
Camera + Microphone
→ Pose Landmarker
→ Hand Landmarker
→ Instrument/Bow Detector
→ Temporal Tracking
→ Audio Features
→ Technique State Machine
→ Rule Engine
→ Feedback
→ Session Summary
```

---

## 6. Görüntü işleme

### 6.1 Body pose

İzlenecek noktalar:

- Baş
- Omuzlar
- Dirsekler
- Bilekler
- Kalça
- Gövde ekseni

### 6.2 Eller

V1’de el takibi gerekir, fakat her parmak için kesin nota doğruluğu iddiası yapılmamalıdır.

Ölçülebilecekler:

- Sol bilek açısı
- Elin klavyeye göre genel konumu
- Parmakların kaba eğriliği
- Başparmak pozisyonu yaklaşık
- Sağ el yay tutuşu için temel şekil

### 6.3 Enstrüman ve yay

MediaPipe Pose enstrümanı bilmez. Özel nesne algılama gerekir.

İlk seçenekler:

- Lightweight YOLO model
- Custom object detector
- Segmentation
- Çello gövdesi, klavye, köprü ve yay için anahtar noktalar
- Yayın çizgi segmenti olarak takibi

V1’de model şu nesneleri ayırmalıdır:

- Cello body
- Fingerboard
- Bridge region
- Bow
- Bow hand
- Left hand

### 6.4 Kamera açısı

Tek kamera için önerilen açı:

- Hafif sağ ön çapraz
- Öğrencinin gövdesi ve yay kolu görünür
- Çellonun tamamı mümkün olduğunca görünür
- Ayak ve sandalye temel yerleşimi görünür
- Kamera sabit

Her teknik aynı açıdan iyi ölçülemez. V1 tek standart açıya göre tasarlanmalıdır.

---

## 7. Ses analizi

Mikrofon üzerinden:

- Nota başlangıç zamanı
- Tempo
- Ritim
- Sustained tone kararlılığı
- Ses kesilmeleri
- Bow change zamanları
- Metronom uyumu
- Açık tel egzersizinde perde sınıfı
- Gürültü seviyesi

ölçülebilir.

V1’de tam müzik transkripsiyonu gerekmeyebilir.

Ses analizi, hareketle senkronize edilmelidir.

Örnek:

- Yay yönü değişti
- Ses kesildi
- Dirsek ani düştü

Bu üç veri birlikte bir teknik sorun gösterebilir.

---

## 8. V1 teknik becerileri

### Setup

- Dik fakat aşırı gergin olmayan oturuş
- Omuzların yaklaşık simetrisi
- Çellonun vücuda göre konumu
- Ayakların zeminde olması
- Başın aşırı öne gitmemesi

### Bowing

- Yayın köprüye yaklaşık paralelliği
- Yayın tel üzerindeki konumu
- Yay yönü
- Kullanılan yay uzunluğu
- Sağ bilek ve dirsek ilişkisi
- Yay değişimi
- Yayın aşırı eğilmesi veya rotadan çıkması
- Temponun korunması

### Left hand basics

- Bileğin aşırı kırılması
- Dirsek yüksekliği
- Elin klavye üzerindeki genel konumu
- Parmakların kaba yerleşimi

### V1 dışı

- İleri vibrato
- Hızlı pasaj tekniği
- İleri shifting değerlendirmesi
- Profesyonel ton kalitesi hükmü
- Müzikal ifade
- Dinamik yorum
- Sınav puanı
- Her nota için kesin parmak doğruluğu

---

## 9. Teknik durum makineleri

Örnek uzun yay:

```text
READY
→ BOW_CONTACT
→ DOWN_BOW
→ DIRECTION_CHANGE
→ UP_BOW
→ COMPLETE
```

Metrikler:

- Bow path deviation
- Bow angle relative to bridge
- Bow speed
- Bow range utilization
- Direction change smoothness
- Sound continuity
- Right elbow trajectory

Geçersiz durumlar:

- Yay algılanmıyor
- Enstrüman görünmüyor
- El yayla karışıyor
- Çok düşük ışık
- Kamera hareketi
- Arka planda benzer çizgiler
- Ses seviyesi yetersiz
- Başka enstrüman sesi

---

## 10. Geri bildirim

Geri bildirim kısa ve teknik olarak güvenli olmalıdır.

Örnekler:

- “Sağ omzunu biraz serbest bırak.”
- “Yayı köprüye daha paralel tut.”
- “Yayın orta bölümünü daha fazla kullan.”
- “Sol bileğini nötr pozisyona yaklaştır.”
- “Yay değişiminde sesi kesmemeye çalış.”
- “Çelloyu gövdenden fazla uzaklaştırdın.”

Uygulama “kasını yanlış kullanıyorsun” gibi kamera ile doğrulanamayan ifadeler üretmemelidir.

Müzik sırasında sürekli konuşma rahatsız edebilir. Geri bildirim seçenekleri:

- Egzersiz sonrası
- Nota aralarında kısa ses
- Görsel ikon
- Haptic
- Zaman çizelgesinde işaret

---

## 11. Öğretmen katmanı

Uzun vadede ürünün savunulabilir tarafı öğretmen iş akışıdır.

Öğretmen:

- Öğrenciye drill atar
- Hedef tempo belirler
- Kural toleransını seçer
- Öğrencinin pratik sıklığını görür
- Öğrenci tarafından seçilmiş videoyu izler
- Yorum bırakır
- Uygulamanın otomatik bulgularını kabul/reddeder

V1’de yalnızca “shareable session report” yeterli olabilir.

---

## 12. Veri toplama ve model geliştirme

Bu proje özel veri seti gerektirir.

Gerekli çeşitlilik:

- Farklı çello boyutları
- Farklı yaylar
- Farklı kıyafet
- Farklı sandalye
- Farklı ışık
- Çocuk/yetişkin
- Sağ/sol el varyasyonu
- Doğru ve hatalı teknik
- Farklı kamera cihazları
- Arka plan çizgileri

Etiketler:

- Instrument bounding box
- Bow line/keypoints
- Bridge region
- Fingerboard
- Bow direction
- Technique phase
- Error label
- Expert confidence

Veri lisansları ve öğrenci izinleri açık olmalıdır.

---

## 13. Gizlilik

Kullanıcıların çoğu evde ve çocuk olabilir.

Kurallar:

- Ham video varsayılan olarak cihazda kalmalı
- Çocuk hesaplarında ebeveyn izni
- Öğretmene paylaşım açık onayla
- Yüz tanıma yok
- Kimlik tespiti yok
- Ses kaydı saklama varsayılan olarak kapalı
- Model eğitimi için ayrı açık rıza
- Veriyi silme
- Saklama süresini gösterme

---

## 14. Riskler

### Teknik risk

Yay ince, hızlı ve çizgisel bir nesnedir. Hareket bulanıklığı ve arka plan çizgileri sorun çıkarır.

### Uzmanlık riski

Yanlış teknik tavsiye öğrencinin kötü alışkanlık geliştirmesine yol açabilir. Kural seti gerçek çello öğretmeniyle hazırlanmalıdır.

### İçerik riski

Her egzersiz için video, nota/metronom, açıklama, tolerans ve değerlendirme kuralı gerekir.

### Pazar riski

Niş pazar daha küçük olabilir. B2B öğretmen/müzik okulu modeli önemlidir.

### Çocuk güvenliği

Çocuk verisi ve video paylaşımı özel koruma gerektirir.

---

## 15. Veri modeli

- User
- StudentProfile
- GuardianConsent
- TeacherProfile
- InstrumentProfile
- CameraSetup
- PracticePlan
- Exercise
- Score/MetronomeConfig
- Session
- MotionFrame
- AudioFrame
- InstrumentDetection
- BowTrack
- TechniqueAttempt
- Metric
- DetectedIssue
- Feedback
- SharedClip
- TeacherComment
- ModelVersion
- RuleSetVersion

---

## 16. Test stratejisi

### Algoritma testleri

- Bow line detection
- Parallelism angle
- Temporal tracking
- Audio onset detection
- Metronome alignment
- Pose/hand fusion
- Error cooldown
- State machine

### Fixture

- Doğru uzun yay
- Yay köprüye eğik
- Kısa yay kullanımı
- Omuz yükselmesi
- Bilek kırılması
- Kamera hareketi
- Yay kaybolması
- Ses kesilmesi

### Uzman doğrulama

Her hata, en az bir profesyonel öğretmen tarafından incelenmelidir.

---

## 17. V1 dışı

- Tüm enstrümanlar
- Canlı insan öğretmen pazaryeri
- Otomatik sınav notu
- Müzik teorisi platformu
- Tam nota transkripsiyonu
- Orkestra analizi
- Profesyonel performans jüri sistemi
- Medikal ergonomi teşhisi
- LLM’nin kamera görüntüsünü yorumlaması
- Kullanıcı videosunu varsayılan buluta yükleme

---

## 18. Claude Code için kurallar

- Önce tek enstrümanda derinlik.
- Body pose ile instrument tracking katmanını ayır.
- Enstrüman algılanmadan teknik hüküm verme.
- Audio ve motion timestamp’lerini tek clock altında tut.
- Düşük güven durumunda geri bildirim üretme.
- Teknik kuralı uzman tarafından düzenlenebilir config hâline getir.
- Çocuk verisine özel politika uygula.
- Öğretmen geri bildirimini otomatik sistemden ayır.
- “Ton kötü” gibi öznel genel hüküm üretme.
- Müzik akışını sürekli sesli uyarıyla bozma.
- Analiz replay sistemi olmadan gerçek zamanlı UI geliştirmeyi ilerletme.
- Her skorun bileşenlerini açıklanabilir tut.

---

## 19. V1 tamamlanma kriterleri

- Standart kamera kurulum akışı
- Çello/enstrüman algılama
- Yay takibi
- Body pose + hand tracking
- Açık tel uzun yay egzersizi
- En az 5 güvenilir teknik geri bildirim
- Metronom uyumu
- Seans özeti
- Yerel kayıt
- Kullanıcı izinli kısa klip paylaşımı
- Uzman doğrulaması
- Düşük güven durumunda hata vermeme
- Çocuk/ebeveyn izin akışı
- Android veya iPad/iOS üzerinde çalışan ilk ürün; iki platform aynı anda zorunlu değil
- Veri toplama ve model versiyonlama altyapısı

---

## 20. Ürün vizyonu

V1 doğrulandıktan sonra:

- Keman
- Gitar
- Piyano
- Flüt
- Davul

gibi enstrümanlara ayrı motorlar geliştirilebilir.

Ortak çekirdek:

- Pose
- Hand
- Object
- Audio
- Teacher workflow

olabilir.

Temel vizyon:

> Müzik öğrencisinin öğretmensiz pratik saatlerini görünür, ölçülebilir ve düzeltilebilir hâle getirmek.
