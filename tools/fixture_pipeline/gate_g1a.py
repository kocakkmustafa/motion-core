#!/usr/bin/env python
"""G1-a — Sayısal doğruluk kapısı koşucusu.

Protokol: ventures/lissom/app/docs/G1-V0-KAPI-PROTOKOLU.md §2
Eşikler ÖLÇÜMDEN ÖNCE yazıldı; bu betik onları yalnız OKUR, değiştirmez.

Çalıştırma:
    ./.venv/bin/python gate_g1a.py --config ../../../../lissom/app/config/metrics/lissom-metrics.v1.json
"""

from __future__ import annotations

import argparse
import os
import json
import statistics
from dataclasses import dataclass
from pathlib import Path

import math

import numpy as np

from mocore import geometry as geo
from mocore import measures as mz
from mocore import phases as ph
from mocore import synth

#: M-F-53 şart (b): kapı hem eski (dünya ekseni) hem yeni (anatomik) izdüşümle
#: koşulabilmeli ki göçün kalibre eşiklere etkisi ÖLÇÜLEBİLSİN.
ANATOMICAL = os.environ.get("MOCORE_ANATOMICAL") == "1"

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



# --------------------------------------------------------------------------
# A7/A8 — faz makinesi senaryoları
# --------------------------------------------------------------------------
#
# Her senaryo bir poz alanını hedef aralıkta gezdirir. Ters eşleme (metrik ->
# poz alanı) yalnız doğrudan sürülebilen testler için yazıldı; türev metrikli
# testler (reach_depth, knee_height, foreshortening) kapsam DIŞI ve rapor bunu
# isimle söyler — kapsanmayanı kapsanmış göstermek, kapının kendi zaafıdır.
P = synth.Pose

#: testId -> (poz alanı, dinlenme değeri, tepe değeri)
#: testId -> (poz alanı, dinlenme, tepe, sabit tutulacak diğer alanlar)
PHASE_DRIVERS = {
    "overhead_reach":  ("shoulder_flex", 10.0, 160.0, {}),
    "deep_squat":      ("knee_flex", 5.0, 120.0, {}),
    # Kollar baş üstünde: `ready` koşulu çok-metrikli (all) — diz düz VE kol yukarı.
    "overhead_squat":  ("knee_flex", 5.0, 110.0, {"shoulder_flex": 165.0}),
    "hip_hinge":       ("trunk_lean", 3.0, 70.0, {}),
    "lateral_bend":    ("lateral_bend", 2.0, 35.0, {}),
}


def _hold(pose, n):
    return synth.ramp(pose, pose, n)


def _scenario_frames(field: str, rest: float, peak: float, kind: str,
                     *, confidence: float = 1.0, fixed: dict | None = None) -> list:
    """Senaryo poz dizisi üret; kare akışına çevir."""
    fixed = fixed or {}
    mk = lambda v: P(**{field: float(v), **fixed})
    if kind == "correct":
        poses = (_hold(mk(rest), 20) + synth.ramp(mk(rest), mk(peak), 45)
                 + _hold(mk(peak), 60) + synth.ramp(mk(peak), mk(rest), 45)
                 + _hold(mk(rest), 20))
    elif kind == "abandoned":
        # Yarıda bırakma: tepeye çıkar, orada kalır, geri dönmez.
        poses = (_hold(mk(rest), 20) + synth.ramp(mk(rest), mk(peak), 45)
                 + _hold(mk(peak), 400))
    elif kind == "never_starts":
        poses = _hold(mk(rest), 200)
    else:
        raise ValueError(kind)
    frames = synth.sequence(poses, fps=30.0)
    if confidence < 1.0:
        frames = [synth.occlude(f, tuple(synth.lm.NAMES), confidence) for f in frames]
    return frames


