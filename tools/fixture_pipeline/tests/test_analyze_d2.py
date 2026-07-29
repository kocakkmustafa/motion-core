#!/usr/bin/env python
"""analyze_d2 birleşim testi (M-F-03 taşınması).

Kanıtlanan iddialar:
  1. Eski JabLab D2 şeması (frames[].landmarks, piksel uzayı) hâlâ okunur ve
     sentetik yumruğu bulur — mevcut kapı raporunun tekrarlanabilirliği.
  2. mocore şeması (frames[].lm+world, WORLD uzayı) aynı analizden geçer ve
     AYNI faz sürelerini verir (kol-uzunluğu normalizasyonu uzay-bağımsız).
  3. mocore.fixture v2 gidiş-dönüşü provenance'ı korur; v1 dosyalar okunur.

Koşum (pytest gerekmez):
    ./.venv/bin/python tests/test_analyze_d2.py
"""
from __future__ import annotations

import json
import math
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import analyze_d2  # noqa: E402
from mocore import fixture as fx  # noqa: E402
from mocore import landmarks as lmk  # noqa: E402

FPS = 30.0
N_FRAMES = 90  # 3 sn
ARM = 0.30  # normalize birimde toplam kol uzunluğu (omuz-dirsek + dirsek-bilek)
SEG = ARM / 2


def _extension_profile(t_ms: float) -> float:
    """e(t): gard 0.55, ~1.5 sn'de tepe 0.95'e çıkan tek yumruk."""
    t_peak, rise_ms, fall_ms = 1500.0, 130.0, 200.0
    if t_ms < t_peak - rise_ms or t_ms > t_peak + fall_ms:
        return 0.55
    if t_ms <= t_peak:
        u = (t_ms - (t_peak - rise_ms)) / rise_ms
    else:
        u = 1.0 - (t_ms - t_peak) / fall_ms
    return 0.55 + (0.95 - 0.55) * u


def _skeleton(e_left: float) -> np.ndarray:
    """33x3 iskelet (normalize uzay). Sol kol e_left uzanımında, sağ kol gardda."""
    p = np.zeros((33, 3))
    p[:, 0], p[:, 1] = 0.5, 0.5  # varsayılan: gövde merkezi
    idx = {name.lower(): i for i, name in enumerate(lmk.NAMES)}

    def put(name, x, y):
        p[idx[name], 0], p[idx[name], 1] = x, y

    put("nose", 0.5, 0.20)
    put("left_ear", 0.53, 0.20); put("right_ear", 0.47, 0.20)
    put("left_shoulder", 0.56, 0.30); put("right_shoulder", 0.44, 0.30)
    put("left_hip", 0.54, 0.55); put("right_hip", 0.46, 0.55)
    put("left_knee", 0.54, 0.75); put("right_knee", 0.46, 0.75)
    put("left_ankle", 0.54, 0.92); put("right_ankle", 0.46, 0.92)
    put("left_heel", 0.545, 0.94); put("right_heel", 0.455, 0.94)
    put("left_foot_index", 0.56, 0.95); put("right_foot_index", 0.44, 0.95)

    def arm(side: str, e: float, direction: float) -> None:
        sh = p[idx[f"{side}_shoulder"], :2]
        r = e * ARM
        wr = sh + np.array([direction * r, 0.0])
        mid = (sh + wr) / 2
        half = r / 2
        h = math.sqrt(max(SEG * SEG - half * half, 0.0))
        el = mid + np.array([0.0, h])  # dirsek aşağı kırık
        p[idx[f"{side}_elbow"], :2] = el
        p[idx[f"{side}_wrist"], :2] = wr
        p[idx[f"{side}_index"], :2] = wr + np.array([direction * 0.02, 0.0])
        p[idx[f"{side}_pinky"], :2] = wr + np.array([direction * 0.015, 0.005])
        p[idx[f"{side}_thumb"], :2] = wr + np.array([direction * 0.01, -0.005])

    arm("left", e_left, +1.0)
    arm("right", 0.53, -1.0)
    return p


def _frames_norm() -> list[np.ndarray]:
    return [_skeleton(_extension_profile(i * 1000.0 / FPS)) for i in range(N_FRAMES)]


