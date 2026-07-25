# SOLO COMBAT COACH — TEK KİŞİLİK KAMERA TABANLI DÖVÜŞ EĞİTİMİ
## Claude Code için Ana Proje Tanımı

> Bu belge Solo Combat Coach ürününün hedefini, V1 kapsamını, teknik mimarisini ve kritik risklerini özetleyen ana proje promptudur. Ürün tek kişi, tek sabit kamera ve ekipmansız çalışma için tasarlanmalıdır. V1’de torba, silah, partner, sparring veya temaslı teknikler bulunmamalıdır.

---

## 1. Projenin özeti

Solo Combat Coach, kullanıcının telefonunu karşısına yerleştirerek temel boks ve shadow boxing eğitimi almasını sağlayan mobil uygulamadır.

Sistem:

- Kullanıcıyı tam vücut izler
- Hareketleri tanır
- Teknik aşamaları analiz eder
- Kritik form hatalarını tespit eder
- Kısa sesli düzeltme verir
- Yapılandırılmış kurslar ve antrenmanlar sunar
- Gelişimi ölçer

Ürün LLM tabanlı canlı kamera yorumlayıcısı değildir.

Temel mimari:

> On-device pose estimation + matematik + sinyal işleme + durum makineleri + uzman kural motoru.

---

## 2. Ana hedef

İlk ürün vaadi:

> Evde tek başına yaptığın temel boks antrenmanında yalnızca yumruk sayısı değil, gard, duruş, hareket sırası ve denge hakkında açıklanabilir geri bildirim al.

Ürün gerçek antrenörün yerini tamamen aldığı iddiasında bulunmamalıdır.

---

## 3. Kullanım sınırları

### Desteklenen

- Tek kişi
- Sabit telefon
- Tam vücut kadraj
- Ekipmansız
- Shadow boxing
- Teknik drill
- Fitness boxing
- Önceden tanımlı kombinasyon
- Temel footwork

### Desteklenmeyen

- Torba
- Pad
- Silah
- Rakip
- Partner
- Sparring
- Clinch
- Takedown
- Grappling
- BJJ
- Judo uygulaması
- Güreş uygulaması
- Darbe gücü ölçümü
- Yaralanma teşhisi
- Self-defense garantisi

---

## 4. V1 branşı

V1 yalnızca:

- Boks
- Shadow boxing
- Fitness boxing

olmalıdır.

Kickboks, Muay Thai, Karate veya Taekwondo sonraki sürümlerde Standing Striking Engine üzerine eklenebilir.

---

## 5. V1 teknikleri

### Duruş

- Orthodox
- Southpaw
- Guard
- Stance width
- Weight balance
- Chin/upper body position
- Ayakların çaprazlanmaması

### Yumruklar

- Jab
- Cross
- Lead hook
- Rear hook temel
- Uppercut temel

### Savunma

- Slip left/right
- Duck
- Roll temel

### Footwork

- İleri
- Geri
- Sağa
- Sola
- Pivot temel

### Kombinasyon

- 1
- 2
- 1–2
- 1–1–2
- 1–2–3
- Basit savunma sonrası kombinasyon

V1’de en güvenilir hareketler önce açılmalıdır. Hook ve uppercut doğruluğu yeterli değilse beta özelliği olarak tutulabilir.

---

## 6. Kullanıcı akışı

1. Onboarding
2. Güvenlik açıklaması
3. Orthodox/southpaw seçimi
4. Kamera kurulum sihirbazı
5. Vücut kalibrasyonu
6. Başlangıç değerlendirmesi
7. Ders seçimi
8. Hareket öğretimi
9. Kontrollü deneme
10. Canlı antrenman
11. Tur özeti
12. Hata odaklı mikro drill
13. Gelişim geçmişi

---

## 7. Teknik mimari

```text
Camera
→ Pose Landmarker
→ Landmark Confidence Filter
→ Temporal Smoothing
→ Body Normalization
→ Orientation & Stance Detection
→ Movement State Machines
→ Technique Rule Engine
→ Feedback Prioritizer
→ Voice/Visual Feedback
→ Session Metrics
→ Local-first Storage
```

Önerilen istemci:

- Flutter
- Android Kotlin bridge
- iOS Swift bridge
- MediaPipe Pose Landmarker
- Yerel veri tabanı
- Cihaz içi ses
- Bulut yalnızca hesap, içerik, abonelik ve izinli senkronizasyon için

---

## 8. Neden LLM kullanılmamalı?

LLM:

- Kare başına güvenilir karar vermez
- Gecikme yaratır
- Maliyet yaratır
- Aynı harekete tutarsız yorum verebilir
- Teknik hata uydurabilir
- İnternet bağımlılığı doğurur

LLM yalnızca sonraki sürümlerde:

- Tur sonu açıklama
- Soru-cevap
- Program metni
- Lokalizasyon
- Destek

için opsiyonel olabilir.

---

## 9. Pose ve koordinat modeli

Her frame:

```text
timestamp
landmarks[33]
  - x
  - y
  - z
  - visibility
orientation
frameQuality
```

Ham koordinatlar normalize edilmelidir:

- Omuz genişliği
- Kalça genişliği
- Gövde uzunluğu
- Kullanıcının kol/bacak oranı
- Kamera mesafesi
- Kalibrasyon duruşu

---

## 10. Hareket durum makineleri

Örnek jab:

```text
GUARD_READY
→ INITIATION
→ EXTENSION
→ PEAK_EXTENSION
→ RETRACTION
→ GUARD_RECOVERED
```

Cross:

```text
GUARD_READY
→ REAR_SHOULDER_ROTATION
→ EXTENSION
→ HIP_SHOULDER_TRANSFER
→ RETRACTION
→ STANCE_RECOVERED
```

Slip:

```text
GUARD_READY
→ HEAD_MOVEMENT_STARTED
→ TARGET_OFFSET_REACHED
→ RETURN
→ GUARD_READY
```

Her hareketin:

- Başlangıç koşulu
- Aşama geçişi
- Bitiş koşulu
- Timeout
- İptal koşulu
- Gerekli landmark
- Güven eşiği
- Teknik metrik
- Hata kodu

olmalıdır.

---

## 11. V1 hata kodları

Önerilen ilk güvenilir hatalar:

- REAR_HAND_LOW
- LEAD_HAND_NOT_RECOVERED
- ELBOW_FLARED
- OVERREACH
- TORSO_FALLING_FORWARD
- STANCE_TOO_NARROW
- STANCE_TOO_WIDE
- FEET_CROSSED
- BALANCE_LOSS
- WRONG_HAND_FOR_COMBINATION
- COMBINATION_ORDER_ERROR
- TEMPO_TOO_FAST_FOR_FORM
- OUT_OF_FRAME
- LOW_LIGHT
- LOW_TRACKING_CONFIDENCE

Her hata:

- Severity
- Confidence
- Evidence
- Cooldown
- Feedback text
- Related drill

ile tanımlanmalıdır.

---

## 12. Güvenilirlik ilkesi

Sistem şunu ayırmalıdır:

1. Hareket yanlış
2. Kamera hareketi göremiyor
3. Hareket henüz tamamlanmadı
4. Kullanıcı farklı geçerli varyasyon yapıyor
5. Model emin değil

Düşük güven durumunda teknik hüküm verilmemelidir.

Doğru geri bildirim:

> Sağ bileğin bu açıdan güvenilir biçimde görünmüyor.

Yanlış geri bildirim:

> Sağ elini yanlış tuttun.

---

## 13. Sesli koç

Telefon kullanıcıdan uzakta olacağı için ana geri bildirim sesli olmalıdır.

Kurallar:

- Aynı anda tek hata
- Kısa cümle
- Kombinasyon ortasında uzun anlatım yok
- Kritik hata önceliği
- Aynı uyarıda cooldown
- Kullanıcı düzeltince olumlu sinyal
- Tur sonunda ayrıntı
- Müziği ve ritmi bastırmayan ses seviyesi

---

## 14. Skorlar

Tek genel “doğruluk” skoru yerine:

- Guard discipline
- Punch mechanics
- Recovery
- Footwork
- Balance
- Timing
- Combination accuracy
- Tracking confidence

gösterilmelidir.

“Power” gerçek kuvvet olarak gösterilmemelidir.

Kullanılabilecek terimler:

- Speed estimate
- Rotation score
- Extension quality
- Technical output
- Form consistency

---

## 15. Kurs yapısı

### Başlangıç

- Kamera ve alan
- Stance
- Guard
- Jab
- Cross
- 1–2
- Footwork
- Temel savunma
- İlk 3 dakikalık tur

### Orta

- Kombinasyon
- Tempo değişimi
- Savunma sonrası cevap
- Footwork ile kombinasyon
- Teknik yorgunluk

### Fitness

- 5 dakika
- 10 dakika
- 20 dakika
- HIIT
- Teknik odaklı kondisyon

