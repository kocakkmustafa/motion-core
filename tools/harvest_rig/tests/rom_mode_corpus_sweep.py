"""M-F-104/M-O-54: rom_mode.py'ye yeni işaret sınıfı eklenince AİLE-GENELİ
regresyon süpürmesi. Kanıt yükümlülüğü: hiçbir kaynak, YENİ sınıf eklenince
(aynı kod tabanında ESKİ-hâl vs YENİ-hâl kıyası — manifest'teki BAYAT kayıtlı
değere karşı DEĞİL, çünkü o çoktan başka iyileştirmelerle kaymış olabilir)
passive'den active'e DÖNMEMELİ.

HANGİ AİLE süpürülüyor: `--family` ile seçilir. Sınıf adının parametre
olması bir kolaylık değil ZORUNLULUK — her yeni demet (birinci-şahıs,
duruş-yönergesi, hareket-yönergesi) KENDİ izole kıyasını hak eder; hepsini
birden kapatıp açmak, hangi demetin hangi geçişi ürettiğini ölçülemez kılar.

Koşum: fixture_pipeline venv'iyle (mediapipe gerekmez, yalnız stdlib+re).
  .venv/bin/python tests/rom_mode_corpus_sweep.py --family MOVEMENT_CUE_MARKERS
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
import rom_mode  # noqa: E402

HARVEST_ROOT = Path.home() / "motion-harvest"
APPS = ["ostinato", "lissom", "jablab", "gravita", "gravita-squat", "choreia"]

#: Süpürülebilir demetler. `ACTIVE_MARKERS` bunları İÇERDİĞİ için, bir demeti
#: devre dışı bırakmak onu ACTIVE_MARKERS'tan da çıkarmayı gerektirir —
#: yoksa "kapattım" sanılan sınıf hâlâ isabet eder ve süpürme SESSİZCE
#: hiçbir şey ölçmez (bu tuzağa bir kez düştüm, J-059).
SWEEPABLE = ("FIRST_PERSON_DEMO_MARKERS", "POSTURE_CUE_MARKERS",
             "MOVEMENT_CUE_MARKERS")


def _disable(family: str):
    """Demeti hem kendi adından hem ACTIVE_MARKERS'tan çıkarır."""
    saved_family = getattr(rom_mode, family)
    saved_active = rom_mode.ACTIVE_MARKERS
    setattr(rom_mode, family, ())
    rom_mode.ACTIVE_MARKERS = tuple(
        p for p in rom_mode.ACTIVE_MARKERS if p not in saved_family)
    return saved_family, saved_active


def _restore(family: str, saved_family, saved_active) -> None:
    setattr(rom_mode, family, saved_family)
    rom_mode.ACTIVE_MARKERS = saved_active


def load_transcript(app: str, video_id: str) -> str:
    p = HARVEST_ROOT / app / "transcripts" / f"{video_id}.transcript.json"
    if not p.exists():
        return ""
    try:
        segs = json.loads(p.read_text(encoding="utf-8"))
        return " ".join(s.get("text", "") for s in segs)
    except Exception:
        return ""


def main() -> int:
    family = "FIRST_PERSON_DEMO_MARKERS"
    for i, a in enumerate(sys.argv):
        if a == "--family" and i + 1 < len(sys.argv):
            family = sys.argv[i + 1]
    if family not in SWEEPABLE:
        print(f"bilinmeyen demet: {family}\nseçenekler: {', '.join(SWEEPABLE)}")
        return 64
    print(f"süpürülen demet: {family}\n")
    total = 0
    flips_dangerous: list[tuple[str, str, str, str, list]] = []
    flips_benign: list[tuple[str, str, str, str]] = []
    unchanged = 0

    for app in APPS:
        manifest_dir = HARVEST_ROOT / app / "manifests"
        if not manifest_dir.exists():
            continue
        for mp in sorted(manifest_dir.glob("*.json")):
            m = json.loads(mp.read_text(encoding="utf-8"))
            video_id = m.get("video_id", mp.stem)
            title = m.get("title") or ""
            desc = m.get("description") or ""
            transcript = load_transcript(app, video_id)

            # ESKİ-hâl: aynı kod tabanı, yalnız SEÇİLEN sınıf devre dışı.
            sf, sa = _disable(family)
            old = rom_mode.classify(title=title, description=desc,
                                     transcript=transcript)
            _restore(family, sf, sa)
            # YENİ-hâl.
            new = rom_mode.classify(title=title, description=desc,
                                     transcript=transcript)

            total += 1
            if old.mode == new.mode:
                unchanged += 1
                continue
            if old.mode == "passive" and new.mode == "active":
                flips_dangerous.append(
                    (app, video_id, old.mode, new.mode, new.active_hits))
            else:
                flips_benign.append((app, video_id, old.mode, new.mode))

    print(f"toplam manifest: {total}  değişmeyen: {unchanged}")
    print(f"zararsız değişim (yalnız YENİ sınıfın etkisiyle, passive->active "
          f"HARİÇ): {len(flips_benign)}")
    for app, vid, old, new in flips_benign:
        print(f"  {app}/{vid}: {old} -> {new}")
    print(f"\nTEHLİKELİ değişim (YENİ sınıf yüzünden passive->active): "
          f"{len(flips_dangerous)}")
    for app, vid, old, new, hits in flips_dangerous:
        print(f"  ❌ {app}/{vid}: {old} -> {new} (yeni işaret: {hits})")

    if flips_dangerous:
        print("\nSÜPÜRME BAŞARISIZ — yeni sınıf fazla geniş, daraltılmalı.")
        return 1
    print("\nSÜPÜRME TEMİZ — yeni sınıf hiçbir passive kaynağı active'e "
          "çevirmiyor (aynı kod tabanında izole karşılaştırıldı).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