def measure_a7_a8(mset, phase_path: str) -> dict:
    """A7: doğru dizilim tanınıyor mu · A8: hatalı dizilim doğru kodla bitiyor mu."""
    tests = ph.load_phase_set(phase_path)
    a7_pass, a7_total, a7_fail = 0, 0, []
    a8_pass, a8_total, a8_fail = 0, 0, []
    uncovered = sorted(set(tests) - set(PHASE_DRIVERS))

    for tid, (field, rest, peak, fixed) in PHASE_DRIVERS.items():
        if tid not in tests:
            continue
        runner = ph.PhaseRunner(tests[tid], mset)

        # --- A7: doğru dizilim tamamlanmalı ---
        a7_total += 1
        r = runner.run(_scenario_frames(field, rest, peak, "correct", fixed=fixed))
        if r.outcome == ph.COMPLETED and r.measured_at_ms is not None:
            a7_pass += 1
        else:
            a7_fail.append(f"{tid}: {r.outcome}, fazlar={'→'.join(r.phase_sequence) or '-'}")

        # --- A8a: yarıda bırakma -> timeout (park etmemeli) ---
        a8_total += 1
        r = runner.run(_scenario_frames(field, rest, peak, "abandoned", fixed=fixed))
        if r.outcome in (ph.TIMED_OUT, ph.ABORTED):
            a8_pass += 1
        else:
            a8_fail.append(f"{tid}/abandoned: {r.outcome} (timeout bekleniyordu)")

        # --- A8b: düşük güven -> abort veya hiç başlamama ---
        a8_total += 1
        r = runner.run(_scenario_frames(field, rest, peak, "correct",
                                        confidence=0.2, fixed=fixed))
        if r.outcome != ph.COMPLETED:
            a8_pass += 1
        else:
            a8_fail.append(f"{tid}/low-confidence: düşük güvende TAMAMLANDI — kaçak")

    return {"a7": (a7_pass, a7_total, a7_fail), "a8": (a8_pass, a8_total, a8_fail),
            "uncovered": uncovered}


def measure_a10(mset, phase_path: str) -> dict:
    """A10 — nötr/doğru duruşta hiçbir abort tetiklenmemeli.

    Guard koşulları "kusur var mı" sorusunu sorar; kusursuz bir duruşta
    tetikleniyorsa koşul terstir veya eşiği anlamsızdır. Bu, ölü-metrik
    ailesinden bir hata: guard vardır ama hiçbir zaman doğru çalışamaz.
    Gerçek örnek (L-072): `lateral_bend`'in TORSO_ROTATED guard'ı
    `foreshortening > 0.15` yazılmıştı; metrik nötrde 0.80 ve rotasyonda
    KÜÇÜLÜR — yani koşul her duruşta doğruydu ve test hep abort ediyordu.
    """
    tests = ph.load_phase_set(phase_path)
    bad: list[str] = []
    checked = 0
    for tid, tdef in tests.items():
        # "Nötr" testten teste değişir: overhead squat'ın doğru başlangıcı
        # kollar YUKARIDA. Test-özel sabit alanlar uygulanmazsa A10 kendi
        # yanlış alarmını üretir.
        fixed = PHASE_DRIVERS.get(tid, (None, None, None, {}))[3]
        neutral = synth.build_frame(P(**fixed))
        runner = ph.PhaseRunner(tdef, mset)
        for phase in tdef["phases"]:
            cond = phase.get("abort")
            if not cond:
                continue
            # Güven koşulları nötr karede zaten sağlanmaz; onları atla.
            if cond.get("kind") == "confidence":
                continue
            checked += 1
            try:
                if runner._holds(cond, neutral, neutral, 0.0):
                    bad.append(
                        f"{tid}.{phase['id']} ({phase.get('abortCode')}): "
                        f"NÖTR duruşta tetikleniyor — koşul ters veya eşik anlamsız"
                    )
            except Exception as exc:  # noqa: BLE001
                bad.append(f"{tid}.{phase['id']}: koşul değerlendirilemedi — {exc}")
    return {"bad": bad, "checked": checked}


