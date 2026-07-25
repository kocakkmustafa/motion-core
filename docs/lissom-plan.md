# MOBILITY AGE — KAMERA TABANLI MOBİLİTE ÖLÇÜMÜ VE GÜNLÜK HAREKET PROGRAMI
## Claude Code için Ana Proje Tanımı

> Bu belge Mobility Age ürününün ürün hedefini, teknik sınırlarını, kullanıcı akışını, değerlendirme sistemini, risklerini ve V1 kapsamını tanımlar. Ürün medikal teşhis veya rehabilitasyon uygulaması değildir. Claude Code bütün mimari ve metin kararlarında wellness/performance sınırını korumalıdır.

---

## 1. Projenin özeti

Mobility Age, telefon kamerasıyla kullanıcının temel hareket açıklığını, sağ-sol farklarını, denge ve kontrollü hareket kapasitesini değerlendiren; daha sonra kullanıcıya günlük kısa mobilite programı sunan bir mobil uygulamadır.

Ürün vaadi:

> Birkaç dakikalık kamera testiyle hareket kapasiteni ölç, hangi bölgelerde kısıtlı olduğunu gör, günlük kısa programını uygula ve zaman içindeki değişimi yeniden ölç.

“Mobility Age” kullanıcıya kolay anlaşılır bir ilerleme göstergesi sunabilir; ancak bu değer biyolojik yaş, tıbbi yaş veya sağlık teşhisi olarak sunulmamalıdır. Uygulama içi bir performans indeksi olduğu açıkça belirtilmelidir.

---

## 2. Ürün konumu

Ürün şu kategoridedir:

- Wellness
- Mobility
- Flexibility
- Movement quality
- Performance preparation
- Desk-worker movement
- Sport-support training

Ürün şu kategoride değildir:

- Fizik tedavi
- Tıbbi teşhis
- Sakatlık tedavisi
- Ağrı tedavisi
- Ortopedik değerlendirme
- Klinik gait analizi
- Doktor veya fizyoterapist yerine geçen sistem

---

## 3. Hedef kullanıcılar

### Birincil

- Masa başında çalışan yetişkinler
- Hareket açıklığını geliştirmek isteyen sporcular
- Evde kısa mobilite rutini arayan kullanıcılar
- Koşu, dans, dövüş veya calisthenics yapan kişiler
- “Esnek değilim, nereden başlamalıyım?” diyen kullanıcılar
- Yaş ilerledikçe hareket kapasitesini korumak isteyen yetişkinler

### İkincil

- Fitness eğitmenleri
- Spor koçları
- Kurumsal wellness programları
- Life OS kullanıcıları
- Solo Combat ve Solo Dance kullanıcıları

### V1 dışı

- Akut ağrısı olan kullanıcılar
- Ameliyat sonrası rehabilitasyon
- Nörolojik rahatsızlık
- Düşme riski yüksek kullanıcı
- Klinik takip bekleyen hastalar
- Çocuklara özel program

---

## 4. Ana ürün döngüsü

```text
Onboarding
→ Güvenlik taraması
→ Kamera kalibrasyonu
→ Mobility Assessment
→ Bölgesel skorlar
→ Mobility Age indeksi
→ Kişisel günlük program
→ Kamera doğrulamalı egzersiz
→ Haftalık mini test
→ 4 haftalık yeniden değerlendirme
```

Ürünün değerini yalnızca egzersiz videoları değil, ölçüm ve yeniden ölçüm döngüsü oluşturmalıdır.

---

## 5. V1 değerlendirme testleri

V1’de en fazla 8–10 test olmalıdır.

Önerilen testler:

1. Overhead shoulder flexion
2. Deep squat
3. Ankle dorsiflexion
4. Standing hamstring reach
5. Hip internal/external rotation için güvenli fonksiyonel varyasyon
6. Thoracic rotation
7. Side bend
8. Single-leg balance
9. Hip hinge
10. Neck rotation için yalnızca basit, düşük riskli gözlemsel test

Her test:

- Kısa olmalı
- Ekipmansız olmalı
- Tek kamera ile görülebilmeli
- Kullanıcı tarafından yanlış anlaşılmamalı
- Kesin sağlık sonucu üretmemeli
- Düşük riskli olmalı

V1’de karmaşık klinik testler kullanılmamalıdır.

---

## 6. Ölçüm yaklaşımı

### Ölçülebilecekler

- Eklem açıları
- Hareket açıklığı
- Sağ-sol farkı
- Gövde kompansasyonu
- Denge süresi
- Kontrollü tekrar
- Hedef pozisyonda kalma
- Hareketin yarıda kalması
- Diz/kalça/omuz ilişkileri
- Kamera açısından güven seviyesi

### Ölçülemeyecekler

- Kas kısalığının kesin nedeni
- Bağ, tendon veya eklem patolojisi
- Ağrı kaynağı
- Sinir sıkışması
- Gerçek kuvvet
- Eklem içi yapı
- Kullanıcının güvenli biçimde daha fazla zorlanıp zorlanamayacağı

