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

#: Aktif/kendi-üretimli hareket işaretleri.
ACTIVE_MARKERS = (
    r"\bactive range of motion\b", r"\bAROM\b", r"\bactively\b",
    r"\bfollow along\b", r"\bfollow-along\b",
    r"\b(raise|lift|reach|bring) your\b", r"\byour turn\b",
    r"\bdo (this|it) (with me|yourself)\b", r"\bon your own\b",
    r"\bexercise demo(nstration)?\b",
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
    active = _hits(ACTIVE_MARKERS + tuple(extra_active), blob)

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
            "yalnız aktif işaret" + (f"; zayıf işaret {weak} tek başına pasif "
                                     "SAYILMAZ" if weak else ""),
            sources_seen=sources,
            passive_execution_possible=passive_execution_possible,
        )
    return RomVerdict(
        UNKNOWN, active, weak,
        ("hiçbir mod işareti yok; pasif icra bu harekette biyomekanik olarak "
         "MÜMKÜN DEĞİL — tehdit yapısal olarak yok, referansa girebilir (M-F-45)"
         if not passive_execution_possible else
         "hiçbir mod işareti yok — fail-closed: referansa giremez")
        + ("" if "transcript" in sources
           else " (TRANSKRİPT YOK: sınıflandırma yalnız başlık/açıklamaya "
                "dayanıyor, kanıt zayıf)"),
        sources_seen=sources,
        passive_execution_possible=passive_execution_possible,
    )