def measure_a11(mset) -> dict:
    """A11 — beyan edilen taban, kusursuz durumda ölçülenle uyuşuyor mu (M-F-34).

    Tolerans taban-göreli yorumlanır; taban yanlış beyan edilmişse her eşik
    yanlış yerden ölçülür. L-072 bunun canlı örneğiydi: tabanı 0,80 olan bir
    metrik sıfır sanılıp guard `> 0.15` yazılmış, guard her duruşta tetiklenmişti.
    """
    neutral = synth.build_frame(P())
    bad: list[str] = []
    checked = 0
    for mid, md in mset.metrics.items():
        if md.baseline is None:
            continue
        checked += 1
        declared = float(md.baseline)
        actual = mz.evaluate(md, neutral, anatomical=ANATOMICAL).value
        scale = max(abs(declared), 0.01)
        if abs(actual - declared) / scale > 0.01:
            bad.append(f"{mid}: beyan {declared:.4f} · ölçüm {actual:.4f}")
    return {"bad": bad, "checked": checked}


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
                res = mz.evaluate(metric, frame, anatomical=ANATOMICAL)
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
                res = mz.evaluate(metric, frame, anatomical=ANATOMICAL)
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
        vals = [mz.evaluate(metric, f, anatomical=ANATOMICAL).value for f in probes]
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

    # --- A7/A8: faz makinesi (taslak köprü; core sürümü çıkınca devreder) ---
    phase_path = str(Path(args.config).parent.parent / "phases" / "lissom-phases.v1.json")
    if Path(phase_path).exists():
        r78 = measure_a7_a8(mset, phase_path)
        (p7, t7, f7), (p8, t8, f8) = r78["a7"], r78["a8"]
        verdicts["A7"] = p7 == t7
        verdicts["A8"] = p8 == t8
        print(f"\nA7  Doğru dizilim tanıma          : {p7}/{t7} test  "
              f"{'✅ GEÇTİ' if verdicts['A7'] else '❌ KALDI'}")
        for line in f7:
            print(f"    ❌ {line}")
        print(f"A8  Hatalı dizilim doğru bitiyor  : {p8}/{t8} senaryo  "
              f"{'✅ GEÇTİ' if verdicts['A8'] else '❌ KALDI'}")
        for line in f8:
            print(f"    ❌ {line}")
        if r78["uncovered"]:
            print(f"    ⚠️  Senaryo üreteci OLMAYAN {len(r78['uncovered'])} test: "
                  f"{', '.join(r78['uncovered'])}")
            print("       Türev metrikli testler; A7/A8 bunları KAPSAMIYOR.")
        report["results"]["A7"] = {"pass": p7, "total": t7, "failures": f7}
        report["results"]["A8"] = {"pass": p8, "total": t8, "failures": f8,
                                   "uncovered": r78["uncovered"]}

        r10 = measure_a10(mset, phase_path)
        verdicts["A10"] = not r10["bad"]
        print(f"A10 Nötr duruşta yanlış abort    : {len(r10['bad'])} / "
              f"{r10['checked']} guard  "
              f"{'✅ GEÇTİ' if verdicts['A10'] else '❌ KALDI'}")
        for line in r10["bad"]:
            print(f"    ❌ {line}")
        report["results"]["A10"] = r10

        r11 = measure_a11(mset)
        if r11["checked"]:
            verdicts["A11"] = not r11["bad"]
            print(f"A11 Taban beyanı doğru mu        : {len(r11['bad'])} / "
                  f"{r11['checked']} metrik  "
                  f"{'✅ GEÇTİ' if verdicts['A11'] else '❌ KALDI'}")
            for line in r11["bad"]:
                print(f"    ❌ {line}")
            report["results"]["A11"] = r11
    else:
        print("\nA7/A8: faz config bulunamadı — ÖLÇÜLMEDİ")
        report["results"]["A7_A8"] = "NOT_MEASURED_no_phase_config"

    # --- Hüküm ---
    measured = ["A1", "A2", "A3", "A4", "A6", "A9"] + [k for k in ("A7", "A8", "A10", "A11") if k in verdicts]
    passed = [k for k in measured if verdicts.get(k)]
    print("\n" + "=" * 78)
    if len(passed) == len(measured):
        verdict = "GEÇTİ (A1-A9 tam)" if {"A7","A8"} <= set(verdicts) else "ŞARTLI GEÇTİ (A1-A6 tam; A7/A8 bekliyor)"
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
