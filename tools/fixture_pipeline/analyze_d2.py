#!/usr/bin/env python3
"""motion-core — D2 örnekleme/blur analizi (JabLab G1 kapısı). v2

`D2-KAPI-PROTOKOLU.md §2` tanımlarının düzeltilmiş uygulaması. v1'e göre üç
düzeltme (gerekçeler jablab DEFTER J-006/J-007/J-008):

1. **Kol-uzunluğu normalizasyonu.** Uzanma ölçüsü omuz genişliğine değil
   ölçülen kol uzunluğuna bölünür: e(t) = |bilek-omuz| / (|omuz-dirsek|+|dirsek-bilek|).
   e ∈ [0,1]; gard ≈ 0.5-0.6, tam uzanma ≈ 0.9-1.0 → eşikler fiziksel anlamlı
   ve vücut ölçüsünden bağımsız.
2. **Taban-göreli görünürlük.** Bölge görünürlüğü mutlak değil, o klibin kendi
   GARD karelerindeki tabanına göre ölçülür. Taban zaten düşükse (uzuv kadraj
   dışı) o bölge o klip için ÖLÇÜLEMEZ sayılır — kadraj sorunu blur bulgusu
   olarak raporlanmaz.
3. **Eşleştirilmiş desimasyon.** H3 karşılaştırması aynı yumruğu fps'ler
   arasında eşleyerek yapılır (tepe zamanına göre); "medyan vs medyan" farklı
   yumruk kümelerini kıyasladığı için geçersizdi.

Kullanım:
    python analyze_d2.py fixtures/bag_full.json --decimate 1,2,3,4 -o out/bag

2026-07-29 (M-F-03): `tools/` kökünden `tools/fixture_pipeline/` altına taşındı;
landmark/bölge tanımları artık mocore'dan gelir, fixture okuyucu HEM eski JabLab
D2 şemasını (frames[].landmarks, piksel uzayı) HEM mocore şemasını
(frames[].lm+world, WORLD uzayı) kabul eder. Analiz matematiği DEĞİŞMEDİ —
mevcut D2 kapı raporu aynı girdiyle aynı sayıları verir (uzanma oranı ve hız
kol-uzunluğu-normalize olduğundan uzay seçimi sonucu etkilemez).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import statistics as stats

import numpy as np

from mocore import landmarks as _lmk

# Eski D2 hattının küçük-harf isim sözleşmesi korunur (rapor anahtarları ve
# çıktı JSON'ları değişmesin); tek doğruluk kaynağı mocore.landmarks'tır.
IDX = {name.lower(): i for i, name in enumerate(_lmk.NAMES)}
REGIONS = {k.lower(): [n.lower() for n in v] for k, v in _lmk.REGIONS.items()}


def arm_region(side: str) -> list[str]:
    return [n.lower() for n in _lmk.arm_region(side)]

# --- Protokol sabitleri ----------------------------------------------------
EXT_PEAK_MIN = 0.82    # yumruk sayılması için minimum tepe uzanma oranı
PHASE_THR = 0.62       # faz sınırı (gard ↔ uzanma) uzanma oranı
MIN_GAP_MS = 150       # iki yumruk tepesi arası minimum gerçek süre
# Fiziksel üst sınırlar. Uzanma fazı 400ms'yi aşan hareket YUMRUK DEĞİLDİR
# (torbaya yaslanma, poz verme, kolu uzatıp bekleme). Bu filtre üretim
# motorundaki EXTENSION_TIMEOUT durumunun prototipidir (jablab-plan §10:
# her hareketin timeout + iptal koşulu olmalı).
MAX_EXT_MS = 400
MAX_CYCLE_MS = 1200
JUMP_THR_L = 0.55      # ardışık karede bilek sıçraması (kol uzunluğu birimi)
VIS_INFRAME_MIN = 0.50 # bölge "kadrajda" sayılması için gard tabanı eşiği
MATCH_TOL_MS = 120     # desimasyonlar arası yumruk eşleme toleransı


#: mocore snake_case meta alanlarının eski camelCase rapor anahtarlarına köprüsü.
_META_ALIASES = {
    "framesProcessed": "frame_count",
    "framesWithoutPose": "frames_without_pose",
    "cameraSetup": "camera_setup",
    "hostInferenceMsPerFrame": "host_inference_ms_per_frame",
}
_META_REPORT_KEYS = (
    "resolution", "fps", "framesProcessed", "framesWithoutPose",
    "sourceUrl", "license", "cameraSetup", "lighting",
    "hostInferenceMsPerFrame",
)


def load(path: str):
    """Fixture yükle — iki şema da kabul (bkz. modül docstring'i).

    Eski şema: normalize görüntü koordinatı -> piksel uzayına ölçeklenir
    (z, MediaPipe'ta x ile AYNI ölçektedir: görüntü genişliğine normalize).
    mocore şeması: WORLD koordinatları (metre) doğrudan kullanılır.
    Her iki uzayda da e(t) ve hız kol-uzunluğuna bölündüğü için eşikler ortak.
    """
    with open(path) as f:
        fx = json.load(f)
    meta = fx["recordingMeta"]
    frames = fx["frames"]
    T = len(frames)
    xyz = np.full((T, 33, 3), np.nan)
    vis = np.full((T, 33), np.nan)
    t_ms = np.array([f["t"] for f in frames], dtype=float)

    legacy = any("landmarks" in fr for fr in frames[:1])
    if legacy:
        w, h = (int(v) for v in str(meta["resolution"]).split("x"))
        for i, fr in enumerate(frames):
            lms = fr["landmarks"]
            if not lms:
                continue
            for j, lm in enumerate(lms):
                xyz[i, j, 0] = lm["x"] * w
                xyz[i, j, 1] = lm["y"] * h
                xyz[i, j, 2] = lm["z"] * w
                vis[i, j] = lm["vis"]
    else:
        for i, fr in enumerate(frames):
            if not fr.get("detected"):
                continue
            world = np.asarray(fr["world"], dtype=float)
            if world.shape != (33, 3):
                continue
            lm_arr = np.asarray(fr["lm"], dtype=float)
            xyz[i] = world
            vis[i] = lm_arr[:, 3]

    # Provenance (v2) rapora akar; sourceUrl/license eski hatta meta'daydı.
    prov = fx.get("provenance") or {}
    for key in ("sourceUrl", "license"):
        if key not in meta and key in prov:
            meta[key] = prov[key]
    for camel, snake in _META_ALIASES.items():
        if camel not in meta and snake in meta:
            meta[camel] = meta[snake]
    for key in _META_REPORT_KEYS:
        meta.setdefault(key, None)
    return fx, meta, t_ms, xyz, vis


def dist(a: np.ndarray, b: np.ndarray, dims: int) -> np.ndarray:
    return np.linalg.norm(a[..., :dims] - b[..., :dims], axis=-1)


def arm_length(xyz: np.ndarray, side: str, dims: int) -> float:
    sh, el, wr = (xyz[:, IDX[f"{side}_{p}"]] for p in ("shoulder", "elbow", "wrist"))
    seg = dist(sh, el, dims) + dist(el, wr, dims)
    seg = seg[np.isfinite(seg)]
    if seg.size == 0:
        return float("nan")
    # Kol bükülüyken segment toplamı sabittir; medyan sağlam tahmindir.
    return float(np.median(seg))


def extension_series(xyz: np.ndarray, side: str, L: float, dims: int) -> np.ndarray:
    """e(t) ∈ [0,1] — uzanma oranı."""
    r = dist(xyz[:, IDX[f"{side}_wrist"]], xyz[:, IDX[f"{side}_shoulder"]], dims)
    return r / L


def _interp_cross(t, e, i, j, thr) -> float:
    if not (math.isfinite(e[i]) and math.isfinite(e[j])):
        return float(t[i])
    denom = e[j] - e[i]
    if abs(denom) < 1e-9:
        return float(t[i])
    frac = min(max((thr - e[i]) / denom, 0.0), 1.0)
    return float(t[i] + frac * (t[j] - t[i]))


def _parabolic_peak(t, e, i) -> float:
    if i <= 0 or i >= len(e) - 1:
        return float(t[i])
    y0, y1, y2 = e[i - 1], e[i], e[i + 1]
    if not all(math.isfinite(v) for v in (y0, y1, y2)):
        return float(t[i])
    denom = y0 - 2 * y1 + y2
    if abs(denom) < 1e-9:
        return float(t[i])
    delta = min(max(0.5 * (y0 - y2) / denom, -1.0), 1.0)
    return float(t[i] + delta * (t[i + 1] - t[i]))


def detect_punches(t: np.ndarray, e: np.ndarray) -> list[dict]:
    """Gard (e<PHASE_THR) → uzanma (tepe ≥ EXT_PEAK_MIN) → gard dönüşü."""
    n = len(e)
    peaks = []
    for i in range(1, n - 1):
        if not math.isfinite(e[i]):
            continue
        if e[i] >= EXT_PEAK_MIN and e[i] >= e[i - 1] and e[i] > e[i + 1]:
            peaks.append(i)

    # Refrakter dönem: MIN_GAP_MS içindeki tepelerden en yükseği kalır.
    merged: list[int] = []
    for p in peaks:
        if merged and (t[p] - t[merged[-1]]) < MIN_GAP_MS:
            if e[p] > e[merged[-1]]:
                merged[-1] = p
        else:
            merged.append(p)

    out = []
    for p in merged:
        i0 = p
        while i0 > 0 and math.isfinite(e[i0 - 1]) and e[i0 - 1] > PHASE_THR:
            i0 -= 1
        if i0 == 0 and (not math.isfinite(e[0]) or e[0] > PHASE_THR):
            continue                       # klip yumruğun ortasında başlıyor
        i1 = p
        while i1 < n - 1 and math.isfinite(e[i1 + 1]) and e[i1 + 1] > PHASE_THR:
            i1 += 1
        if i1 == n - 1 and (not math.isfinite(e[-1]) or e[-1] > PHASE_THR):
            continue                       # klip yumruğun ortasında bitiyor

        t0 = _interp_cross(t, e, i0, i0 - 1, PHASE_THR)
        tp = _parabolic_peak(t, e, p)
        t1 = _interp_cross(t, e, i1, i1 + 1, PHASE_THR)
        if not (t0 < tp < t1):
            continue
        if (tp - t0) > MAX_EXT_MS or (t1 - t0) > MAX_CYCLE_MS:
            continue                       # yumruk değil: uzanıp bekleme/yaslanma
        out.append({
            "i0": i0, "ip": p, "i1": i1,
            "t0": t0, "tp": tp, "t1": t1,
            "t_ext_ms": tp - t0,
            "t_ret_ms": t1 - tp,
            "n_ext_frames": p - i0 + 1,
            "n_cycle_frames": i1 - i0 + 1,
            "e_peak": float(e[p]),
        })
    return out


def region_baseline_and_min(vis, guard_mask, i0, i1, names):
    idxs = [IDX[n] for n in names]
    base_win = vis[guard_mask][:, idxs]
    base_win = base_win[np.isfinite(base_win)]
    baseline = float(np.median(base_win)) if base_win.size else float("nan")
    win = vis[i0:i1 + 1, idxs]
    win = win[np.isfinite(win)]
    vmin = float(np.min(win)) if win.size else float("nan")
    return baseline, vmin


def peak_wrist_speed(xyz, t, side, L, i0, i1, dims) -> float:
    """Kare-arası bilek hızı tepesi (kol-uzunluğu / saniye) — ÇÜRÜTME kolu."""
    lo, hi = max(i0 - 1, 0), min(i1 + 2, len(t))
    wr = xyz[lo:hi, IDX[f"{side}_wrist"], :dims]
    tt = t[lo:hi]
    if len(wr) < 2:
        return float("nan")
    d = np.linalg.norm(np.diff(wr, axis=0), axis=1) / L
    dt = np.diff(tt) / 1000.0
    with np.errstate(invalid="ignore", divide="ignore"):
        v = d / dt
    v = v[np.isfinite(v)]
    return float(np.max(v)) if v.size else float("nan")


def cv(values) -> float:
    vals = [v for v in values if v is not None and math.isfinite(v)]
    if len(vals) < 2:
        return float("nan")
    m = stats.fmean(vals)
    return stats.pstdev(vals) / abs(m) if abs(m) > 1e-9 else float("nan")


def med(values) -> float:
    vals = [v for v in values if v is not None and math.isfinite(v)]
    return float(stats.median(vals)) if vals else float("nan")


def analyze(path: str, decimations: list[int], dims: int, label: str) -> dict:
    fx, meta, t, xyz, vis = load(path)
    fps = float(meta["fps"])
    duration_s = (t[-1] - t[0]) / 1000.0 if len(t) > 1 else 0.0

    per_side, all_punches = {}, []
    guard_mask = np.ones(len(t), dtype=bool)

    # 1. geçiş: yumrukları bul, gard maskesini oluştur.
    for side in ("left", "right"):
        L = arm_length(xyz, side, dims)
        e = extension_series(xyz, side, L, dims)
        punches = detect_punches(t, e)
        per_side[side] = {"L_px": L, "e": e, "punches": punches}
        for p in punches:
            guard_mask[p["i0"]:p["i1"] + 1] = False

    # 2. geçiş: gard-tabanı bilinince görünürlük ve hız metrikleri.
    for side in ("left", "right"):
        L = per_side[side]["L_px"]
        for p in per_side[side]["punches"]:
            i0, i1 = p["i0"], p["i1"]
            other = "right" if side == "left" else "left"
            for key, names in (("fast", arm_region(side)),
                               ("guard", arm_region(other)),
                               ("trunk", REGIONS["trunk"]),
                               ("base", REGIONS["base"])):
                b, vmin = region_baseline_and_min(vis, guard_mask, i0, i1, names)
                p[f"vis_{key}_baseline"] = b
                p[f"vis_{key}_min"] = vmin
                p[f"vis_{key}_drop"] = (b - vmin) if math.isfinite(b) and math.isfinite(vmin) else float("nan")
                p[f"vis_{key}_inframe"] = bool(math.isfinite(b) and b >= VIS_INFRAME_MIN)
            p["v_wrist_peak"] = peak_wrist_speed(xyz, t, side, L, i0, i1, dims)
            p["side"] = side
            all_punches.append(p)

    all_punches.sort(key=lambda p: p["tp"])

    # --- H3: EŞLEŞTİRİLMİŞ desimasyon deneyi ------------------------------
    h3_per_punch = []
    h3_levels = {}
    for side in ("left", "right"):
        L = per_side[side]["L_px"]
        e_full = per_side[side]["e"]
        base = {round(p["tp"]): p for p in per_side[side]["punches"]}
        for k in decimations:
            tk, ek, xyzk = t[::k], e_full[::k], xyz[::k]
            pk = detect_punches(tk, ek)
            for q in pk:
                q["v_wrist_peak"] = peak_wrist_speed(xyzk, tk, side, L,
                                                     q["i0"], q["i1"], dims)
            h3_levels.setdefault(k, {"n": 0, "eff_fps": round(fps / k, 2)})
            h3_levels[k]["n"] += len(pk)
            for tp_ref, ref in base.items():
                cand = min(pk, key=lambda q: abs(q["tp"] - tp_ref), default=None)
                if cand is None or abs(cand["tp"] - tp_ref) > MATCH_TOL_MS:
                    continue
                ref.setdefault("matched", {})[k] = {
                    "t_ext_ms": cand["t_ext_ms"],
                    "v_wrist_peak": cand["v_wrist_peak"],
                    "n_ext_frames": cand["n_ext_frames"],
                }
        for p in per_side[side]["punches"]:
            m = p.get("matched", {})
            if len(m) < len(decimations):
                continue                    # her seviyede eşleşmeyen yumruk atlanır
            h3_per_punch.append({
                "tp": p["tp"], "side": side,
                "cv_phase": cv([m[k]["t_ext_ms"] for k in decimations]),
                "cv_pixel": cv([m[k]["v_wrist_peak"] for k in decimations]),
                "t_ext_series": [m[k]["t_ext_ms"] for k in decimations],
                "v_series": [m[k]["v_wrist_peak"] for k in decimations],
            })

    n_base = h3_levels[decimations[0]]["n"] if decimations else 0

    def inframe_stats(key):
        vals = [p for p in all_punches if p[f"vis_{key}_inframe"]]
        return {
            "inframe_ratio": (len(vals) / len(all_punches)) if all_punches else float("nan"),
            "baseline_median": med([p[f"vis_{key}_baseline"] for p in all_punches]),
            "min_median": med([p[f"vis_{key}_min"] for p in vals]),
            "drop_median": med([p[f"vis_{key}_drop"] for p in vals]),
            "below_0_5_ratio": (float(np.mean([p[f"vis_{key}_min"] < 0.5 for p in vals]))
                                if vals else float("nan")),
            "below_0_4_ratio": (float(np.mean([p[f"vis_{key}_min"] < 0.4 for p in vals]))
                                if vals else float("nan")),
        }

    # --- Landmark-başına ayrıştırma ---------------------------------------
    # Bölge minimumu EN KÖTÜ landmark'ın esiridir (parmak landmark'ı tüm kolu
    # aşağı çeker). Ürün kararı landmark seviyesinde verilir: ELBOW_FLARED
    # dirseğe, REAR_HAND_LOW arka bileğe, STANCE_* ayak bileğine bakar.
    key_lms = ["left_wrist", "right_wrist", "left_elbow", "right_elbow",
               "left_index", "right_index", "left_shoulder", "right_shoulder",
               "left_hip", "right_hip", "left_ankle", "right_ankle", "nose"]
    lm_stats = {}
    for name in key_lms:
        j = IDX[name]
        base_col = vis[guard_mask, j]
        base_col = base_col[np.isfinite(base_col)]
        baseline = float(np.median(base_col)) if base_col.size else float("nan")
        mins = []
        for p in all_punches:
            w = vis[p["i0"]:p["i1"] + 1, j]
            w = w[np.isfinite(w)]
            if w.size:
                mins.append(float(np.min(w)))
        lm_stats[name] = {
            "baseline": baseline,
            "min_median": med(mins),
            "drop_median": (baseline - med(mins)) if math.isfinite(baseline) else float("nan"),
            "below_0_5_ratio": float(np.mean([v < 0.5 for v in mins])) if mins else float("nan"),
            "inframe": bool(math.isfinite(baseline) and baseline >= VIS_INFRAME_MIN),
        }

    # --- Blur mü kapanma mı? KLİP-İÇİ hız↔bozulma testi -------------------
    # Bölgesel düşüşün nedeni belirsizdir: motion blur mu, gövdenin uzvu
    # kapatması mı? Ayırt edici deney AYNI KLİP içindedir — kadraj, ışık,
    # kamera açısı ve giysi sabitken yalnız yumruk hızı değişir. Hızlı
    # yumruklar sistematik olarak daha çok bozuluyorsa neden HIZDIR.
    def spearman(xs, ys) -> float:
        pairs = [(a, b) for a, b in zip(xs, ys)
                 if a is not None and b is not None
                 and math.isfinite(a) and math.isfinite(b)]
        if len(pairs) < 5:
            return float("nan")
        def ranks(v):
            order = sorted(range(len(v)), key=lambda i: v[i])
            rk = [0.0] * len(v)
            i = 0
            while i < len(order):
                j = i
                while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
                    j += 1
                avg = (i + j) / 2.0 + 1
                for q in range(i, j + 1):
                    rk[order[q]] = avg
                i = j + 1
            return rk
        rx, ry = ranks([p[0] for p in pairs]), ranks([p[1] for p in pairs])
        mx, my = stats.fmean(rx), stats.fmean(ry)
        num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
        den = math.sqrt(sum((a - mx) ** 2 for a in rx) *
                        sum((b - my) ** 2 for b in ry))
        return num / den if den > 1e-9 else float("nan")

    blur_test = {}
    for side in ("left", "right"):
        j_wr = IDX[f"{side}_wrist"]
        ps = [p for p in all_punches if p["side"] == side]
        speeds, drops, texts = [], [], []
        base_col = vis[guard_mask, j_wr]
        base_col = base_col[np.isfinite(base_col)]
        baseline = float(np.median(base_col)) if base_col.size else float("nan")
        for p in ps:
            w = vis[p["i0"]:p["i1"] + 1, j_wr]
            w = w[np.isfinite(w)]
            if not w.size:
                continue
            speeds.append(p["v_wrist_peak"])
            drops.append(baseline - float(np.min(w)))
            texts.append(p["t_ext_ms"])
        blur_test[side] = {
            "n": len(speeds),
            "wrist_baseline": baseline,
            # Pozitif ρ: hız arttıkça bozulma artıyor → BLUR imzası.
            "rho_speed_vs_drop": spearman(speeds, drops),
            # Negatif ρ: uzanma süresi kısaldıkça (=daha hızlı) bozulma artıyor.
            "rho_text_vs_drop": spearman(texts, drops),
        }

    wr_jump = {}
    for side in ("left", "right"):
        L = per_side[side]["L_px"]
        wr = xyz[:, IDX[f"{side}_wrist"], :dims]
        d = np.linalg.norm(np.diff(wr, axis=0), axis=1) / L
        d = d[np.isfinite(d)]
        wr_jump[side] = float(np.mean(d > JUMP_THR_L)) if d.size else float("nan")

    t_ext_med = med([p["t_ext_ms"] for p in all_punches])
    result = {
        "label": label,
        "fixture": os.path.basename(path),
        "modelVersion": fx["modelVersion"],
        "dims": dims,
        "meta": {kk: meta.get(kk) for kk in
                 ("resolution", "fps", "framesProcessed", "framesWithoutPose",
                  "sourceUrl", "license", "cameraSetup", "lighting",
                  "hostInferenceMsPerFrame")},
        "armLengthPx": {s: round(per_side[s]["L_px"], 2) for s in per_side},
        "summary": {
            "duration_s": round(duration_s, 2),
            "n_punches": len(all_punches),
            "cadence_pps": round(len(all_punches) / duration_s, 2) if duration_s else None,
            "median_t_ext_ms": t_ext_med,
            "p10_t_ext_ms": (float(np.percentile([p["t_ext_ms"] for p in all_punches], 10))
                             if all_punches else float("nan")),
            "median_t_ret_ms": med([p["t_ret_ms"] for p in all_punches]),
            "median_n_ext_frames": med([p["n_ext_frames"] for p in all_punches]),
            "median_e_peak": med([p["e_peak"] for p in all_punches]),
            "jump_rate": wr_jump,
            # t_ext ölçülünce n_ext@fps ARİTMETİK olarak türetilir (protokol §0/D2-A).
            "derived_n_ext_at_30fps": (t_ext_med * 30 / 1000.0) if math.isfinite(t_ext_med) else None,
            "derived_n_ext_at_60fps": (t_ext_med * 60 / 1000.0) if math.isfinite(t_ext_med) else None,
        },
        "regions": {k: inframe_stats(k) for k in ("fast", "guard", "trunk", "base")},
        "landmarks": lm_stats,
        "blurTest": blur_test,
        "h3": {
            "levels": {k: {**v, "detection_rate": (v["n"] / n_base) if n_base else float("nan")}
                       for k, v in h3_levels.items()},
            "n_matched_punches": len(h3_per_punch),
            "median_cv_phase": med([x["cv_phase"] for x in h3_per_punch]),
            "median_cv_pixel": med([x["cv_pixel"] for x in h3_per_punch]),
            "per_punch": h3_per_punch[:50],
        },
    }
    return result


def fmt(v, n=1):
    return "—" if v is None or (isinstance(v, float) and not math.isfinite(v)) else f"{v:.{n}f}"


def report(r: dict, decimations: list[int]) -> None:
    m, s = r["meta"], r["summary"]
    print(f"\n### {r['label']}  ({m['resolution']} @ {m['fps']}fps · "
          f"{m['framesProcessed']} kare · pozsuz={m['framesWithoutPose']} · {m['cameraSetup']})")
    print(f"  yumruk / kadans        : {s['n_punches']} / {fmt(s['cadence_pps'],2)} yumruk-sn⁻¹  "
          f"(süre {fmt(s['duration_s'],1)}s)")
    print(f"  medyan tepe uzanma e   : {fmt(s['median_e_peak'],3)}")
    print(f"  medyan t_ext           : {fmt(s['median_t_ext_ms'])} ms  "
          f"(p10 {fmt(s['p10_t_ext_ms'])} ms) → türetilen kare: "
          f"{fmt(s['derived_n_ext_at_30fps'],1)}@30fps · {fmt(s['derived_n_ext_at_60fps'],1)}@60fps")
    print(f"  medyan t_retraction    : {fmt(s['median_t_ret_ms'])} ms")
    print("  bölge görünürlüğü (yalnız KADRAJDA olan bölgeler):")
    for k, tr in (("fast", "yumruk kolu"), ("guard", "arka el"),
                  ("trunk", "gövde"), ("base", "ayaklar")):
        g = r["regions"][k]
        if not math.isfinite(g["baseline_median"]) or g["baseline_median"] < VIS_INFRAME_MIN:
            print(f"    {tr:<12}: ÖLÇÜLEMEZ (gard tabanı {fmt(g['baseline_median'],2)} < {VIS_INFRAME_MIN}) — kadraj dışı")
            continue
        print(f"    {tr:<12}: taban {fmt(g['baseline_median'],3)} → yumrukta min {fmt(g['min_median'],3)} "
              f"(düşüş {fmt(g['drop_median'],3)}; <0.5 oranı {fmt(g['below_0_5_ratio'],2)})")
    print("  landmark-başına (taban → yumrukta min · düşüş · <0.5 oranı):")
    for name in ("left_wrist", "right_wrist", "left_elbow", "right_elbow",
                 "left_index", "right_index", "left_hip", "left_ankle"):
        g = r["landmarks"][name]
        if not g["inframe"]:
            print(f"    {name:<14}: ÖLÇÜLEMEZ (taban {fmt(g['baseline'],2)})")
            continue
        print(f"    {name:<14}: {fmt(g['baseline'],3)} → {fmt(g['min_median'],3)} "
              f"· {fmt(g['drop_median'],3)} · {fmt(g['below_0_5_ratio'],2)}")
    print("  BLUR mü KAPANMA mı (klip-içi, ρ>0 ⇒ hız arttıkça bozulma artıyor = blur):")
    for side in ("left", "right"):
        b = r["blurTest"][side]
        print(f"    {side:<6}: n={b['n']} taban={fmt(b['wrist_baseline'],2)} "
              f"ρ(hız,düşüş)={fmt(b['rho_speed_vs_drop'],2)} "
              f"ρ(t_ext,düşüş)={fmt(b['rho_text_vs_drop'],2)}")
    print(f"  bilek sıçrama oranı    : sol {fmt(r['summary']['jump_rate']['left'],3)} · "
          f"sağ {fmt(r['summary']['jump_rate']['right'],3)}")
    print(f"  --- H3 (eşleştirilmiş, n={r['h3']['n_matched_punches']} yumruk) ---")
    for k in decimations:
        lv = r["h3"]["levels"][k]
        print(f"    k={k} (~{lv['eff_fps']}fps): tespit={lv['n']} "
              f"(oran {fmt(lv['detection_rate'],2)})")
    print(f"    medyan CV_phase={fmt(r['h3']['median_cv_phase'],3)}  "
          f"medyan CV_pixel={fmt(r['h3']['median_cv_pixel'],3)}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("fixture")
    ap.add_argument("--decimate", default="1,2,3,4")
    ap.add_argument("--dims", type=int, default=2, choices=(2, 3))
    ap.add_argument("-o", "--out-prefix", required=True)
    ap.add_argument("--label", default=None)
    args = ap.parse_args()

    decs = [int(v) for v in args.decimate.split(",")]
    r = analyze(args.fixture, decs, args.dims,
                args.label or os.path.basename(args.fixture))
    os.makedirs(os.path.dirname(args.out_prefix) or ".", exist_ok=True)
    with open(args.out_prefix + ".json", "w") as f:
        json.dump(r, f, indent=2)
    report(r, decs)


if __name__ == "__main__":
    main()
