#!/usr/bin/env python
"""G1-a — Sayısal doğruluk kapısı koşucusu.

Protokol: ventures/lissom/app/docs/G1-V0-KAPI-PROTOKOLU.md §2
Eşikler ÖLÇÜMDEN ÖNCE yazıldı; bu betik onları yalnız OKUR, değiştirmez.

Çalıştırma:
    ./.venv/bin/python gate_g1a.py --config ../../../../lissom/app/config/metrics/lissom-metrics.v1.json
"""

from __future__ import annotations

import argparse
import json
import statistics
from dataclasses import dataclass
from pathlib import Path

import math

import numpy as np

from mocore import geometry as geo
from mocore import measures as mz
from mocore import synth

#: Sentetik iskeletin varsayılan ölçüleri — analitik beklentiler bunlara dayanır.
_B = synth.BodyProportions()

# --------------------------------------------------------------------------
# Eşikler — G1-V0-KAPI-PROTOKOLU.md §2.2'den birebir. Burada DEĞİŞTİRİLMEZ.
# --------------------------------------------------------------------------
THRESHOLDS = {
    "A1_clean_error_deg": 0.5,
    "A2_noise_005_median_deg": 2.0,
    "A3_noise_010_median_deg": 5.0,
    "A4_body_scale_drift_deg": 1.0,
    # A5 eşiksiz — gerçeklik ölçümü, kalibrasyon toleransını belirleyecek
    "A6_confidence_gate_leaks": 0,
    "A9_dead_metrics": 0,
}

#: Sentetik poz parametresi -> config metriği beklenen değer eşlemesi.
#: Bu eşleme, üretecin ürettiği açı ile config'in ölçtüğü açının AYNI şey
#: olduğunu iddia eder; iddia yanlışsa kapı bunu A1'de yakalar.
EXPECTED = {
    "shoulder_flexion_right": lambda p: p.shoulder_flex,
    "shoulder_flexion_left": lambda p: p.shoulder_flex,
    "elbow_extension_right": lambda p: 180.0 - p.elbow_flex,
    "elbow_extension_left": lambda p: 180.0 - p.elbow_flex,
    # Kalça açısı = GÖVDE ile uyluk arasındaki açı. Öne eğilmek anatomik olarak
    # zaten kalça fleksiyonudur, bu yüzden trunk_lean bu metriğe DAHİLDİR.
    # (İlk koşuda beklenti formülü bunu atlamıştı; ölçüm doğruydu, test yanlıştı.
    #  Ürün tarafı sonucu: hip_flexion ile trunk_lean bağımsız metrikler değildir
    #  — hip_hinge testindeki "lumbo-pelvik ritim" tam olarak bu ikisinin oranıdır.)
    "hip_flexion_right": lambda p: 180.0 - p.hip_flex - p.trunk_lean,
    "hip_flexion_left": lambda p: 180.0 - p.hip_flex - p.trunk_lean,
    "knee_flexion_right": lambda p: 180.0 - p.knee_flex,
    "knee_flexion_left": lambda p: 180.0 - p.knee_flex,
    "trunk_lean": lambda p: p.trunk_lean,
    "trunk_lateral_tilt": lambda p: p.lateral_bend,
    "tibia_inclination_right": lambda p: abs(p.hip_flex - p.knee_flex),
    "tibia_inclination_left": lambda p: abs(p.hip_flex - p.knee_flex),
    # --- L-016: oran metriklerinin analitik beklentileri ---
    # Topuğun parmak hizasından ne kadar yükseldiği, gövdeye oranlanmış.
    "heel_rise_right": lambda p: p.heel_lift / _B.torso,
    "heel_rise_left": lambda p: p.heel_lift / _B.torso,
    # Diz-ayakbileği dikey farkı: shank * cos(kalça - diz açısı) / gövde.
    # Kosinüs, uyluk ve baldır yönleri arasındaki açıdan gelir.
    "knee_height_right": lambda p: _B.shank * math.cos(math.radians(p.hip_flex - p.knee_flex)) / _B.torso,
    "knee_height_left": lambda p: _B.shank * math.cos(math.radians(p.hip_flex - p.knee_flex)) / _B.torso,
    # Omuz hattının frontal izdüşümü: gövde kameraya dönükken tam genişlik.
    # (yaw sapması A5'te ayrıca ölçülür, burada nötr duruş beklentisi)
    "shoulder_line_foreshortening": lambda p: _B.shoulder_width / _B.torso,
}