Ders tamamlamak tek başına ilerleme sayılmamalıdır. Ölçülebilir beceri kriteri kullanılmalıdır.

---

## 16. Veri modeli

- UserProfile
- StancePreference
- CalibrationProfile
- Technique
- TechniquePhase
- RuleSet
- Lesson
- Workout
- Round
- PoseFrame
- MovementAttempt
- AttemptMetric
- DetectedIssue
- FeedbackEvent
- Session
- ProgressMetric
- SafetyEvent
- ModelVersion
- RuleSetVersion

Ham video varsayılan olarak kaydedilmez.

---

## 17. Güvenlik ve hukuki dil

- Temiz çalışma alanı
- Kaymayan zemin
- Sağlık sorunu varsa profesyonel görüş
- Ağrı olursa dur
- Uygulama gerçek dövüş güvenliği garantisi vermez
- Self-defense sonucu garanti edilmez
- Kullanıcıya birine vurma veya riskli pratik önerilmez
- Çocuklarda ebeveyn gözetimi

---

## 18. Test stratejisi

### Replay tests

Önceden kaydedilmiş landmark dizileriyle:

- Doğru jab
- Arka el düşük
- Dirsek açık
- Geç dönüş
- Overreach
- Denge kaybı
- Ayak çapraz
- Kadraj dışı
- Düşük güven

### Unit tests

- Açı
- Hız
- Normalizasyon
- State machine
- Cooldown
- Skor
- Sağ/sol gard dönüşümü

### İnsan testi

- Farklı vücut tipi
- Sağ/sol gard
- Bol kıyafet
- Farklı ışık
- Küçük oda
- Farklı telefon

### Uzman

Gerçek boks antrenörü kural setini doğrulamalıdır.

---

## 19. Başarı ölçütleri

- Kamera kurulum başarı oranı
- Geçerli analiz oranı
- Yanlış pozitif hata oranı
- İlk ders tamamlama
- 7/30 günlük retention
- Bir teknik metriğin zamanla gelişimi
- Kullanıcının aynı seans içinde düzeltme yapabilmesi
- Ücretsizden premium’a geçiş
- İnternetsiz antrenman kullanımı

---

## 20. V1 dışı

- Bütün dövüş sanatları
- Partner
- Torba
- Silah
- Darbe gücü
- Canlı LLM
- Avatar
- Çoklu kamera
- Koç pazaryeri
- Sosyal ağ
- Müsabaka analizi
- BJJ/güreş/judo tam kurs
- Medikal tavsiye

---

## 21. Claude Code için kurallar

- V1’i boks dışında genişletme.
- Pose modelini teknik karar motoru sanma.
- Tüm kararları açıklanabilir rule engine ile ver.
- Low-confidence durumda hüküm verme.
- Camera ve combat engine’i bağımsız paketler hâlinde tut.
- Sağ/sol gardı merkezi transform ile çöz.
- Gerçek zamanlı kodu bulut bağımlı yapma.
- Ham videoyu varsayılan yükleme.
- Hata kodlarını UI metnine doğrudan gömme.
- Rule set versioning kullan.
- Replay test olmadan yeni teknik ekleme.
- “Power” gibi fiziksel olarak ölçülemeyen değerleri kesin sunma.
- Önce beş çok güvenilir hata, sonra kapsam.

---

## 22. V1 tamamlanma kriterleri

- Android/iOS tam vücut takip
- Kamera kalibrasyonu
- Orthodox/southpaw
- Stance ve guard
- Jab/cross/1–2
- En az 10 güvenilir hata
- Footwork temel
- Canlı kısa sesli feedback
- Tur özeti
- Yerel geçmiş
- İnternetsiz antrenman
- Ham video gizliliği
- Replay testleri
- Uzman doğrulaması
- Performans/ısı ölçümü
- Abonelik öncesi çalışan ücretsiz çekirdek deneyim

---

## 23. Uzun vadeli vizyon

Ortak Standing Striking Engine üzerinden:

- Fitness Boxing
- Kickboxing
- Muay Thai striking
- Karate kihon
- Taekwondo basics
- Sanda
- Savate

eklenebilir.

Ancak her branş ayrı uzman kural seti ve içerik gerektirir.

Temel vizyon:

> Kullanıcının tek başına yaptığı ekipmansız dövüş antrenmanını kör tekrar olmaktan çıkarıp ölçülebilir, açıklanabilir ve güvenilir öğrenme sürecine dönüştürmek.
