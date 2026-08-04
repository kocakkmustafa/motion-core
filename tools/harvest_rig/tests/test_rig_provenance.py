#!/usr/bin/env python
"""SINIFLANDIRICI PROVENANCE + bayat-rig nöbeti (M-F-206 / J-085).

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_rig_provenance.py

Neden test: J-085'te hasat, origin/main'in 3414 satır gerisindeki bir
ağaçtan koşuldu. Mevcut `rig_version()` damgası TERTEMİZ çıkıyordu
(takipli ✓ · motion-core ✓ · dirty=false ✓) — çünkü "hangi rig" sorusunu
yanıtlıyordu, "GÜNCEL Mİ" sorusunu değil. Bu dosya o boşluğun kapalı
kaldığını sınıyor.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest as M  # noqa: E402

FAILURES: list[str] = []


def _check(label: str, cond: bool) -> None:
    if not cond:
        FAILURES.append(label)


def main() -> int:
    print("[1] rig_version() bayatlık alanlarını TAŞIYOR")
    v = M.rig_version()
    for key in ("behindOriginMain", "originMainKnown", "branch"):
        _check(f"rig_version'da '{key}' yok", key in v or v.get("vendored"))

    print("[2] BAYAT rig için uyarı ÜRETİLİR ve sayıyı söyler")
    real = M.rig_version
    M.rig_version = lambda: {"sha": "deadbeef" * 5, "dirty": False,
                             "vendored": False, "branch": "feat/baska-oturum",
                             "behindOriginMain": 3414, "originMainKnown": True}
    w = M.rig_staleness_warning()
    _check("bayat rigde uyarı yok", w is not None)
    _check("eksik commit sayısı uyarıda yok", w is not None and "3414" in w)
    _check("dal adı uyarıda yok", w is not None and "feat/baska-oturum" in w)

    print("[3] GÜNCEL rig SESSİZ kalır (uyarı enflasyonu yok)")
    M.rig_version = lambda: {"sha": "a" * 40, "dirty": False, "vendored": False,
                             "branch": "main", "behindOriginMain": 0,
                             "originMainKnown": True}
    _check("güncel rigde gereksiz uyarı", M.rig_staleness_warning() is None)

    print("[4] origin/main BİLİNMİYORSA 0 ile karıştırılmaz")
    # Bilinmiyor ≠ güncel. Sessiz kalmak, doğrulanmamışı doğrulanmış
    # göstermek olurdu.
    M.rig_version = lambda: {"sha": "b" * 40, "dirty": False, "vendored": False,
                             "branch": "main", "behindOriginMain": None,
                             "originMainKnown": False}
    w4 = M.rig_staleness_warning()
    _check("bilinmiyorken sessiz kaldı", w4 is not None)
    _check("bilinmiyor uyarısı DOĞRULANAMADI demiyor",
           w4 is not None and "DOĞRULANAMADI" in w4)

    print("[5] KARAR kaydı classifiedBy damgası taşır, MEKANİK kayıt taşımaz")
    M.rig_version = lambda: {"sha": "c" * 40, "dirty": True, "vendored": False,
                             "branch": "wt", "behindOriginMain": 7,
                             "originMainKnown": True}
    m = M.HarvestManifest.start(app="jablab", video_id="x", source_url="u")
    m.record("romMode", "active", romActiveHits=["i throw"])
    m.record("extract", "ok", fixture="x.full.json")
    rom = [s for s in m.stages if s.stage == "romMode"][-1]
    ext = [s for s in m.stages if s.stage == "extract"][-1]
    cb = rom.detail.get("classifiedBy")
    _check("karar kaydında classifiedBy yok", isinstance(cb, dict))
    _check("classifiedBy bayatlığı taşımıyor",
           isinstance(cb, dict) and cb.get("behindOriginMain") == 7)
    _check("classifiedBy dirty taşımıyor",
           isinstance(cb, dict) and cb.get("dirty") is True)
    # Mekanik aşama damgalanmaz: aynı girdi → aynı çıktı, sürümden bağımsız.
    _check("mekanik kayıt gereksiz damgalandı",
           "classifiedBy" not in ext.detail)

    print("[6] çağıran AÇIKÇA verdiyse üzerine YAZILMAZ")
    # M-F-138 tazelemesi kendi damgasını koyar; otomatik damga onu ezerse
    # "hangi sürüm tazeledi" bilgisi kaybolur.
    m2 = M.HarvestManifest.start(app="jablab", video_id="y", source_url="u")
    m2.record("romMode", "active", classifiedBy={"sha": "elle", "dirty": False})
    _check("elle verilen damga ezildi",
           m2.stages[-1].detail["classifiedBy"]["sha"] == "elle")

    print("[7] İLERİ/AYRIK dal (behind=0 ama soy-dışı) SESSİZ GEÇMEZ — M-F-238")
    # C-114 sınıfı: `HEAD..origin/main` sayımı ardıl dalda 0 döner; yalnız
    # sayıma bakan nöbet, merge edilmemiş kuralların kararlarını "güncel"
    # damgalar. Soy alanı açıkça False ise uyarı ŞART.
    M.rig_version = lambda: {"sha": "d" * 40, "dirty": False, "vendored": False,
                             "branch": "feat/unmerged", "behindOriginMain": 0,
                             "originMainKnown": True, "onMainLineage": False}
    w7 = M.rig_staleness_warning()
    _check("ileri/ayrık dalda uyarı yok", w7 is not None)
    _check("ileri/ayrık uyarısı ATASI DEĞİL demiyor",
           w7 is not None and "ATASI DEĞİL" in w7)
    _check("ileri/ayrık uyarısı dal adını söylemiyor",
           w7 is not None and "feat/unmerged" in w7)

    print("[8] main-soyunda behind=0 SESSİZ kalır (ayırt-edicilik ikizi)")
    # [7]'nin pozitif ikizi: uyarı, soy-içi güncel ağaçta SUSMALI — susmuyorsa
    # nöbet ayırt etmiyor, gürültü üretiyor demektir.
    M.rig_version = lambda: {"sha": "e" * 40, "dirty": False, "vendored": False,
                             "branch": "main", "behindOriginMain": 0,
                             "originMainKnown": True, "onMainLineage": True}
    _check("soy-içi güncel ağaçta gereksiz uyarı",
           M.rig_staleness_warning() is None)

    M.rig_version = real

    if FAILURES:
        print(f"\n{len(FAILURES)} HATA")
        for f in FAILURES:
            print(f"  ❌ {f}")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