#: Tarama uzayı: her poz alanı için sınanacak değerler.
SWEEPS = {
    "shoulder_flex": [0, 15, 30, 45, 60, 90, 120, 150, 180],
    "elbow_flex": [0, 15, 30, 45, 60, 90],
    "hip_flex": [0, 15, 30, 45, 60, 90, 110],
    "knee_flex": [0, 15, 30, 45, 60, 90, 120],
    "trunk_lean": [0, 10, 20, 30, 45, 60],
    "lateral_bend": [0, 5, 10, 20, 30, 40],
    "heel_lift": [0.0, 0.01, 0.02, 0.04, 0.06],
}


@dataclass
class Row:
    metric: str
    field: str
    field_value: float          # taranan poz alanının değeri — A4/A5 eşleştirme anahtarı
    target: float               # beklenen değer; formülü olmayan metrikte NaN
    measured: float
    error: float                # |ölçüm - beklenen|; beklenen yoksa NaN


def _sweep(mset: mz.MetricSet, *, sigma: float = 0.0, seed: int = 0,
           body: synth.BodyProportions | None = None,
           yaw_deg: float = 0.0) -> list[Row]:
    """Tüm poz alanlarını tarayıp her metriğin hatasını topla."""
    rows: list[Row] = []
    for field, values in SWEEPS.items():
        for v in values:
            pose = synth.Pose(**{field: float(v)})
            frame = synth.build_frame(pose, body=body)
            if yaw_deg:
                frame = synth.yaw(frame, yaw_deg)
            if sigma:
                frame = synth.add_noise(frame, sigma, seed=seed + int(v))
            for mid, metric in mset.metrics.items():
                res = mz.evaluate(metric, frame)
                if not np.isfinite(res.value):
                    continue
                # L-016: beklenen-değer formülü olmayan metrikler de taranır.
                # A1-A3 (doğruluk) onları atlar, ama A4 (ölçek değişmezliği),
                # A5 (yaw) ve A9 (ölü metrik) kapsar — aksi halde kapının kör
                # noktasında kalırlar; L-011 tam o boşluktan geçmişti.
                exp = EXPECTED[mid](pose) if mid in EXPECTED else float("nan")
                err = abs(res.value - exp) if np.isfinite(exp) else float("nan")
                rows.append(Row(mid, field, float(v), exp, res.value, err))
    return rows


