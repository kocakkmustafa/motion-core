"""Kaynak-uygunluk sınıflandırması: gösterilen hareket AKTİF mi PASİF mi (M-F-43).

Neden gerekli: skorlama referansı DOĞRU olmalı (M-C-01). Pasif ROM'da hareketi
klinisyen üretir ve pasif aralık tipik olarak aktiften geniştir; böyle bir
kaynaktan türetilen referans kullanıcıya ULAŞILAMAZ hedef koyar.

Neden landmark'tan DEĞİL metadata'dan: klinisyen kolu kaldırdığında landmark izi
aktif uzanmayla BİREBİR AYNI (Lissom ölçümü L-095). Kamera bu ayrımı göremez;
ayrım yalnız kaynağın kendi anlatısında vardır.

Neden `provisional` etiketi YETMEZ: provisional istatistiksel zayıflığı örter,
SİSTEMATİK yanlılığı örtmez. Pasif kaynaklardan kurulan bir referans, örneklem
büyüdükçe daha da yanlış olur.

FAIL-CLOSED: varsayılan `unknown` ve `unknown` referansa GİREMEZ. "İşaret
bulamadım" asla "aktif" sayılmaz — sessiz kabul, kuralın kendisini iptal eder.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

ACTIVE = "active"
PASSIVE = "passive"
UNKNOWN = "unknown"

#: GÜÇLÜ pasif işaretler: hareketi BAŞKA BİRİNİN ürettiğini açıkça söyler.
#: Biri bile geçiyorsa kaynak referansa giremez.
PASSIVE_MARKERS = (
    r"\bpassive(ly)?\b", r"\bPROM\b", r"\btherapist\b", r"\bclinician\b",
    r"\bexaminer\b", r"\bpractitioner\b", r"\bover ?pressure\b",
    r"\bmanual (resistance|therapy|muscle)\b",
    r"\bI (will|'ll) (move|lift|take)\b", r"\blet me (move|lift|take)\b",
    r"\brelax (your|the) (arm|leg|shoulder)\b",
)

#: ZAYIF işaretler: pasif ANLAMA GELEBİLİR ama çoğu zaman gelmez. Tek başına
#: pasif SAYILMAZ — yalnız kaydedilir. ÖLÇÜLDÜ (L-122): bu işaretler
#: `deep_squat`'ın 4 kaynağından 2'sini yanlışlıkla eledi.
#:   "assist"      → "level one is the deep squat WITH AN ASSIST using
#:                    something in front of you" = kişi KENDİ tutunuyor
#:   "resistance"  → "with more resistance or with more body weight" = YÜK
#:   "mobiliz"     → "mobilization and soft-tissue pliability techniques"
#:                    = videonun öğrettiği şey, kimse kimseyi hareket ettirmiyor
#: Yanlış pozitif asimetrik zarar verir: iyi kaynağı ÖLDÜRÜR. Gerçek pozitif
#: örneklerimizin hepsinde en az bir GÜÇLÜ işaret vardı, yani bu ayrım hiçbir
#: doğru tespiti kaybetmiyor.
WEAK_PASSIVE_MARKERS = (
    r"\bresisted\b", r"\bresistance\b", r"\bassist(ed|ance)\b",
    r"\bmobiliz",
)

#: DURUŞ-YÖNERGESİ sınıfı (M-O-54/M-F-125): öğrenciye verilen, KENDİ
#: gövdesini konumlandırmasını isteyen ikinci-şahıs emir kipi. Ayrı bir
#: demet olarak durur ki tek başına açılıp kapatılabilsin (aynı-kod izole
#: süpürmesi bu ayrımı gerektirir).
#:
#: NEDEN EKLENDİ — ölçüldü, varsayılmadı (M-O-54): çalgı-duruşu öğreten
#: kaynaklarda mevcut `ACTIVE_MARKERS` sözlüğü YAPISAL olarak sıfır isabet
#: veriyor. Rpalo0sbpj4: 11.698 karakter, "posture"×18 / "sitting"×12 /
#: "shoulder"×11 → ACTIVE isabet 0. SGsYZAqIwi4: 10.818 karakter,
#: "sitting"×14 → ACTIVE isabet 0. Uygun ÇIKAN kaynaklar ise duruşa özgü
#: hiçbir işaretle değil, GENEL fiillerle geçmişti ("bring your...",
#: "lift your...") — yani havuz bir eleme değil, büyük ölçüde bir rastlantı
#: sonucuydu. Sözlük rehab/ROM için yazılmış ("follow along", "AROM");
#: duruş öğretmeni "benimle birlikte yap" demez, "dik otur" der.
#:
#: SINIR — pasif taraf EZİLMEZ: `classify` pasifi ÖNCE kontrol eder ve
#: pasif kazanır (bu dosyanın karar sırası), yani buraya eklenen hiçbir
#: kalıp "let me adjust"/"I'll move your" sınıfını geçersizleştiremez.
#: `relax your shoulder` KASTEN BURAYA ALINMADI: aynı ifade PASSIVE
#: demetinde zaten var (terapist uzvu hareket ettirebilsin diye gevşetme)
#: ve duruş bağlamındaki anlamı ters olsa da, çakışan bir kalıbı iki tarafa
#: birden yazmak sınıflandırmayı belirsizleştirir — yanlış tarafta hata
#: yapmak referansı kirletir (bu dosyanın kendi ilkesi).
#: İKİNCİ-ŞAHIS ŞARTI — ÖLÇÜLDÜ, sonradan sıkılaştırıldı. İlk sürüm
#: `\bchin (up|down|level|parallel)\b` ve çıplak `\bfeet flat\b` içeriyordu;
#: aile-geneli süpürme (bkz. `tools/sweep_posture_dialect.py`) ikisinin de
#: YANLIŞ YÖNDE isabet ettiğini gösterdi:
#:   · jablab/InSkFbZWoBY: "he walks in with HIS chin down" → ÜÇÜNCÜ ŞAHIS
#:     ANLATIM, öğrenciye yönerge değil.
#:   · ostinato/dc8PNOTTUlg: "I've got nice control with MY feet flat" →
#:     BİRİNCİ ŞAHIS; bu zaten `FIRST_PERSON_DEMO_MARKERS` sınıfının işi,
#:     duruş-yönergesi sınıfının değil.
#: Aktif tarafta yanlış pozitif, pasif taraftakinin AYNASI ve daha
#: tehlikelisidir: pasif yanlış-pozitifi iyi kaynağı ÖLDÜRÜR, aktif
#: yanlış-pozitifi KÖTÜ kaynağı REFERANSA SOKAR (M-F-43'ün korumaya
#: çalıştığı ulaşılamaz-hedef tehdidi). Bu yüzden kalıplar artık
#: tereddütsüz ikinci-şahıs ister. Bedeli isimle kayıtlı: "keep your hands
#: up, chin down" (jablab/umI6jNMVG-s) gibi GERÇEK yönergeler de elendi —
#: güvenli yön bilinçli olarak seçildi.
POSTURE_CUE_MARKERS = (
    r"\b(sit|stand) (up )?(tall|straight|upright)\b",
    # MECAZ KAPISI (M-F-143 sevki, JabLab M-F-137 deseniyle AYNI): vücut
    # adının ardından "in the"/"on the" gelirse bu bir DURUŞ yönergesi değil
    # deyimdir — "keep your head IN THE game", "keep your eyes ON THE prize".
    # LATENT kusurdu: aile korpusunda bugün SIFIR isabeti var (ölçtüm), ama
    # kalıp eşleşiyordu ve JabLab izole kıyasla benim ailemden ACTIVE
    # ürettiğini gösterdi. Ölçülmüş geçiş olmadan da kapatılır, çünkü
    # yanlış yön AKTİF tarafta: kötü kaynağı referansa SOKAR (M-F-43).
    # Bedeli isimle: "keep your back ON THE wall" gibi gerçek ama seyrek
    # yönergeler de elenir — güvenli yön bilinçli seçildi (M-O-54 aynı karar).
    r"\bkeep your (back|spine|shoulders?|head|chin|neck|wrist)\b"
    r"(?!\s+(?:in|on)\s+the\b)",
    r"\b(drop|lower|roll) your shoulders?\b",
    r"\byour shoulders? (back and )?down\b",
    r"\byour chin (up|down|level|parallel)\b",
    r"\b(align|lengthen|elongate|straighten) your (spine|back|neck|posture)\b",
    r"\byour feet flat\b", r"\bboth (of your )?feet flat\b",
    r"\bsit (on|at|toward|towards) the (edge|front) of your\b",
    r"\byour (sitting|seated) position\b",
)

#: HAREKET-YÖNERGESİ (İKİNCİ-ŞAHIS EMİR KİPİ) sınıfı — J-065/M-F-137.
#:
#: NE OLDUĞU: koçun öğrenciye verdiği, ÖĞRENCİNİN KENDİ gövdesini hareket
#: ettirmesini isteyen emir kipi ("keep your hands up", "tuck your chin",
#: "drop your hands"). `POSTURE_CUE_MARKERS`in tamamlayıcısı: o STATİK
#: konumlandırmayı ("dik otur", "omuzların geride") tanır, bu HAREKETİ.
#:
#: NEDEN AYRI DEMET — ve neden M-O-54'ün ailesi GEVŞETİLMEDİ: M-O-54,
#: şartlı-kalıp ailesini tereddütsüz ikinci-şahısa sıkarken bedelini isimle
#: kaydetti — "keep your hands up, chin down" (jablab/umI6jNMVG-s) gibi
#: GERÇEK yönergeler de elendi. O feda DOĞRUYDU (aktif yanlış-pozitifi KÖTÜ
#: kaynağı referansa sokar, M-F-43). Bu demet o fedanın **tamamlayıcı
#: geri-kazanımı**: onların kalıplarını gevşetmek yerine, kaybedilen sınıfı
#: kendi kapılarıyla geri alır. Böylece iki demet bağımsız açılıp
#: kapatılabilir ve izole süpürme her birini ayrı ölçebilir.
#:
#: ÖLÇÜLEN KÖR NOKTA (J-064): iki jab kaynağı `unknown`da kalıp HARD BLOCK
#: yedi ve jab referansının yeniden kurulmasını imkânsız kıldı:
#:   · umI6jNMVG-s (Precision Striking): 7.451 karakter, 15 emir kipi +
#:     88 "you + fiil" — "keep your hands up" dahil. ACTIVE isabet 0.
#:   · InSkFbZWoBY (Sören/Kenny Weldon): 8.075 karakter — "tuck your chin",
#:     "drop your hands", "put your hands down", "throw your punches".
#:     ACTIVE isabet 0.
#: Mevcut `(raise|lift|reach|bring) your` yalnız DÖRT fiil tanıyor; boks
#: koçu "raise your arm" demez, "keep your hands up" der.
#:
#: ÜÇ SERT KAPI (hepsi ölçülmüş tuzaklara karşı):
#:  1. **`your` ZORUNLU, `the` KABUL EDİLMEZ.** Kanıttaki "bend the knees",
#:     "turn the other way", "step the next step" bilinçli olarak DIŞARIDA:
#:     `the` üçüncü-şahıs anlatımda da geçer, `your` geçmez. M-O-54'ün
#:     seçtiği güvenli yön aynen korunuyor.
#:  2. **ÜÇÜNCÜ-ŞAHIS ANLATIM GEÇMEZ** — bilinen tuzak sınıfı, M-O-54
#:     süpürmesinin adıyla kaydettiği vaka: "he walks in with HIS chin down"
#:     (jablab/InSkFbZWoBY). `his`/`her`/`their` bu kalıplara UYMAZ.
#:  3. **BİRİNCİ ŞAHIS GEÇMEZ** — "I've got nice control with MY feet flat"
#:     (ostinato/dc8PNOTTUlg) bu sınıfın değil `FIRST_PERSON_DEMO_MARKERS`in
#:     işi; `my` bu kalıplara uymaz.
#:
#: `relax` KASTEN YOK: `relax (your|the) (arm|leg|shoulder)` ZATEN
#: PASSIVE_MARKERS'ta (terapist uzvu hareket ettirebilsin diye gevşetme).
#: Çakışan bir kalıbı iki tarafa birden yazmak sınıflandırmayı
#: belirsizleştirir — bu dosyanın kendi ilkesi.
#:
#: `move|lift` gibi pasif cümlelerde de görünebilen fiiller listede DURUYOR
#: ama tehlikeli DEĞİL: `classify()` pasifi ÖNCE kontrol eder ve pasif
#: kazanır, yani "I'll move your arm" PASSIVE'e düşer (aynı güvence
#: `(raise|lift|...) your` için de zaten geçerliydi).
#:
#: İsim demeti ANATOMİK + genel hareket nesnesi: fiil tek başına
#: ("keep your eyes on the prize") mecazı da yakalardı; ismi sınırlamak
#: POSTURE_CUE_MARKERS'in felsefesini sürdürür.
#: MECAZ KAPISI — ölçüldü, varsayılmadı. İlk sürüm ismi sınırlamakla yetindi
#: ve kendi negatif korpusum bir yanlış pozitif yakaladı: "keep your head IN
#: THE game" → `keep your head` isabet etti. Mecaz bir hareket yönergesi
#: değildir ve aktif yanlış-pozitifi KÖTÜ kaynağı referansa sokar. Bu yüzden
#: kalıp, ismin ardından `in the` / `on the` gelmesini REDDEDER — mecazların
#: ("head in the game", "eyes on the prize") taşıyıcı yapısı budur.
#: Bedeli isimle: "keep your hands IN THE guard position" gibi gerçek ama
#: seyrek yönergeler de elenir — güvenli yön bilinçli seçildi (M-O-54 aynı
#: kararı aynı gerekçeyle vermişti).
MOVEMENT_CUE_MARKERS = (
    r"\b(keep|bring|snap|extend|turn|rotate|drop|raise|lift|push|pull|step|"
    r"pivot|tuck|shift|square|point|plant|drive|throw|land|return|bend|"
    r"straighten|move|place|put)\s+your\s+"
    r"(hands?|fists?|arms?|elbows?|shoulders?|chin|head|hips?|knees?|"
    r"foot|feet|legs?|guard|punch(?:es)?|jab|weight|back|spine|core|"
    r"toes?|heels?|stance|body|torso|chest|wrists?|thighs?|shins?)\b"
    r"(?!\s+(?:in|on)\s+the\b)",
)

#: BİRİNCİ-ŞAHIS ÇOĞUL hareket yönergesi (M-F-213 sevki · JabLab J-090).
#:
#: Dans/grup öğretiminin ANA KİPİ ve ailenin iki mevcut sınıfı da buna KÖR:
#: `MOVEMENT_CUE_MARKERS` ikinci şahıs ("keep your hands"),
#: `FIRST_PERSON_DEMO_MARKERS` tekil birinci şahıs ("I'm throwing").
#: "We're going to step back with our right on count one" hiçbirine girmiyor.
#:
#: BULUNUŞU (zayıf-işaret süpürmesinin yan ürünü): `choreia/FtZzjGsPxjg`
#: sunumsal bir ifadeyle (`here's the regular basic`) uygun sayılıyordu; o
#: kalıp zayıf-kademeye inince kaynak `unknown`a düştü — DOĞRU sonuç ama
#: YANLIŞ sebeple: transkriptte gerçek aktif kanıt VARDI ve sözlük onu
#: görmüyordu.
#:
#: TUZAK SINIFI — SUNUMSAL ÇOĞUL. "We're going to talk about / look at /
#: cover / go over the hook" bir HAREKET DEĞİL, bir GÜNDEM cümlesidir. Bu
#: yüzden fiil listesi BEYAZ LİSTE: sunumsal fiiller listede olmadığı için
#: eşleşemez. Kara liste tutmak, her yeni sunum fiilinde sızıntı demek olurdu.
#:
#: İKİ MECAZ KAPISI (imperative ailesindeki `in/on the` disiplininin kardeşi,
#: ikisi de gerçek kullanımdan alındı):
#:   * "move ON TO the next drill" → konu geçişi, hareket değil
#:   * "step THROUGH the combination" → anlatım, hareket değil
#: Fiil hareket fiili olsa bile bu edatlar cümleyi sunumsal yapıyor.
FIRST_PERSON_PLURAL_CUE_MARKERS = (
    r"\b(?:we(?:'re| are|'ll| will)?|let'?s)\s+"
    r"(?:(?:gonna|going to|will)\s+)?(?:be\s+)?"
    r"(step|turn|rotate|pivot|shift|lean|bend|straighten|reach|extend|"
    r"push|pull|drive|swing|throw|punch|jab|kick|jump|hop|drop|lift|"
    r"raise|lower|slide|cross|squat|hinge|press|roll|twist|move|"
    r"stepping|turning|moving|shifting|leaning|reaching|swinging)\b"
    # ÜÇ MECAZ/İDYOM KAPISI — üçü de GERÇEK korpustan ölçülerek eklendi:
    #   * "move ON TO / step THROUGH"  → konu geçişi (ilk iki kapı)
    #   * "jump/dive INTO the exercises" → başlama idyomu; hareket fiili ama
    #     hareket DEĞİL (ostinato/pwIO71FhP9g · choreia/AyzYABnWDEM)
    #   * "move now TO THE NEXT step" → yine konu geçişi, ama araya sözcük
    #     giriyor ve dar bir bakış onu KAÇIRIYORDU (choreia/o6E9Ljr5o_c);
    #     bu yüzden 0-2 sözcüklük pencere.
    r"(?!(?:\s+\w+){0,2}\s+(?:on\s+to|onto|into|through|to\s+the\s+next)\b)"
    r"(?!\s+(?:on\s+to|onto|into|through)\b)",
    # ⚠️ AÇIK KALEM — NESNE↔GÖVDE ayrımı bu ailede YAPILAMIYOR (J-090/J-091).
    #
    # ⛔ OLUMLU KURAL DENENDİ VE ÖLÇÜLEREK BIRAKILDI (M-F-216 hükmü a,
    #    kabul kriteri 4). Üç okunabilir desene bölündü — iyelik · yön ·
    #    uzuv — ve 313-manifestlik korpusta ölçüldü:
    #      kriter 1 (13 gerçek geçişin 13'ü YAŞAMALI) → **12/13, DÜŞTÜ**
    #      kriter 2 (yanlış-pozitif ÖLMELİ)           → **yaşadı, DÜŞTÜ**
    #    Kaybedilen geçiş: `lissom/W_O65GVbLQM` — tek eşleşmesi
    #    "let's turn for a sec so we can showcase this"; yön de uzuv de
    #    iyelik de yok, çünkü hareket İNSTRÜKSİYONEL değil SUNUMSAL.
    #    Ölmeyen yanlış-pozitif: `ostinato/2mPS-2guHVo` — "we're gonna
    #    move UP a half step" bir YÖN sözcüğü kullanıyor ama hareket eden
    #    şey PERDE, gövde değil.
    #
    #    SEBEP TEK CÜMLEYLE: fark SÖZDİZİMSEL DEĞİL ANLAMSAL. "move up (a
    #    half step)" ile "move up (the body)" aynı sözdizimidir; ayrımı
    #    taşıyan şey ismin ALANIDIR. Hiçbir olumlu sözdizim kuralı bunu
    #    göremez — olumsuz ileribakış da göremedi (geri-izleme "the LEFT
    #    arm"ı eliyordu). İki yol da ölçüldü; takas ölçülmüş-imkânsızlıkla
    #    kapandı.
    # KAYNAK DÜZEYİNDE tek yanlış-pozitif kalıyor (ilk sayımım İKİ demişti
    # ve YANLIŞTI — uygunluk CÜMLE değil KAYNAK düzeyindedir):
    #   ostinato/2mPS-2guHVo → "we move this five down a half step" ve
    #     "we're gonna move up a half step": ikisi de PERDE hareketi. Kaynak
    #     gerçekten yanlış-pozitif.
    #   ostinato/D9hEN4wEwNU → "if we raise the bench up" spurious AMA aynı
    #     kaynakta "as we lean back and forth" var: piyanistin taburede
    #     salınımı, GERÇEK gövde hareketi. Kaynak HAKLI olarak uygun.
    # `MOVEMENT_CUE_MARKERS` bunu `your <uzuv>` ŞARTIYLA çözüyor; bu ailede
    # aynısı YAPILAMAZ, çünkü ailenin ÇEKİRDEK vakasının ("we're going to
    # step back") hiç uzvu yok — uzuv şart koşmak tam onu öldürürdü.
    # Olumsuz-ileribakışla denendi ve BIRAKILDI: geri-izleme "the LEFT arm"da
    # "left"i nesne sayıp meşru bir uzuv ifadesini eliyordu; yığılmış
    # ileribakışlar okunamaz ve sessizce yanlış oluyor. Yapısal alternatif
    # (uzuv VEYA iyelik VEYA çıplak yön ŞART — olumlu kural) ailenin kapsamını
    # değiştirir, o yüzden tek başıma seçmedim.
)

#: Aktif/kendi-üretimli hareket işaretleri.
ACTIVE_MARKERS = (
    r"\bactive range of motion\b", r"\bAROM\b", r"\bactively\b",
    r"\bfollow along\b", r"\bfollow-along\b",
    r"\b(raise|lift|reach|bring) your\b", r"\byour turn\b",
    r"\bdo (this|it) (with me|yourself)\b", r"\bon your own\b",
    r"\bexercise demo(nstration)?\b",
) + POSTURE_CUE_MARKERS + MOVEMENT_CUE_MARKERS + FIRST_PERSON_PLURAL_CUE_MARKERS

#: BİRİNCİ-ŞAHIS GÖSTERİM sınıfı (J-058/M-F-104): eğitmen kendi hareketini
#: birinci şahısla anlatır ("I throw the fist away from me", "here is the
#: first punch"). ACTIVE_MARKERS'taki kalıplardan (ör. "raise YOUR") farklı
#: bir REGISTER — o izleyiciye komut verir, bu gösterenin KENDİ hareketini
#: anlatır; ikisi de aktif-icra kanıtı, farklı dilbilgisel kalıplar. Ölçülen
#: kör nokta: frolov'un jab transkripti ("I throw the fist away from me...",
#: "here is the first punch") bu sınıf olmadan `unknown`da kalıyordu (J-058).
#:
#: GÜVENLİK (M-F-43 fail-closed disiplini): bu sınıf pasif tespitini
#: EZEMEZ. "I will/I'll move/lift/take" ve "let me move/lift/take" ZATEN
#: PASSIVE_MARKERS'ta ve `classify()` pasifi aktiften ÖNCE kontrol eder
#: (adım 1) — pasif işaret varsa bu sınıf hiç görülmeden PASSIVE kazanır.
#: Fiil listesi kasıtlı GENİŞ AMA SINIRLI: ailenin gövde-hareketi
#: disiplinlerinde (dövüş/PT/dans/genel) ortak gösterim fiilleri — rastgele
#: bir fiil hunısı değil, "kendi hareketini anlatan birinci şahıs" sınıfı.
#: DÜZENLİ SÜPÜRME ZORUNLU (M-F-104): yeni bir kaynak sınıfı eklenince aile
#: genelindeki mevcut transkript korpusuna karşı regresyon koşulmalı — bkz.
#: `tests/rom_mode_corpus_sweep.py`.
FIRST_PERSON_DEMO_MARKERS = (
    r"\bI(?:'m| am)? (?:throw(?:ing|s)?|punch(?:ing|es)?|kick(?:ing|s)?|"
    r"jump(?:ing|s)?|swing(?:ing|s)?|step(?:ping|s)?|pivot(?:ing|s)?|"
    r"reach(?:ing|es)?|extend(?:ing|s)?|drive(?:s)?|push(?:ing|es)?|"
    r"pull(?:ing|s)?|rotate(?:s)?|bend(?:ing|s)?|twist(?:ing|s)?|"
    r"lean(?:ing|s)?)\b",
)

#: ZAYIF AKTİF işaret (M-F-208 / JabLab J-089) — `WEAK_PASSIVE_MARKERS`in
#: aynadaki hâli ve AYNI kural: **tek başına mod belirlemez.**
#:
#: `here's the ...` bu sınıfın kurucu üyesi ve buraya BİR ÖLÇÜMLE indi.
#: Kalıp `FIRST_PERSON_DEMO_MARKERS`e J-058'de eklenmişti (frolov'un jab
#: transkriptindeki "here is the first punch" için) — ama ailenin diğer tüm
#: kalıplarının aksine **hareket fiili İSTEMİYOR**: "here's the thing",
#: "here's the deal", "here's the problem" de eşleşir.
#:
#: ÖLÇÜLEN VAKA (JabLab `lqvdxbOyTgU`, protips4u uppercut dersi): ailenin
#: fiil gerektiren kalıplarından **SIFIR** eşleşme; tek eşleşme
#: *"this is the lead uppercut, and here's the other one"*. Yani bir kaynağın
#: REFERANS-UYGUNLUĞU, hareket kanıtı olmayan tek bir sunum ifadesine
#: dayanıyordu.
#:
#: Kademe KOMBİNASYON EŞİĞİ İÇERMEZ ("≥2 zayıf yeter" gibi bir kural
#: ölçülmemiş olurdu): zayıf işaret tek başına SIFIR, güçlünün yanında yalnız
#: bağlamdır. Salt-zayıf kaynak fail-closed `unknown` kalır ve sebebi İSİMLE
#: yazılır — sessizce düşmez.
WEAK_ACTIVE_MARKERS = (
    r"\bhere(?:'s| is| comes)\s+(?:the|your|my)\b",
)


@dataclass
class RomVerdict:
    mode: str
    active_hits: list[str] = field(default_factory=list)
    passive_hits: list[str] = field(default_factory=list)
    reason: str = ""
    #: M-F-45: pasif icra bu harekette biyomekanik olarak mümkün mü. `False`
    #: ise M-F-43'ün koruduğu tehdit YAPISAL OLARAK yoktur (kimse birine pasif
    #: squat yaptıramaz), bu yüzden `unknown` kaynak referansa girebilir.
    passive_execution_possible: bool = True
    #: Sınıflandırmanın hangi metinlere baktığı — transkript yoksa kanıt zayıf
    #: demektir ve bunu gizlemek yerine kaydediyoruz.
    sources_seen: list[str] = field(default_factory=list)
    #: M-F-208 kademesi: bulunan ama TEK BAŞINA hüküm taşımayan aktif
    #: işaretler. Kaydediliyor ki "hiç işaret yoktu" ile "yalnız zayıf işaret
    #: vardı" AYIRT EDİLEBİLSİN — ikincisi bir sonraki turda tekrar
    #: araştırılmasın diye.
    weak_active_hits: list[str] = field(default_factory=list)

    @property
    def reference_eligible(self) -> bool:
        if self.mode == ACTIVE:
            return True
        # `passive` HER ZAMAN dışarıda: pasif icra imkânsız sanılan bir
        # harekette pasif işaret bulunduysa, kaynak muhtemelen o hareketi
        # göstermiyordur — bu bir uygunluk değil, eşleşme sorunudur.
        if self.mode == PASSIVE:
            return False
        return not self.passive_execution_possible

    def to_detail(self) -> dict:
        return {
            "romMode": self.mode,
            "romActiveHits": self.active_hits,
            "romPassiveHits": self.passive_hits,
            "romWeakActiveHits": self.weak_active_hits,
            "romReason": self.reason,
            "romSourcesSeen": self.sources_seen,
            "passiveExecutionPossible": self.passive_execution_possible,
            "referenceEligible": self.reference_eligible,
        }


def _hits(patterns: tuple[str, ...], text: str) -> list[str]:
    return sorted({m.group(0).lower()
                   for p in patterns
                   for m in re.finditer(p, text, flags=re.IGNORECASE)})


def classify(
    *, title: str = "", description: str = "", transcript: str = "",
    extra_passive: tuple[str, ...] = (), extra_active: tuple[str, ...] = (),
    passive_execution_possible: bool = True,
) -> RomVerdict:
    """Kaynağın gösterim modunu metinden sınıflandır.

    Karar sırası ve gerekçeleri:
      1. Pasif işaret varsa → PASSIVE. Aktif işaret de olsa fark etmez: karışık
         videoda hangi tekrarın hangi modda olduğunu metinden bilemeyiz ve
         yanlış tarafta hata yapmak referansı kirletir. Lissom'un
         "Active, Passive and Resisted" başlıklı klibi tam bu vakadır.
      2. Yalnız aktif işaret varsa → ACTIVE.
      3. Hiçbiri yoksa → UNKNOWN (referansa giremez).
    """
    sources = [n for n, v in (("title", title), ("description", description),
                              ("transcript", transcript)) if v.strip()]
    blob = "\n".join((title, description, transcript))
    passive = _hits(PASSIVE_MARKERS + tuple(extra_passive), blob)
    weak = _hits(WEAK_PASSIVE_MARKERS, blob)
    active = _hits(
        ACTIVE_MARKERS + FIRST_PERSON_DEMO_MARKERS + tuple(extra_active), blob)
    # Zayıf-aktif AYRI toplanır: `active`a karışsaydı tek başına ACTIVE
    # üretirdi — düzeltilen kusur tam buydu.
    weak_active = _hits(WEAK_ACTIVE_MARKERS, blob)

    if passive:
        reason = ("pasif/klinisyen işareti bulundu"
                  + (" — aktif işaret de var ama karışık kaynakta hangi "
                     "tekrarın hangi modda olduğu metinden bilinemez"
                     if active else ""))
        return RomVerdict(
            PASSIVE, active, passive + weak, reason,
            sources_seen=sources,
            passive_execution_possible=passive_execution_possible,
        )
    if active:
        return RomVerdict(
            ACTIVE, active, weak,
            "yalnız aktif işaret"
            + (f"; zayıf işaret {weak} tek başına pasif SAYILMAZ" if weak else "")
            + (f"; zayıf-aktif {weak_active} güçlü işaretin yanında bağlam"
               if weak_active else ""),
            sources_seen=sources,
            weak_active_hits=weak_active,
            passive_execution_possible=passive_execution_possible,
        )
    return RomVerdict(
        UNKNOWN, active, weak,
        # Salt-zayıf kaynak SESSİZCE düşmez: sebebi isimle yazılır, yoksa
        # "hiçbir işaret yok" ile "yalnız zayıf işaret var" ayırt edilemez.
        (f"YALNIZ ZAYIF-AKTİF işaret {weak_active} — tek başına aktif "
         "SAYILMAZ (M-F-208 kademesi); hareket-fiilli güçlü işaret yok"
         if weak_active else "") or
        ("hiçbir mod işareti yok; pasif icra bu harekette biyomekanik olarak "
         "MÜMKÜN DEĞİL — tehdit yapısal olarak yok, referansa girebilir (M-F-45)"
         if not passive_execution_possible else
         "hiçbir mod işareti yok — fail-closed: referansa giremez")
        + ("" if "transcript" in sources
           else " (TRANSKRİPT YOK: sınıflandırma yalnız başlık/açıklamaya "
                "dayanıyor, kanıt zayıf)"),
        sources_seen=sources,
        weak_active_hits=weak_active,
        passive_execution_possible=passive_execution_possible,
    )