def build_legacy(path: str) -> None:
    frames = []
    for i, p in enumerate(_frames_norm()):
        t = int(round(i * 1000.0 / FPS))
        lms = [
            {"x": round(float(x), 6), "y": round(float(y), 6),
             "z": round(float(z), 6), "vis": 0.9}
            for x, y, z in p
        ]
        frames.append({"t": t, "landmarks": lms})
    doc = {
        "schemaVersion": 1,
        "app": "jablab",
        "technique": "jab",
        "recordingMeta": {
            "device": "synthetic", "fps": FPS, "lighting": "bright",
            "bodyProfile": "synthetic", "cameraSetup": "frontal",
            "resolution": "1000x1000", "framesProcessed": N_FRAMES,
            "framesWithoutPose": 0,
        },
        "modelVersion": "synthetic",
        "frames": frames,
        "labels": [],
    }
    with open(path, "w") as f:
        json.dump(doc, f)


def build_mocore(path: str) -> None:
    meta = fx.RecordingMeta.freeform(
        technique="jab", device="synthetic", camera_setup="frontal",
        source_video="synthetic.mp4",
    )
    meta.fps = FPS
    meta.frame_count = N_FRAMES
    meta.resolution = "1000x1000"
    meta.frames_without_pose = 0
    fixture = fx.Fixture(
        schema_version=fx.SCHEMA_VERSION,
        app="jablab",
        meta=meta,
        model_version="synthetic",
        model_sha256="0" * 64,
        provenance={"sourceUrl": "https://example.test/v", "license": "cc-by"},
    )
    for i, p in enumerate(_frames_norm()):
        t = i * 1000.0 / FPS
        # world: normalize iskeletin metre ölçeğine indirgenmiş hâli (÷2) —
        # ölçek farkı, kol-uzunluğu normalizasyonunun uzay-bağımsızlık kanıtı.
        world = p / 2.0
        fixture.frames.append({
            "t": round(t, 2),
            "detected": True,
            "lm": [[round(float(x), 5), round(float(y), 5), round(float(z), 5),
                    0.9, 0.95] for x, y, z in p],
            "world": [[round(float(x), 5), round(float(y), 5),
                       round(float(z), 5)] for x, y, z in world],
        })
    with open(path, "w") as f:
        f.write(fixture.to_json())


def _fast_ramp_profile(t_ms: float, ramp_ms: float, peak: float) -> float:
    """gard 0.55'ten `ramp_ms` sürede `peak`'e çıkan tek geçiş.

    `peak` bilerek 1.0'ı (fiziksel tam uzanma) aşabilir — burada gerçek bir
    yumruk MODELLENMİYOR, yalnız jump/glitch dedektörünün ham bilek
    yer-değiştirme matematiği (JUMP_THR_L/JUMP_THR_SPEED_L) fps'e karşı
    sınanıyor. `arm_length()` medyan aldığı için baseline karelerin (e=0.55)
    çoğunluğu L'yi domine eder, tepe kareleri L tahminini bozmaz.
    """
    t_peak = 500.0
    if t_ms < t_peak - ramp_ms or t_ms > t_peak + 200.0:
        return 0.55
    if t_ms <= t_peak:
        u = (t_ms - (t_peak - ramp_ms)) / ramp_ms
    else:
        u = 1.0 - (t_ms - t_peak) / 200.0
    return 0.55 + (peak - 0.55) * u


def build_fast_punch(path: str, fps: float, ramp_ms: float, peak: float,
                      n_frames: int) -> None:
    """M-F-72 #3: AYNI fiziksel hareket (ramp_ms gerçek-zaman rampası),
    yalnız fps FARKLI örneklenmiş. jump_rate/jump_rate_fps_normalized
    karşılaştırması bu çift üstünde yapılır."""
    frames = []
    for i in range(n_frames):
        t_ms = i * 1000.0 / fps
        p = _skeleton(_fast_ramp_profile(t_ms, ramp_ms, peak))
        lms = [
            {"x": round(float(x), 6), "y": round(float(y), 6),
             "z": round(float(z), 6), "vis": 0.9}
            for x, y, z in p
        ]
        frames.append({"t": int(round(t_ms)), "landmarks": lms})
    doc = {
        "schemaVersion": 1,
        "app": "jablab",
        "technique": "jab",
        "recordingMeta": {
            "device": "synthetic", "fps": fps, "lighting": "bright",
            "bodyProfile": "synthetic", "cameraSetup": "frontal",
            "resolution": "1000x1000", "framesProcessed": n_frames,
            "framesWithoutPose": 0,
        },
        "modelVersion": "synthetic",
        "frames": frames,
        "labels": [],
    }
    with open(path, "w") as f:
        json.dump(doc, f)