Sistem gözlediği hareketi raporlamalı, nedenine dair tıbbi tahmin yapmamalıdır.

Örnek doğru ifade:

> Sağ omuz fleksiyonunda sol tarafa göre daha düşük hareket açıklığı gözlendi.

Yanlış ifade:

> Sağ omuz kapsülünde kısıtlılık var.

---

## 7. Mobility Age indeksi

Mobility Age bir oyunlaştırılmış gösterge olmalıdır.

Bileşenler:

- Üst gövde hareket açıklığı
- Alt gövde hareket açıklığı
- Sağ-sol simetri
- Denge
- Hareket kontrolü
- Tutarlılık
- Test güvenilirliği

İndeks yaşla doğrudan eşleştirilecekse bunun klinik veya biyolojik yaş olmadığı çok açık belirtilmelidir.

Daha güvenli alternatifler:

- Mobility Score
- Motion Age
- Movement Readiness
- Mobility Level

“Yaş” kavramı pazarlama açısından güçlü, fakat yanıltıcı olmamalıdır.

Skorlar kullanıcıyı utandırmamalı veya korkutmamalıdır.

---

## 8. Günlük program motoru

Program oluşturma ilk aşamada LLM ile yapılmamalıdır.

Deterministik rule engine:

```text
Assessment result
+ Kullanıcı hedefi
+ Mevcut spor
+ Günlük zaman
+ Ağrı/güvenlik beyanı
→ Program template
→ Exercise selection
→ Süre ve tekrar
→ Haftalık progression
```

Örnek:

- Düşük ankle mobility
- Orta hip mobility
- İyi shoulder mobility
- Koşucu profili
- Günlük 8 dakika

Sonuç:

- Ankle rocks
- Calf stretch
- Controlled deep squat hold
- Hip airplane hazırlığı
- Thoracic rotation

Her egzersizin seçilme nedeni loglanmalıdır.

---

## 9. Günlük egzersiz deneyimi

Her seans:

1. Bugünkü hedef
2. Kısa ısınma
3. 3–5 hareket
4. Kamera üzerinden poz/süre kontrolü
5. Kullanıcının ağrı geri bildirimi
6. Seans özeti
7. Bir sonraki test tarihi

Kamera sürekli zorunlu olmayabilir. Bazı hareketlerde takip opsiyonel olabilir. Bu, kullanıcının günlük sürtünmesini azaltır.

Kamera kullanılan egzersizlerde:

- Poz süresi
- Hareket tekrar sayısı
- Hareket açıklığı
- Sağ-sol eşitliği
- Temel kompansasyonlar

izlenebilir.

---

## 10. Teknik mimari

```text
Camera
→ Pose Landmarker
→ Tracking Quality
→ Body Normalization
→ Test-specific Measurement Engine
→ Assessment Rules
→ Score Engine
→ Program Rules
→ Session Guidance
→ Local-first Storage
```

Önerilen:

- Flutter
- Kotlin/Swift native pose bridge
- MediaPipe Pose Landmarker
- Yerel veri tabanı
- Bulut senkronizasyonu opsiyonel
- Ham videoyu saklamama
- Kuralların JSON/YAML veya versioned config ile yönetilmesi

---

## 11. Test motoru

Her test bağımsız bir modül olmalıdır.

Örnek arayüz:

```text
MobilityTest
- id
- name
- cameraSetup
- requiredLandmarks
- calibrationRequirements
- stateMachine
- metrics
- invalidationRules
- scoreMapping
- feedbackRules
- safetyCopy
```

Örnek deep squat state machine:

```text
READY
→ DESCENDING
→ BOTTOM_REACHED
→ HOLDING
→ ASCENDING
→ COMPLETE
```

Geçersiz test durumları:

- Topuk görünmüyor
- Kullanıcı kadrajdan çıktı
- Kamera açısı yanlış
- Test yeterli derinliğe ulaşmadan bırakıldı
- Kritik landmark güveni düşük
- Kullanıcı destek aldı
- Birden fazla kişi görünür

---

## 12. Kişiselleştirme

Kişiselleştirme şu bilgilere dayanmalıdır:

- Hedef
- Mevcut spor
- Günlük süre
- Başlangıç skoru
- Sağ-sol farkı
- Haftalık uyum
- Kullanıcının ağrı geri bildirimi
- Önceki program performansı
- Kullanıcının hareketleri tamamlayabilme oranı

İlk aşamada “AI sana özel program” yerine açıklanabilir kural tabanlı kişiselleştirme kullanılmalıdır.

---

## 13. Riskler

### Sağlık iddiası riski

En büyük ürün riski medikal sınıra yaklaşmaktır.

Kaçınılması gereken ifadeler:

- Ağrını geçirir
- Sakatlığı tedavi eder
- Fıtığı düzeltir
- Omuz sıkışmasını çözer
- Duruş bozukluğunu teşhis eder
- Fizik tedavi yerine geçer

### Ölçüm yanılsaması

Tek kamera 3D hareketi tam ölçmez. Sonuçlar “yaklaşık” ve kamera koşullarına bağlı olmalıdır.

