"""M-F-138: türev pencerede uygunluk BAYATLAMASI — önce-kırmızı-sonra-yeşil.

Bu dosyanın ilk testi KUSURU üretir: kesim anında kopyalanmış bir uygunluk
değeri, kaynak sonradan bloklanmış olsa bile kapıdan geçmeye devam eder.
İkinci test aynı senaryonun tazelenmiş hâlini sınar. Sıra bilinçli: düzeltme
testinin tek başına yeşil olması, kusurun HİÇ var olmadığı durumdan ayırt
edilemez.

Koşum:  .venv/bin/python tests/test_eligibility.py
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from eligibility import (  # noqa: E402
    StaleEligibilityError,
    refresh_fixture_file,
    refresh_provenance,
)

_fails: list[str] = []


def check(cond: bool, label: str) -> None:
    print(("  ✓ " if cond else "  ✗ ") + label)
    if not cond:
        _fails.append(label)


def _workspace(tmp: Path, *, source_eligible: bool, source_mode: str,
               window_eligible: bool, window_mode: str) -> tuple[Path, Path]:
    """Kaynak manifesti BLOKLU, pencere fixture'ı ESKİ (uygun) hâlde."""
    manifest = tmp / "manifests" / "SRC.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({
        "video_id": "SRC",
        "reference_eligible": source_eligible,
        "rom_mode": source_mode,
        "context_tags": [],
        "context_source": None,
    }), encoding="utf-8")

    window = tmp / "SRC_jab_1.json"
    window.write_text(json.dumps({
        "frames": [],
        "provenance": {
            "sourceUrl": "https://example/SRC",
            "referenceEligible": window_eligible,
            "romMode": window_mode,
            "windowRule": {"mechanism": "punch_fsm"},
        },
    }), encoding="utf-8")
    return manifest, window


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        print("KIRMIZI: tazeleme YOKKEN bayat değer kapıdan geçer")
        manifest, window = _workspace(
            tmp, source_eligible=False, source_mode="unknown",
            window_eligible=True, window_mode="active")
        raw = json.loads(window.read_text())["provenance"]
        # Kesicinin bugün yaptığı şey: provenance'ı OLDUĞU GİBİ taşımak.
        check(raw["referenceEligible"] is True,
              "pencere ESKİ uygunluğu taşıyor (True) — kaynak BLOKLU olmasına "
              "rağmen; kapı-atlatma yolu bu")

        print("\nYEŞİL: tazeleme kaynağın GÜNCEL kaydını kapıya sunar")
        fresh = refresh_provenance(raw, manifest)
        check(fresh["referenceEligible"] is False,
              "tazelenmiş provenance kaynağın BLOKLU hâlini taşıyor")
        check(fresh["romMode"] == "unknown", "romMode da tazelendi")
        check(fresh["eligibilityRefreshed"] is True,
              "değişiklik İŞARETLİ (sessiz düzeltme = düzeltilmemiş kadar riskli)")
        check("$eligibilityRefreshedWhy" in fresh, "değişimin sebebi yazılı")

        print("\nSNAPSHOT tarihçe olarak KORUNUYOR (geçmiş yeniden yazılmaz)")
        snap = fresh["eligibilitySnapshot"]
        check(snap["referenceEligible"] is True,
              "kesim anındaki değer snapshot'ta duruyor")
        check(snap["romMode"] == "active", "kesim anındaki romMode duruyor")
        check("$doc" in snap and "OKUMAZ" in snap["$doc"],
              "snapshot'ın kapı tarafından okunmadığı yazılı")

        print("\nDEĞİŞİKLİK YOKSA gürültü de yok")
        manifest2, window2 = _workspace(
            tmp / "b", source_eligible=True, source_mode="active",
            window_eligible=True, window_mode="active")
        same = refresh_provenance(
            json.loads(window2.read_text())["provenance"], manifest2)
        check(same["eligibilityRefreshed"] is False,
              "kaynak ile pencere uyuşuyorsa refreshed=False")
        check("$eligibilityRefreshedWhy" not in same,
              "gereksiz gerekçe alanı yazılmıyor")

        print("\nDİĞER provenance alanları KORUNUYOR")
        check(fresh["sourceUrl"] == "https://example/SRC", "sourceUrl duruyor")
        check(fresh["windowRule"]["mechanism"] == "punch_fsm",
              "windowRule duruyor (kesim mekanizması tarihçesi)")

        print("\nFAIL-CLOSED: kaynak kaydı yoksa SESSİZCE devam EDİLMEZ")
        try:
            refresh_provenance(raw, tmp / "manifests" / "YOK.json")
            check(False, "eksik manifestte hata FIRLATILMALI")
        except StaleEligibilityError as e:
            check("tazelenemez" in str(e),
                  "eksik kaynak kaydı isimli hata veriyor (fail-closed)")

        print("\nDOSYA ÜZERİNDE tazeleme (kesicinin çağıracağı yol)")
        changed = refresh_fixture_file(window, manifest)
        check(changed is True, "dosya tazelemesi değişiklik bildirdi")
        reread = json.loads(window.read_text())["provenance"]
        check(reread["referenceEligible"] is False,
              "diskteki pencere artık BLOKLU değeri taşıyor")
        check(reread["eligibilitySnapshot"]["referenceEligible"] is True,
              "diskteki snapshot tarihçeyi koruyor")

    print()
    if _fails:
        print(f"{len(_fails)} BAŞARISIZ:")
        for f in _fails:
            print("  -", f)
        return 1
    print("Hepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
