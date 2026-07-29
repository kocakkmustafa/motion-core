"""Uygunluğu KARAR ANINDA kaynağın GÜNCEL kaydından çözer (M-F-138).

AİLE KURALI: **uygunluk türev artefaktta BAYATLAR.** Kapı, karar anında
kaynağın GÜNCEL kaydından çözer; türev artefaktın taşıdığı `referenceEligible`
yalnız TARİHÇEDİR.

ÖLÇÜLEN KUSUR (J-064): `segment_punches` gibi kesiciler pencere fixture'ını
üretirken kaynağın provenance'ını olduğu gibi KOPYALIYOR — yani uygunluğu
KESİM ANINDA snapshot'lıyor. Kaynağın sınıflandırması sonradan değişse bile
eski pencereler ESKİ değeri taşımaya devam ediyor ve kanonik kapıdan geçiyor.
Jab referansı tam bu yüzden bir kez "geçti": pencereler kaynaklar
`referenceEligible` alanını KAZANMADAN önce kesilmişti; kaynaklar
sınıflandırılıp iki tanesi bloklandıktan sonra AYNI pencereler hâlâ
admissible görünüyordu. Yeniden kesince reddedildi.

Bu bir tesadüf değil KAPI-ATLATMA YOLUDUR: uygunluk kuralını (M-F-43)
sessizce iptal etmenin en kolay yolu, kuralı kaynağa uygulamak ama kapıya
TÜREV bir kopyayı sunmaktır.

NİYE SNAPSHOT SİLİNMİYOR: kesim anındaki değer, o pencerenin hangi bilgiyle
üretildiğini söyleyen gerçek bir tarihsel kayıttır. Silmek, geçmişi
yeniden yazmak olurdu. Bu yüzden snapshot `eligibilitySnapshot` altına
TAŞINIR ve karar alanı TAZE değerle DOLDURULUR — ikisi ayrı ayrı okunabilir
kalır ve fark görünür olur.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

#: Kaynağın güncel kaydından okunacak, uygunluğu belirleyen alanlar.
#: `referenceEligible` kapının okuduğu alan; diğerleri onun GEREKÇESİ ve
#: birlikte tazelenmeleri şart — taze karar + bayat gerekçe, gerekçesiz
#: karardan daha kötüdür (neden reddedildiği yanlış okunur).
ELIGIBILITY_FIELDS = ("referenceEligible", "romMode",
                      "contextTags", "contextSource")


class StaleEligibilityError(RuntimeError):
    """Kaynak kaydı bulunamadı — uygunluk TAZELENEMEZ.

    Sessizce bayat değerle devam etmek, kuralın kendisini iptal eder; bu
    yüzden fail-closed: çağıran ya kaynağı gösterir ya pencereyi dışlar.
    """


def source_eligibility(manifest_path: str | Path) -> dict[str, Any]:
    """Kaynağın GÜNCEL uygunluk kaydını manifestten okur."""
    p = Path(manifest_path)
    if not p.exists():
        raise StaleEligibilityError(
            f"kaynak manifesti yok: {p} — uygunluk tazelenemez, pencere "
            f"kapıya SUNULMAMALI (M-F-138 fail-closed)")
    m = json.loads(p.read_text(encoding="utf-8"))
    # Manifest snake_case, provenance camelCase taşır.
    return {
        "referenceEligible": m.get("reference_eligible"),
        "romMode": m.get("rom_mode"),
        "contextTags": m.get("context_tags") or [],
        "contextSource": m.get("context_source"),
    }


def _differs(field: str, old: Any, new: Any) -> bool:
    """Alan bazında GERÇEK fark var mı.

    `contextTags` için YOK ile BOŞ LİSTE aynı şeydir — ilk sürüm bunları
    farklı sayıp her tazelemede "değişti" diyordu ve uyarı gürültüye
    dönüşüyordu (gürültü, uyarının kendisini işlevsiz kılar).

    `referenceEligible` için ise YOK ile `False` AYNI DEĞİLDİR ve bu ayrım
    J-064'ün tam çekirdeği: alanın YOKLUĞU "henüz sınıflandırılmadı"
    (`unattested`, override edilebilir), `False` ise "BLOKLU"
    (`ineligible`, override YOK). İkisini birleştirmek, bloklanmış bir
    kaynağı yalnızca sınıflandırılmamış saymak olurdu.
    """
    if field == "contextTags":
        return (old or []) != (new or [])
    return old != new


def refresh_provenance(
    provenance: dict[str, Any],
    manifest_path: str | Path,
) -> dict[str, Any]:
    """Türev pencerenin provenance'ındaki uygunluğu kaynaktan TAZELER.

    Kesim anındaki değerler `eligibilitySnapshot` altına taşınır (tarihçe),
    karar alanları kaynağın güncel kaydıyla doldurulur. Fark varsa
    `eligibilityRefreshed: true` işaretlenir — sessiz bir düzeltme,
    düzeltilmemiş olmakla aynı riski taşır (kimse ne değiştiğini bilmez).
    """
    fresh = source_eligibility(manifest_path)
    out = dict(provenance)

    snapshot = {k: provenance.get(k) for k in ELIGIBILITY_FIELDS
                if k in provenance}
    changed = any(_differs(k, provenance.get(k), fresh[k])
                  for k in ELIGIBILITY_FIELDS)

    out.update(fresh)
    if snapshot:
        out["eligibilitySnapshot"] = {
            **snapshot,
            "$doc": ("KESİM ANINDAKİ değerler — yalnız TARİHÇE (M-F-138). "
                     "Kapı bu alanları OKUMAZ; karar kaynağın güncel "
                     "kaydından gelir."),
        }
    out["eligibilityRefreshed"] = changed
    if changed:
        out["$eligibilityRefreshedWhy"] = (
            "Kaynağın uygunluk kaydı, bu pencere kesildikten SONRA değişti. "
            "Kapıya TAZE değer sunuluyor; kesim anındaki değer "
            "eligibilitySnapshot altında duruyor.")
    return out


def refresh_fixture_file(
    fixture_path: str | Path,
    manifest_path: str | Path,
) -> bool:
    """Pencere fixture'ını yerinde tazeler. Değişiklik olduysa `True`."""
    p = Path(fixture_path)
    doc = json.loads(p.read_text(encoding="utf-8"))
    before = doc.get("provenance", {})
    after = refresh_provenance(before, manifest_path)
    doc["provenance"] = after
    p.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
    return bool(after.get("eligibilityRefreshed"))
