#!/usr/bin/env python
"""ZAYIF-AKTİF KADEMESİ (M-F-208 / JabLab J-089).

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_weak_active_tier.py

Kural: **güçlü işaret (hareket-fiilli) uygunluğu TEK BAŞINA taşır · zayıf
işaret (sunumsal) ASLA tek başına taşımaz** — yalnız güçlünün yanında
bağlamdır. Kombinasyon eşiği YOK ("≥2 zayıf yeter" gibi bir kural
ölçülmemiş olurdu).

Ölçülen vaka: `lqvdxbOyTgU` (protips4u uppercut) — *"this is the lead
uppercut, and here's the other one"*; ailenin fiil gerektiren
kalıplarından SIFIR eşleşme. Aile süpürmesi aynı kusuru 3 app'te
5 kaynakta buldu (choreia 1 · jablab 1 · ostinato 3).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from rom_mode import ACTIVE, UNKNOWN, classify  # noqa: E402

FAILURES: list[str] = []


def _check(label: str, cond: bool) -> None:
    if not cond:
        FAILURES.append(label)


def main() -> int:
    print("[1] SALT zayıf işaret → UNKNOWN (uygunluk YOK)")
    # Gerçek korpustan: ostinato/qtZ7EUrsnR8'in tam ifadesi. Bir söylem
    # bağlacının referans-uygunluğu taşıması, düzeltilen kusurun ta kendisi.
    v = classify(transcript="So here is my suggestion. Open your hand a bit.")
    _check("salt zayıf ACTIVE üretti", v.mode == UNKNOWN)
    _check("salt zayıf uygun sayıldı", v.reference_eligible is False)
    _check("zayıf işaret kayda geçmedi", v.weak_active_hits == ["here is my"])
    # Sebep İSİMLİ olmalı: "hiç işaret yok" ile "yalnız zayıf var" farklı
    # iki durum ve ikincisi bir sonraki turda tekrar araştırılmasın.
    _check("sebep zayıf-aktifi söylemiyor", "ZAYIF-AKTİF" in v.reason)

    print("[2] ÇOK sayıda zayıf işaret de yetmez (kombinasyon eşiği YOK)")
    v2 = classify(transcript="Here's the thing. Here is my point. "
                             "Here comes the tricky part.")
    _check("zayıf yığını ACTIVE üretti", v2.mode == UNKNOWN)
    _check("zayıf yığını uygun sayıldı", v2.reference_eligible is False)
    _check("zayıf yığını eksik kaydedildi", len(v2.weak_active_hits) >= 2)

    print("[3] GÜÇLÜ işaret tek başına TAŞIR")
    v3 = classify(transcript="I'm throwing the jab from my chin.")
    _check("güçlü işaret taşımadı", v3.mode == ACTIVE)
    _check("güçlü işaret uygun değil", v3.reference_eligible is True)

    print("[4] güçlü + zayıf → ACTIVE, zayıf BAĞLAM olarak yazılır")
    v4 = classify(transcript="Here's the jab. I'm throwing it now.")
    _check("güçlü+zayıf ACTIVE değil", v4.mode == ACTIVE)
    _check("zayıf bağlam kaydedilmedi", v4.weak_active_hits != [])
    _check("gerekçe zayıfı bağlam demiyor", "bağlam" in v4.reason)

    print("[5] PASİF üstünlüğü BOZULMADI (M-F-43 fail-closed)")
    # Kademe yalnız aktif tarafı ilgilendirir; pasif işaret her şeyi yener.
    v5 = classify(transcript="Here's the arm. Let me lift your arm for you.")
    _check("pasif üstünlüğü bozuldu", v5.mode not in (ACTIVE, UNKNOWN))
    _check("pasif kaynak uygun sayıldı", v5.reference_eligible is False)

    print("[6] gerçek kusur vakası: sunumsal isimlendirme uygunluk TAŞIMAZ")
    v6 = classify(transcript="This is the uppercut, this is the lead "
                             "uppercut, and here's the other one.")
    _check("lqvdxbOyTgU vakası hâlâ uygun", v6.reference_eligible is False)

    if FAILURES:
        print(f"\n{len(FAILURES)} HATA")
        for f in FAILURES:
            print(f"  ❌ {f}")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