def main() -> int:
    failures: list[str] = []

    def check(cond: bool, msg: str) -> None:
        print(("  ✅ " if cond else "  ❌ ") + msg)
        if not cond:
            failures.append(msg)

    with tempfile.TemporaryDirectory() as td:
        legacy_path = os.path.join(td, "legacy.json")
        mocore_path = os.path.join(td, "mocore.json")
        build_legacy(legacy_path)
        build_mocore(mocore_path)

        r_leg = analyze_d2.analyze(legacy_path, [1], 2, "legacy")
        r_moc = analyze_d2.analyze(mocore_path, [1], 2, "mocore")

        print("[1] eski şema hâlâ analiz ediliyor")
        check(r_leg["summary"]["n_punches"] == 1,
              f"legacy: 1 yumruk bekleniyordu, {r_leg['summary']['n_punches']} bulundu")
        t_ext_leg = r_leg["summary"]["median_t_ext_ms"]
        check(80 <= t_ext_leg <= 200,
              f"legacy: t_ext {t_ext_leg:.0f}ms ~130ms bandında olmalı")

        print("[2] mocore şeması aynı sonucu veriyor")
        check(r_moc["summary"]["n_punches"] == 1,
              f"mocore: 1 yumruk bekleniyordu, {r_moc['summary']['n_punches']} bulundu")
        t_ext_moc = r_moc["summary"]["median_t_ext_ms"]
        check(abs(t_ext_leg - t_ext_moc) <= 12,
              f"faz süresi uzay-bağımsız olmalı: legacy {t_ext_leg:.1f} vs "
              f"mocore {t_ext_moc:.1f} ms")
        check(r_moc["meta"]["sourceUrl"] == "https://example.test/v",
              "provenance.sourceUrl rapora akmalı")

        print("[3] fixture v2 gidiş-dönüşü")
        meta, frames, stats = fx.load(mocore_path)
        check(stats["detected"] == N_FRAMES, "tüm kareler world uzayında yüklenmeli")
        check(meta.technique == "jab" and meta.resolution == "1000x1000",
              "v2 serbest-meta alanları korunmalı")

        print("[4] bölge tanımları mocore'dan geliyor")
        check(analyze_d2.REGIONS["trunk"] == [
            "left_shoulder", "right_shoulder", "left_hip", "right_hip"],
            "trunk bölgesi eski hatla birebir aynı olmalı")
        check(analyze_d2.arm_region("left") == ["left_elbow", "left_wrist",
                                                "left_index"],
              "arm_region eski hatla birebir aynı olmalı")

        print("[5] M-F-72 #3: JUMP_THR_L kare-cinsinden fps'e göre kayıyor,"
              " fps_normalized kaymıyor")
        # AYNI fiziksel geçiş (148ms rampa, e: 0.55→2.55 — bkz. _fast_ramp_
        # profile docstring'i), yalnız fps FARKLI örneklendi. Kol-boyu/kare
        # eşiği (JUMP_THR_L=0.55) 30fps'te net altında (hesap: ~0.45),
        # 24fps'te aynı geçiş eşiği geçer (hesap: ~0.56) — coordinator'ın
        # ölçtüğü desenle örtüşüyor. jump_rate_fps_normalized ikisinde de
        # AYNI olmalı.
        p30 = os.path.join(td, "fast30.json")
        p24 = os.path.join(td, "fast24.json")
        build_fast_punch(p30, fps=30.0, ramp_ms=148.0, peak=2.55, n_frames=45)
        build_fast_punch(p24, fps=24.0, ramp_ms=148.0, peak=2.55, n_frames=36)
        r30 = analyze_d2.analyze(p30, [1], 2, "fast30")
        r24 = analyze_d2.analyze(p24, [1], 2, "fast24")
        jr30 = r30["summary"]["jump_rate"]["left"]
        jr24 = r24["summary"]["jump_rate"]["left"]
        jrn30 = r30["summary"]["jump_rate_fps_normalized"]["left"]
        jrn24 = r24["summary"]["jump_rate_fps_normalized"]["left"]
        check(jr24 > jr30,
              f"BUG kanıtı: 24fps'te jump_rate ({jr24:.3f}) 30fps'ten "
              f"({jr30:.3f}) yüksek olmalı — aynı fiziksel hareket, kare-"
              f"cinsinden eşik fps'e göre kayıyor")
        check(abs(jrn30 - jrn24) < 0.05,
              f"DÜZELTME kanıtı: jump_rate_fps_normalized fps'ten bağımsız "
              f"olmalı (30fps {jrn30:.3f} vs 24fps {jrn24:.3f})")

    if failures:
        print(f"\n{len(failures)} HATA")
        return 1
    print("\nHepsi geçti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