def _fmt(rows: list[Row], *, top: int = 6) -> str:
    worst = sorted(rows, key=lambda r: -r.error)[:top]
    return "\n".join(
        f"      {r.metric:<26} {r.field:<14} hedef={r.target:6.1f}  "
        f"ölçüm={r.measured:7.2f}  hata={r.error:5.2f}°"
        for r in worst
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()

    mset = mz.MetricSet.load(args.config)
    report: dict[str, object] = {
        "config": str(Path(args.config).name),
        "configVersion": mset.version,
        "thresholds": THRESHOLDS,
        "results": {},
    }
    verdicts: dict[str, bool] = {}

    print("=" * 78)
    print(f"G1-a — SAYISAL DOĞRULUK KAPISI · config {mset.set_id} v{mset.version}")
    print(f"{len(mset.metrics)} metrik · {sum(len(v) for v in SWEEPS.values())} poz noktası")
    print("=" * 78)

    # --- A1: gürültüsüz doğruluk ---
    clean = _sweep(mset)
    scored = [r for r in clean if np.isfinite(r.error)]
    a1 = float(max(r.error for r in scored))
    verdicts["A1"] = bool(a1 <= THRESHOLDS["A1_clean_error_deg"])
    print(f"\nA1  Gürültüsüz maksimum hata      : {a1:6.3f}° "
          f"(eşik ≤ {THRESHOLDS['A1_clean_error_deg']}°)  "
          f"{'✅ GEÇTİ' if verdicts['A1'] else '❌ KALDI'}")
    if not verdicts["A1"]:
        print("    En kötüler:")
        print(_fmt(scored))
    report["results"]["A1"] = {"value": a1, "pass": verdicts["A1"], "n": len(scored)}

    # --- A2/A3: gürültü dayanıklılığı ---
    for key, sigma in (("A2", 0.005), ("A3", 0.010)):
        errs: list[float] = []
        for seed in range(5):  # 5 farklı gürültü tohumu
            errs += [r.error for r in _sweep(mset, sigma=sigma, seed=seed * 100)
                     if np.isfinite(r.error)]
        med = float(statistics.median(errs))
        p95 = float(np.percentile(errs, 95))
        thr = THRESHOLDS[f"{key}_noise_{int(sigma*1000):03d}_median_deg"]
        verdicts[key] = bool(med <= thr)
        print(f"\n{key}  σ={sigma} gürültüde medyan hata : {med:6.3f}° "
              f"(eşik ≤ {thr}°)  {'✅ GEÇTİ' if verdicts[key] else '❌ KALDI'}")
        print(f"    p95={p95:.3f}°  n={len(errs)}")
        report["results"][key] = {
            "median": med, "p95": p95, "pass": verdicts[key], "n": len(errs)
        }

    # --- A4: vücut oranı bağımsızlığı ---
    base = {(r.metric, r.field, r.field_value): r.measured for r in clean}
    drifts: list[float] = []
    for k in (0.75, 1.30):
        for r in _sweep(mset, body=synth.BodyProportions().scaled(k)):
            ref = base.get((r.metric, r.field, r.field_value))
            if ref is not None:
                drifts.append(abs(r.measured - ref))
    a4 = float(max(drifts)) if drifts else float("nan")
    verdicts["A4"] = bool(a4 <= THRESHOLDS["A4_body_scale_drift_deg"])
    print(f"\nA4  Vücut ölçeği sapması (0.75x/1.3x): {a4:6.3f}° "
          f"(eşik ≤ {THRESHOLDS['A4_body_scale_drift_deg']}°)  "
          f"{'✅ GEÇTİ' if verdicts['A4'] else '❌ KALDI'}")
    report["results"]["A4"] = {"value": a4, "pass": verdicts["A4"], "n": len(drifts)}

    # --- A5: yaw duyarlılığı (eşiksiz, gerçeklik ölçümü) ---
    print(f"\nA5  Yaw (kamera hizası) duyarlılığı — EŞİKSİZ, kalibrasyon girdisi:")
    a5: dict[str, float] = {}
    for yd in (5, 10, 15, 30):
        ds = []
        for r in _sweep(mset, yaw_deg=yd):
            ref = base.get((r.metric, r.field, r.field_value))
            if ref is not None:
                ds.append(abs(r.measured - ref))
        med, mx = float(statistics.median(ds)), float(max(ds))
        a5[f"yaw_{yd}"] = med
        print(f"    ±{yd:>2}° sapmada  medyan {med:6.3f}°   maksimum {mx:6.3f}°")
    report["results"]["A5"] = a5

    # --- A6: güven kapısı sızdırmazlığı ---
    leaks = 0
    checked = 0
    critical = ("RIGHT_SHOULDER", "RIGHT_HIP", "RIGHT_KNEE", "RIGHT_ANKLE",
                "RIGHT_ELBOW", "LEFT_SHOULDER", "LEFT_HIP")
    for level in (0.0, 0.1, 0.3, 0.5, 0.59):
        for name in critical:
            frame = synth.occlude(
                synth.build_frame(synth.Pose(shoulder_flex=90, knee_flex=45)),
                (name,), level,
            )
            for mid, metric in mset.metrics.items():
                if name not in metric.points:
                    continue
                checked += 1
                res = mz.evaluate(metric, frame)
                if res.valid:  # düşük güvende skor ÜRETMEMELİYDİ
                    leaks += 1
                    print(f"    ❌ SIZINTI: {mid} · {name}@{level} · "
                          f"conf={res.confidence:.2f} ama valid=True")
    verdicts["A6"] = leaks == THRESHOLDS["A6_confidence_gate_leaks"]
    print(f"\nA6  Güven kapısı sızıntısı        : {leaks} / {checked} kontrol "
          f"(eşik = 0)  {'✅ GEÇTİ' if verdicts['A6'] else '❌ KALDI'}")
    report["results"]["A6"] = {"leaks": leaks, "checked": checked, "pass": verdicts["A6"]}

    # --- A9: ölü metrik avı (rev.3, kapının kendi bulgusundan doğdu) ---
    # Bir metrik hiçbir bozucuya tepki vermiyorsa sabit değer üretiyor demektir.
    # Sabit değer, makul GÖRÜNEN bir skora dönüşür ve kimse fark etmez — bu yüzden
    # sessiz yanlışların en tehlikeli sınıfıdır (L-011: angle_vertical+transverse).
    dead: list[str] = []
    uncovered: list[str] = []
    # Problar SWEEPS'ten TÜRETİLİR, elle yazılmaz: elle tutulan bir liste, yeni
    # bir poz parametresi eklendiğinde güncellenmeyi unutur ve o parametreye
    # bağlı metrik sessizce "ölü" görünür. (Bu tam olarak `heel_lift` eklenince
    # yaşandı — liste eskiydi, metrik masumdu.)
    probes = [
        synth.build_frame(synth.Pose(**{field: float(max(values))}))
        for field, values in SWEEPS.items()
    ]
    probes += [
        synth.yaw(synth.build_frame(synth.Pose()), 40),
        synth.build_frame(synth.Pose(), body=synth.BodyProportions().scaled(1.3)),
    ]
    for mid, metric in mset.metrics.items():
        if mid not in EXPECTED:
            uncovered.append(mid)
        vals = [mz.evaluate(metric, f).value for f in probes]
        finite = [v for v in vals if np.isfinite(v)]
        if len(finite) < 2 or (max(finite) - min(finite)) < 1e-6:
            dead.append(mid)
    verdicts["A9"] = not dead
    print(f"\nA9  Ölü metrik (sabit değer)      : {len(dead)} / {len(mset.metrics)} "
          f"(eşik = 0)  {'✅ GEÇTİ' if verdicts['A9'] else '❌ KALDI'}")
    if dead:
        for d in dead:
            print(f"    ❌ ÖLÜ: {d} — hiçbir bozucuya tepki vermiyor")
    if uncovered:
        print(f"    ⚠️  A1-A4 kapsamı dışında {len(uncovered)} metrik "
              f"(beklenen-değer formülü yok): {', '.join(uncovered)}")
        print("       Bunlar yalnız A9 ile korunuyor — doğruluk garantisi YOK.")
    report["results"]["A9"] = {
        "dead": dead, "uncovered": uncovered, "pass": verdicts["A9"]
    }

    # --- A7/A8: state machine — HENÜZ ÖLÇÜLMEDİ ---
    print("\nA7  State-machine doğru dizilim   : ⏳ ÖLÇÜLMEDİ (state machine G4'te yazılacak)")
    print("A8  State-machine geçersizlik     : ⏳ ÖLÇÜLMEDİ (aynı gerekçe)")
    report["results"]["A7_A8"] = "NOT_MEASURED_state_machine_pending"

    # --- Hüküm ---
    measured = ["A1", "A2", "A3", "A4", "A6", "A9"]
    passed = [k for k in measured if verdicts.get(k)]
    print("\n" + "=" * 78)
    if len(passed) == len(measured):
        verdict = "ŞARTLI GEÇTİ (A1-A6 tam; A7/A8 state machine bekliyor)"
        code = 0
    elif verdicts.get("A6") and verdicts.get("A1"):
        verdict = f"SINIRDA ({len(passed)}/{len(measured)}) — protokol §2.3 şartlı geçiş"
        code = 0
    else:
        verdict = f"KALDI ({len(passed)}/{len(measured)}) — A1 veya A6 ihlali toleranssız"
        code = 1
    print(f"HÜKÜM: {verdict}")
    print("=" * 78)
    report["verdict"] = verdict
    report["passed"] = passed
    report["measured"] = measured

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"\nJSON rapor: {args.json_out}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
