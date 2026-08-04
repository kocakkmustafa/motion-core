#!/usr/bin/env python
"""height_diff_norm çerçeve-tüketimi + beyan-guard testleri (L-190 / M-F-233).

Kanıtlanan iddialar:
  1. gravityYaw beyanlı height metriği için anatomik mod, ham-y yoluyla
     BİT-AYNI değer üretir (SI=[0,-1,0] tanımı gereği) — mevcut config'ler
     için davranış DEĞİŞMEDİ (M-F-53 şart-c: sessiz değişim yok).
  2. proximal beyanlı height metriği anatomik modda GÖVDE-EKSENİ dikeyini
     kullanır: eğik gövdede kamera-modundan ölçülür biçimde ayrışır ve el
     hesabıyla birebir örtüşür — beyan artık süs değil (pozitif kontrol);
     dik gövdede fark ~0 (negatif kontrol).
  3. Kamera modu (anatomical=False) eski formülle bire bir aynı kalır.
  4. Tüketilemeyen beyanlar YÜKLEME anında reddedilir: height_diff_norm +
     frameRef:none · düzlemsiz distance_norm + frameRef≠none ("süs beyan"
     kapısı, L-181 sınıfı). Geçerli beyanlar yüklenmeye devam eder.
  5. Dejenere gövde (torso~0) iki modda da dürüst valid=False + NaN verir.

Koşum (pytest gerekmez):
    ./.venv/bin/python tests/test_measures_frames.py
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mocore import geometry as geo  # noqa: E402
from mocore import landmarks as lmk  # noqa: E402
from mocore import measures as mz  # noqa: E402
from mocore import synth  # noqa: E402

FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    mark = "✅" if ok else "❌"
    print(f"{mark} {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        FAILS.append(name)


def _metric(mid: str, frame_ref: str, kind: str = "height_diff_norm",
            points=("RIGHT_WRIST", "RIGHT_HIP"), plane: str = "none") -> mz.MetricDef:
    return mz.MetricDef(id=mid, kind=kind, points=tuple(points), plane=plane,
                        frame_ref=frame_ref)


def _pt(f: geo.Frame, name: str) -> np.ndarray:
    return f.xyz[list(lmk.resolve(name))].mean(axis=0)


def _rand_frame(rng: np.random.Generator) -> geo.Frame:
    xyz = rng.normal(0.0, 0.4, size=(33, 3))
    ones = np.ones(33)
    return geo.Frame(xyz=xyz, visibility=ones, presence=ones, t_ms=0.0)


def main() -> int:
    rng = np.random.default_rng(190)

    # --- 1. gravityYaw bit-kimliği ---
    m_gy = _metric("h_gy", "gravityYaw")
    same = True
    for _ in range(200):
        f = _rand_frame(rng)
        cam = mz.evaluate(m_gy, f, anatomical=False, mask_invalid=False)
        ana = mz.evaluate(m_gy, f, anatomical=True, mask_invalid=False)
        if cam.value != ana.value and not (math.isnan(cam.value) and math.isnan(ana.value)):
            same = False
            break
    for yaw_deg in (0.0, 20.0, -35.0):
        f = synth.yaw(synth.build_frame(synth.Pose(trunk_lean=25.0, heel_lift=0.04)), yaw_deg)
        if mz.evaluate(m_gy, f, anatomical=False).value != mz.evaluate(m_gy, f, anatomical=True).value:
            same = False
    check("1. gravityYaw: anatomik == kamera (bit-aynı; 200 rastgele + yaw süpürmesi)", same)

    # --- 2. proximal pozitif/negatif kontrol ---
    m_px = _metric("h_px", "proximal")
    f = synth.build_frame(synth.Pose(trunk_lean=30.0))
    cam = mz.evaluate(m_px, f, anatomical=False)
    ana = mz.evaluate(m_px, f, anatomical=True)
    i = {n: lmk.NAMES.index(n) for n in ("LEFT_SHOULDER", "RIGHT_SHOULDER", "LEFT_HIP", "RIGHT_HIP")}
    mid_sh = (f.xyz[i["LEFT_SHOULDER"]] + f.xyz[i["RIGHT_SHOULDER"]]) / 2
    mid_hip = (f.xyz[i["LEFT_HIP"]] + f.xyz[i["RIGHT_HIP"]]) / 2
    si = mid_sh - mid_hip
    si = si / np.linalg.norm(si)
    expect = float(np.dot(_pt(f, "RIGHT_WRIST") - _pt(f, "RIGHT_HIP"), si)) / geo.torso_length(f.xyz)
    check("2a. proximal: anatomik değer el-hesabıyla örtüşür",
          abs(ana.value - expect) < 1e-12, f"{ana.value:.6f} vs {expect:.6f}")
    check("2b. proximal: eğik gövdede kamera-modundan ayrışır (pozitif kontrol)",
          abs(ana.value - cam.value) > 1e-3, f"Δ={abs(ana.value - cam.value):.4f}")
    f0 = synth.build_frame(synth.Pose(trunk_lean=0.0))
    d0 = abs(mz.evaluate(m_px, f0, anatomical=True).value
             - mz.evaluate(m_px, f0, anatomical=False).value)
    check("2c. proximal: dik gövdede fark ~0 (negatif kontrol)", d0 < 1e-9, f"Δ={d0:.2e}")

    # --- 3. kamera modu eski formülle bire bir ---
    ok3 = True
    for _ in range(50):
        f = _rand_frame(rng)
        got = mz.evaluate(m_gy, f, anatomical=False, mask_invalid=False).value
        t = geo.torso_length(f.xyz)
        old = -(((_pt(f, "RIGHT_WRIST"))[1] - (_pt(f, "RIGHT_HIP"))[1]) / t) if t > 1e-9 else float("nan")
        if got != old and not (math.isnan(got) and math.isnan(old)):
            ok3 = False
            break
    check("3. kamera modu: eski formülle bire bir (50 rastgele)", ok3)

    # --- 4. beyan-guard'ları ---
    try:
        _metric("h_none", "none")
        check("4a. height_diff_norm + frameRef:none REDDEDİLİR", False)
    except ValueError:
        check("4a. height_diff_norm + frameRef:none REDDEDİLİR", True)
    try:
        _metric("d_vacuous", "gravityYaw", kind="distance_norm", plane="none")
        check("4b. düzlemsiz distance_norm + frameRef≠none REDDEDİLİR", False)
    except ValueError:
        check("4b. düzlemsiz distance_norm + frameRef≠none REDDEDİLİR", True)
    ok4c, err = True, ""
    try:
        _metric("h_cam", "camera")
        _metric("h_px2", "proximal")
        _metric("d_ok", "none", kind="distance_norm", plane="none")
        _metric("d_fs", "camera", kind="distance_norm", plane="frontal")
    except ValueError as e:  # pragma: no cover
        ok4c, err = False, str(e)
    check("4c. geçerli beyanlar yüklenmeye devam eder", ok4c, err)

    # --- 5. dejenere gövde ---
    ones = np.ones(33)
    f_dg = geo.Frame(xyz=np.zeros((33, 3)), visibility=ones, presence=ones, t_ms=0.0)
    dg_cam = mz.evaluate(m_gy, f_dg, anatomical=False)
    dg_ana = mz.evaluate(m_gy, f_dg, anatomical=True)
    check("5. dejenere gövde: iki modda da valid=False + NaN",
          (not dg_cam.valid) and (not dg_ana.valid)
          and math.isnan(dg_cam.value) and math.isnan(dg_ana.value))

    # --- 6. anatomical_mode kanonik çözücü (M-F-241 flip-hazırlığı) ---
    ok6 = (mz.anatomical_mode(env=None) is mz.ANATOMICAL_DEFAULT
           if os.environ.get("MOCORE_ANATOMICAL") is None else True)
    ok6 = ok6 and mz.anatomical_mode(env="1") is True
    ok6 = ok6 and mz.anatomical_mode(env="0") is False
    ok6 = ok6 and mz.anatomical_mode(env="") is mz.ANATOMICAL_DEFAULT
    check("6a. anatomical_mode: '1'/'0'/boş/unset semantiği", ok6)
    # Çevirme-günü simülasyonu: varsayılan True olsa bile '0' opt-out'u YAŞAR
    # (M-F-53 şart-b: iki-mod koşulabilirliği çevirme sonrası da korunur).
    saved = mz.ANATOMICAL_DEFAULT
    try:
        mz.ANATOMICAL_DEFAULT = True
        ok6b = (mz.anatomical_mode(env=None) is True
                and mz.anatomical_mode(env="0") is False
                and mz.anatomical_mode(env="1") is True)
    finally:
        mz.ANATOMICAL_DEFAULT = saved
    check("6b. flip-simülasyonu: varsayılan=True iken '0' opt-out yaşıyor", ok6b)

    # --- 7. frame_basis damgası: sayı kaynağını üzerinde taşır ---
    f = synth.build_frame(synth.Pose(trunk_lean=20.0))
    b_cam = mz.evaluate(m_gy, f, anatomical=False).frame_basis
    b_gy = mz.evaluate(m_gy, f, anatomical=True).frame_basis
    m_camref = _metric("h_camref", "camera")
    b_camref = mz.evaluate(m_camref, f, anatomical=True).frame_basis
    b_inv = mz.evaluate(m_gy, f_dg, anatomical=True).frame_basis
    check("7a. kamera modu → 'camera'", b_cam == "camera", b_cam)
    check("7b. anatomik+gravityYaw → 'anatomical:gravityYaw'",
          b_gy == "anatomical:gravityYaw", b_gy)
    check("7c. anatomik modda camera-çerçeveli metrik 'camera' KALIR (dokunulmaz)",
          b_camref == "camera", b_camref)
    check("7d. geçersiz ölçüm de damga taşır", b_inv == "anatomical:gravityYaw", b_inv)

    print()
    if FAILS:
        print(f"KIRMIZI: {len(FAILS)} iddia düştü: {FAILS}")
        return 1
    print("HÜKÜM: GEÇTİ (çerçeve-tüketimi + beyan-guard'ları)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
