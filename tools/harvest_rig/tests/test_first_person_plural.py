#!/usr/bin/env python
"""BİRİNCİ-ŞAHIS ÇOĞUL hareket yönergesi (M-F-213 sevki / JabLab J-090).

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_first_person_plural.py

Dans/grup öğretiminin ana kipi; ailenin iki mevcut sınıfı da kördü
(MOVEMENT_CUE ikinci şahıs · FIRST_PERSON_DEMO tekil birinci şahıs).

NEGATİF KORPUS ZORUNLU: bu ailenin tuzağı SUNUMSAL ÇOĞUL — "we're going to
talk about the hook" bir gündem cümlesidir, hareket değil. Aşağıdaki
negatiflerin her biri GERÇEK korpustan geldi ve her biri bir kapının
varlık sebebidir.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from rom_mode import (ACTIVE, FIRST_PERSON_PLURAL_CUE_MARKERS, UNKNOWN,  # noqa: E402
                      _hits, classify)

FAILURES: list[str] = []


def _expect(text: str, should_match: bool, why: str) -> None:
    hit = bool(_hits(FIRST_PERSON_PLURAL_CUE_MARKERS, text))
    if hit != should_match:
        FAILURES.append(f"[{why}] {text!r} → {'eşleşti' if hit else 'eşleşmedi'}")


def main() -> int:
    print("[1] POZİTİF — gerçek hareket yönergeleri")
    _expect("we're going to step back with our right on count one", True,
            "çekirdek vaka (choreia/FtZzjGsPxjg) — UZUV YOK, yön var")
    _expect("we're going to reach our arms out and twist to the right", True,
            "iyelik + uzuv (lissom/YghyGHKKojA)")
    _expect("we will step forward", True, "will kipi (choreia/SHGkSbJm2Iw)")
    _expect("we'll lift the ribs on inhalation", True,
            "belirteç + uzuv (ostinato/Ds8GKSp5GwE)")
    _expect("we are going to be stepping forward", True, "sürerlik kipi")
    _expect("let's turn to the left", True, "let's + yön")

    print("[2] NEGATİF — SUNUMSAL ÇOĞUL (beyaz liste bunları dışarıda tutar)")
    for t in ("we're going to talk about the hook",
              "we're going to look at the step back",
              "we'll cover the uppercut today",
              "let's go over the basics",
              "we're going to discuss footwork"):
        _expect(t, False, "sunumsal fiil listede YOK")

    print("[3] NEGATİF — MECAZ/İDYOM kapıları (üçü de ölçülmüş vaka)")
    _expect("we're going to move on to the next drill", False, "konu geçişi")
    _expect("let's step through the combination", False, "anlatım")
    _expect("we're going to jump right into the exercises", False,
            "başlama idyomu (ostinato/pwIO71FhP9g)")
    _expect("let's jump right into it", False, "başlama idyomu (choreia/AyzYABnWDEM)")
    _expect("we're going to move now to the next step", False,
            "araya sözcük giren konu geçişi (choreia/o6E9Ljr5o_c)")

    print("[4] sınıf UYGUNLUK üretir ve pasif üstünlüğünü BOZMAZ")
    v = classify(transcript="we're going to step back on count one")
    if v.mode != ACTIVE or v.reference_eligible is not True:
        FAILURES.append("çoğul yönerge ACTIVE/uygun üretmedi")
    p = classify(transcript="we're going to step back. let me lift your arm for you.")
    if p.mode == ACTIVE:
        FAILURES.append("pasif üstünlüğü bozuldu (M-F-43)")

    print("[5] ⚠️ BİLİNEN AÇIK: nesne↔gövde ayrımı YOK — kayıtlı yanlış-pozitif")
    # Bu iki satır bir HEDEF DEĞİL, ölçülmüş bir SINIRIN kaydı. Ailenin
    # çekirdek vakasının uzvu olmadığı için `your <uzuv>` şartı buraya
    # konulamıyor. Davranış değişirse bu test kırılır ve karar YENİDEN
    # gözden geçirilir — sessizce düzelmiş ya da kötüleşmiş olmasın.
    _expect("we move this five down a half step", True,
            "BİLİNEN AÇIK: nota, gövde değil (ostinato/2mPS-2guHVo)")
    _expect("if we raise the bench up", True,
            "BİLİNEN AÇIK: tabure, gövde değil (ostinato/D9hEN4wEwNU)")

    if FAILURES:
        print(f"\n{len(FAILURES)} HATA")
        for f in FAILURES:
            print(f"  ❌ {f}")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