### Kullanıcının aşırı zorlaması

Skor yükseltmek için hareket açıklığını güvenli olmayan şekilde zorlayabilir. Uygulama acı oluştuğunda durmayı hatırlatmalıdır.

### Retention

Kullanıcı değerlendirmeyi yapıp uygulamayı bırakabilir. Günlük seansların kısa, ilerlemenin görünür ve yeniden test döngüsünün güçlü olması gerekir.

---

## 14. Veri modeli

- UserProfile
- MobilityGoal
- SafetyScreen
- CalibrationProfile
- Assessment
- MobilityTestDefinition
- TestAttempt
- TestMetric
- RegionScore
- MobilityIndex
- ProgramTemplate
- DailyProgram
- Exercise
- ExerciseAttempt
- PainFeedback
- ProgressSnapshot
- RuleSetVersion
- ModelVersion

Ağrı verisi hassas kabul edilmelidir.

---

## 15. Ürün paketleri

Uzun vadede:

- Desk Worker
- Runner
- Fighter
- Dancer
- Calisthenics
- General Mobility
- 40+
- Travel Mobility

V1’de tüm paketler ayrı ürün gibi geliştirilmemeli. Genel motor + 2 kullanıcı profili yeterlidir:

1. Genel mobilite
2. Masa başı çalışan

---

## 16. Test ve doğrulama

### Teknik test

- Eklem açıları
- Kamera perspektifi
- Sağ-sol dönüşümü
- State machine
- Test geçersizleştirme
- Skor haritalama
- Program seçme kuralları

### İnsan testi

Farklı:

- Yaş
- Boy
- Vücut oranı
- Esneklik seviyesi
- Kıyafet
- Telefon
- Işık

koşullarında test yapılmalıdır.

### Uzman doğrulaması

En az bir mobilite/fitness uzmanı:

- Testlerin güvenliğini
- Egzersiz seçimlerini
- Skor dilini
- Progresyonu
- Güvenlik metinlerini

gözden geçirmelidir.

---

## 17. Başarı ölçütleri

- Assessment completion rate
- Test başına geçerli ölçüm oranı
- Kullanıcının günlük programı tamamlama oranı
- 7, 14 ve 30 günlük retention
- 4 hafta sonunda yeniden test oranı
- Bölgesel skor değişimi
- Kullanıcının ağrı bildirdiği oturum oranı
- Yanlış pozitif form uyarısı
- Kamera kurulum başarısı

---

## 18. V1 dışı

- Klinik rapor
- Fizyoterapiste otomatik teşhis
- Sigorta sistemi
- Doktor paneli
- Rehabilitasyon protokolü
- Çocuk programı
- Yaşlı düşme riski değerlendirmesi
- Çoklu kamera
- Giyilebilir cihaz zorunluluğu
- LLM tabanlı sağlık tavsiyesi
- Sosyal ağ
- Canlı ders
- Genel beslenme veya kilo verme planı

---

## 19. Claude Code için kurallar

- Ürünü medikal uygulamaya dönüştürme.
- “AI tanı” veya “AI tedavi” özelliği ekleme.
- Test sonuçlarını kesin gerçek olarak sunma.
- Skor algoritmasını gizli ve açıklanamaz bırakma.
- Ham videoyu varsayılan olarak buluta yükleme.
- Her test için geçersizleştirme kuralları oluştur.
- Düşük güven durumunda skor üretme.
- Sağ-sol ve kamera aynalama sorunlarını merkezi çöz.
- Program motorunu versioned rule set ile kur.
- Her önerinin nedenini kayıt altına al.
- Önce assessment güvenilirliği, sonra içerik kataloğu.
- Kullanıcıyı korkutan sağlık dili kullanma.

---

## 20. V1 tamamlanma kriterleri

- En az 8 çalışan mobility testi
- Kamera kurulum yönlendirmesi
- Geçerli/geçersiz test ayrımı
- Bölgesel skorlar
- Açıklanabilir Mobility Index
- En az iki program profili
- Günlük 5–10 dakikalık seanslar
- Kamera doğrulamalı en az 10 egzersiz
- Yerel ilerleme kaydı
- 4 haftalık yeniden test
- Ağrı güvenlik akışı
- Android/iOS
- İnternetsiz temel çalışma
- Uzman tarafından doğrulanmış test ve egzersiz seti

---

## 21. Ürün vizyonu

Mobility Age tek başına ürün olabilir; ayrıca diğer Yula Motion ürünlerinin ortak değerlendirme ve hazırlık katmanı olabilir.

Uzun vadeli kullanım:

- Solo Combat öncesi hareket hazırlığı
- Solo Dance için hareket açıklığı
- MotionSkill için omuz/bilek hazırlığı
- Life OS içinde hareket sağlığı modülü
- Spor branşına özel mobility packs

Temel vizyon:

> Kullanıcıya rastgele esneme videoları vermek yerine hareket kapasitesini ölç, en önemli sınırlara göre kısa program üret ve gelişimi yeniden ölç.
