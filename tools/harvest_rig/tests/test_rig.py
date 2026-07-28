#!/usr/bin/env python
"""Hasat rig'i birim testleri — sentetik videolarla, ağ erişimsiz.

Koşum:
    ../fixture_pipeline/.venv/bin/python tests/test_rig.py
"""
from __future__ import annotations

import os
import sys
import tempfile

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harvest import hamming, perceptual_signature  # noqa: E402
from manifest import HarvestManifest  # noqa: E402
from triage import TriageThresholds, triage  # noqa: E402

FAILURES: list[str] = []


def check(cond: bool, msg: str) -> None:
    print(("  ✅ " if cond else "  ❌ ") + msg)
    if not cond:
        FAILURES.append(msg)


def write_video(path: str, *, seconds: float, size: tuple[int, int],
                fps: float = 24.0, scene_flip_every: float = 0.0,
                textured: bool = True, seed: int = 7) -> None:
    """Sentetik test videosu. scene_flip_every>0 -> sert kesmeli kurgu."""
    rng = np.random.default_rng(seed)
    w, h = size
    vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    n = int(seconds * fps)
    scene_a = rng.integers(0, 255, (h, w, 3), dtype=np.uint8)
    scene_b = np.zeros((h, w, 3), dtype=np.uint8)
    scene_b[:, :, 2] = 220  # bambaşka renk dünyası — kesme sinyali
    flat = np.full((h, w, 3), 128, dtype=np.uint8)
    for i in range(n):
        t = i / fps
        if not textured:
            frame = flat.copy()
        elif scene_flip_every > 0 and int(t / scene_flip_every) % 2 == 1:
            frame = scene_b.copy()
        else:
            frame = scene_a.copy()
        # küçük hareket — tamamen statik encode köşe durumlarına düşmesin
        cv2.circle(frame, (int(w / 2 + 20 * np.sin(t)), h // 2), 6,
                   (255, 255, 255), -1)
        if not textured:
            # odak-dışı kaynak simülasyonu: keskin kenar bırakma
            frame = cv2.GaussianBlur(frame, (31, 31), 12)
        vw.write(frame)
    vw.release()


def main() -> int:
    fast = TriageThresholds(min_duration_s=4.0)
    with tempfile.TemporaryDirectory() as td:
        long_ok = os.path.join(td, "ok.mp4")
        short = os.path.join(td, "short.mp4")
        vertical = os.path.join(td, "vertical.mp4")
        cutty = os.path.join(td, "cutty.mp4")
        blurry = os.path.join(td, "flat.mp4")

        write_video(long_ok, seconds=6, size=(320, 180))
        write_video(short, seconds=2, size=(320, 180))
        write_video(vertical, seconds=6, size=(180, 320))
        write_video(cutty, seconds=6, size=(320, 180), scene_flip_every=0.5)
        write_video(blurry, seconds=6, size=(320, 180), textured=False)

        print("[1] triyaj filtreleri (M-O-02)")
        check(triage(long_ok, thresholds=fast).accepted,
              "uzun+yatay+net+tek-sahne video KABUL")
        r = triage(short, thresholds=fast)
        check(not r.accepted and any("süre" in x for x in r.rejects),
              "kısa video süreden RET")
        r = triage(short)  # varsayılan eşikler
        check(any("90s" in x for x in r.rejects),
              "varsayılan eşik 90 sn (shorts eleme)")
        r = triage(vertical, thresholds=fast)
        check(any("dikey" in x for x in r.rejects), "dikey format RET")
        r = triage(cutty, thresholds=fast)
        check(any("kesme" in x for x in r.rejects),
              f"hızlı kurgu RET (ölçülen {r.cuts_per_min:.0f}/dk)")
        r = triage(blurry, thresholds=fast)
        check(any("netlik" in x for x in r.rejects), "dokusuz/bulanık kaynak RET")

        print("[1b] tam-gövde eşiği entegrasyonu (L-046; sonda stub'lı)")
        # Poz sondasını stub'la: entegrasyon YOLU gerçek koşulsun (8ef2d09'un
        # iki NameError/AttributeError'ı tam bu yolda saklanıyordu).
        import triage as triage_mod
        real_probe = triage_mod._body_presence
        triage_mod._body_presence = lambda p, d, n, m: (0.92, 0.50)
        try:
            full_th = TriageThresholds(min_duration_s=4.0,
                                       min_full_body_ratio=0.6)
            r = triage(long_ok, thresholds=full_th,
                       pose_model=__import__("pathlib").Path("stub.task"))
            check(not r.accepted and any("tam-gövde" in x for x in r.rejects),
                  "üst-gövde 0.92 geçse de tam-gövde 0.50 < 0.6 → RET")
            check(r.upper_body_ratio == 0.92 and r.full_body_ratio == 0.50,
                  "iki oran da rapora yazılıyor (tek sonda geçişi)")
            off_th = TriageThresholds(min_duration_s=4.0)  # varsayılan: kapalı
            r = triage(long_ok, thresholds=off_th,
                       pose_model=__import__("pathlib").Path("stub.task"))
            check(r.accepted and r.full_body_ratio is None,
                  "eşik kapalıyken tam-gövde reddi yok (geriye uyum)")
        finally:
            triage_mod._body_presence = real_probe

        print("[2] algısal imza / dedup")
        sig_a = perceptual_signature(long_ok)
        sig_a2 = perceptual_signature(long_ok)
        sig_b = perceptual_signature(cutty)
        check(hamming(sig_a, sig_a2) == 0, "aynı dosya aynı imza")
        check(hamming(sig_a, sig_b) > 64,
              f"farklı içerik uzak imza (hamming={hamming(sig_a, sig_b)})")

        print("[3] manifest provenance")
        m = HarvestManifest.start(app="jablab", video_id="abc123",
                                  source_url="https://youtu.be/abc123")
        m.absorb_info_json({"channel": "Precision Striking",
                            "uploader": "PS", "upload_date": "20240110"})
        check(m.license == "standard-youtube",
              "lisans alanı boşsa 'standard-youtube' varsayılır (C-017)")
        m.record("triage", "ok", durationS=120)
        p = os.path.join(td, "m.json")
        m.save(p)
        back = HarvestManifest.load(p)
        check(back.channel == "Precision Striking" and
              back.stages[0].stage == "triage",
              "manifest gidiş-dönüşü kayıpsız")
        blk = back.provenance_block()
        check(all(k in blk for k in ("sourceUrl", "license", "retrievedAt",
                                     "toolVersions")),
              "provenance bloku fixture v2 alanlarını taşıyor")

    if FAILURES:
        print(f"\n{len(FAILURES)} HATA")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
