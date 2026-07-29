#!/usr/bin/env python3
"""Presence isolator — finds the window where a target joint sustains a
target range (M-F-85, third member of the isolator family).

Family (M-F-75/83): periodic repeat -> `movement_isolator` · static hold ->
`hold_isolator` · **phase-defined single demonstration -> presence_isolator**.
The downstream requirement (M-F-83's generalized rule — "the isolator's
criteria and measurements mirror the consumer's ACTUAL required set") for a
ROM-assessment reference take is Lissom's own `movementPresence` concept:
the TARGET joint reaches and SUSTAINS a target range. This tool answers that
question directly, at harvest time, on raw landmarks — before any app-side
JointSpec/angle-extraction pipeline runs.

WHY NOT THE OTHER TWO (L-151, measured on real footage): `movement_isolator`
looks for repetition; a single-rep ROM assessment clip is not periodic and,
worse, its full-body autocorrelation can latch onto something else that IS
periodic in the frame — a speech gesture, a weight shift — and hand back a
"periodic" window that is not the target movement at all. Measured on
Lissom's own overhead_reach footage: the tool's "most confident" window
(periodicity 0.98) carried a real `shoulder_flexion_right` trace of
116.9 -> 10.5 -> 6.8 -> 36.2 -> 114.0 -> 17.1 (deg, ~0.5s apart) — a
physiologically impossible sequence for a deliberate "raise slowly, hold two
seconds, lower" rep. `hold_isolator` looks for LOW energy; a ROM sweep is
defined by NOT being still (that is the entire point of the movement), so it
structurally cannot find the rep either.

DRIVING SIGNAL: a three-point angle (proximal -> joint -> distal, e.g.
HIP -> SHOULDER -> ELBOW for an overhead reach) computed directly from
normalized image-plane (x, y) landmark pairs — a faithful-enough PROXY for
the app's real metric (mocore's isotropic/world geometry) to locate WHERE a
rep happened; it is not used to produce the scored value itself, only to
find the clip. Immune to the gesture trap BY CONSTRUCTION: it does not look
for repetition or stillness, it looks for a value crossing a threshold and
STAYING there for `min_hold_s` — a 0.5s gesture spike never accumulates the
required dwell time, no matter how "periodic" it looks to a different
detector.

Reuses `hold_isolator`'s M-O-41/42/43 lessons rather than re-deriving them:
visibility + torso-quartet mirror (a window that would die at the canonical
CLI's confidence gate is not a window), and criteria/measurement scope
narrowed to the downstream consumer's actual required landmark set.

Self-check:  python3 tools/harvest_rig/presence_isolator.py --self-test
"""

from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass

from hold_isolator import SCOPES, _frame_visible

L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28


@dataclass
class PresenceWindow:
    start_frame: int
    end_frame: int
    seconds: float
    hold_seconds: float
    peak_value: float
    coverage: float

    def __str__(self) -> str:
        return (f"{self.start_frame}-{self.end_frame} ({self.seconds:.1f}s) "
                f"tutuş={self.hold_seconds:.1f}s tepe={self.peak_value:.1f} "
                f"kapsama={self.coverage:.2f}")


def _angle_deg(a: list[float], b: list[float], c: list[float]) -> float:
    """Unsigned angle at vertex b between rays b->a and b->c, in degrees.

    atan2(cross, dot) rather than acos(dot/|.||.|) — numerically stable
    near 0 and 180 degrees, where acos's derivative blows up and small
    landmark jitter would otherwise read as a large angle swing.
    """
    bax, bay = a[0] - b[0], a[1] - b[1]
    bcx, bcy = c[0] - b[0], c[1] - b[1]
    cross = bax * bcy - bay * bcx
    dot = bax * bcx + bay * bcy
    return math.degrees(abs(math.atan2(cross, dot)))


def _landmark_visible(p: list[float], *, min_vis: float = 0.5) -> bool:
    vis = p[3] if len(p) > 3 else 1.0
    return vis >= min_vis and 0.0 <= p[0] <= 1.0 and 0.0 <= p[1] <= 1.0


# A "point" in a driver triplet is either a single landmark index, or a pair
# of indices to average — the latter for virtual points (MID_HIP/MID_SHOULDER
# = the midpoint of L/R, not "whichever side"; averaging a pair of invisible
# landmarks would silently fabricate a point, so both must be visible).
def _resolve_point(lm: list[list[float]], point: int | tuple[int, int],
                   *, min_vis: float = 0.5) -> list[float] | None:
    if isinstance(point, tuple):
        a, b = lm[point[0]], lm[point[1]]
        if not (_landmark_visible(a, min_vis=min_vis)
                and _landmark_visible(b, min_vis=min_vis)):
            return None
        return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
    p = lm[point]
    return p if _landmark_visible(p, min_vis=min_vis) else None


def _driver_value(
    lm: list[list[float]],
    triplets: list[tuple[int | tuple[int, int], int | tuple[int, int],
                          int | tuple[int, int]]],
    *, op: str, min_vis: float = 0.5,
) -> float | None:
    """Best reading across candidate triplets (e.g. right/left side), or None.

    "Best" is op-directed: for a `>=` gate the higher candidate is the one
    that could satisfy it (a person may face either side to camera; only
    one side's triplet is usually reliably visible at a time), and
    symmetrically for `<=`. A triplet with any point unresolvable (below
    `min_vis` or out of frame) does not vote — an invisible elbow cannot
    report an angle.
    """
    vals = []
    for prox, joint, dist in triplets:
        pts = [_resolve_point(lm, p, min_vis=min_vis) for p in (prox, joint, dist)]
        if any(p is None for p in pts):
            continue
        vals.append(_angle_deg(*pts))
    if not vals:
        return None
    return max(vals) if op in (">", ">=") else min(vals)


def find_presence_windows(
    frames: list[list[list[float]] | None],
    *,
    fps: float,
    driver_triplets: list[tuple[int | tuple[int, int], int | tuple[int, int],
                                int | tuple[int, int]]],
    op: str,
    threshold_deg: float,
    min_hold_s: float,
    pad_s: float = 1.5,
    max_gap_s: float = 0.25,
    min_vis: float = 0.5,
    torso_min_vis: float = 0.6,
    scope: str = "upperBody",
    min_coverage: float = 0.8,
    max_windows: int = 3,
) -> list[PresenceWindow]:
    """Windows where a driver angle crosses `threshold_deg` and sustains it.

    Continuity mirrors Lissom's own `longest_hold_s` (fixture_check.py):
    a hold survives gaps up to `max_gap_s` (a dropped frame does not reset
    the clock) but longer gaps split the run. `pad_s` context is added on
    both sides so the returned clip carries the rise/return, not only the
    plateau — the reference builder aligns whole takes, not isolated peaks.
    [scope] mirrors the downstream JointSpec set (M-O-43); the torso
    quartet is enforced unconditionally by `_frame_visible` regardless of
    scope (normalization anchor).

    J-052-v2 (JabLab measured): a proportional `scope` share can pass while
    one landmark that will actually be SCORED sits at 0% visible the whole
    window. `hold_isolator._frame_visible`'s `required_ids` closes this for
    a single fixed joint set — but a `{side}`-templated driver has TWO
    candidate joint sets (right/left) and the lesson there is "at least one
    side's three points are ALL visible", not "these N points are ALL
    visible" (an AND over the union would wrongly demand both arms). That
    OR-of-ANDs guarantee is what `_driver_value` already enforces per
    triplet, per frame — a candidate with any unresolved point simply does
    not vote. Only when there is exactly ONE driver triplet (no side
    ambiguity) does `required_ids` unambiguously apply here too, so it is
    passed for defense-in-depth in that case only.
    """
    if fps <= 0:
        raise SystemExit("fps > 0 zorunlu — sessiz varsayım yok (doc 60 §1)")
    if op not in (">", ">=", "<", "<="):
        raise SystemExit(f"bilinmeyen op: {op!r}")
    ids = SCOPES[scope]
    cmp = {
        ">": lambda v: v > threshold_deg, ">=": lambda v: v >= threshold_deg,
        "<": lambda v: v < threshold_deg, "<=": lambda v: v <= threshold_deg,
    }[op]
    max_gap = max(1, round(max_gap_s * fps))
    pad = round(pad_s * fps)

    required_ids = None
    if len(driver_triplets) == 1:
        required_ids = [i for p in driver_triplets[0]
                        for i in (p if isinstance(p, tuple) else (p,))]

    vis_ok: list[bool] = []
    driver_val: list[float | None] = []
    for f in frames:
        ok = f is not None and _frame_visible(
            f, ids, required_ids=required_ids,
            min_vis=min_vis, torso_min_vis=torso_min_vis)
        vis_ok.append(ok)
        driver_val.append(
            _driver_value(f, driver_triplets, op=op, min_vis=min_vis)
            if ok else None)

    runs: list[tuple[int, int]] = []
    run_start: int | None = None
    gap = 0
    for i, v in enumerate(driver_val):
        holds = v is not None and cmp(v)
        if holds:
            if run_start is None:
                run_start = i
            gap = 0
        elif run_start is not None:
            gap += 1
            if gap > max_gap:
                runs.append((run_start, i - gap))
                run_start = None
                gap = 0
    if run_start is not None:
        runs.append((run_start, len(driver_val) - gap))

    windows: list[PresenceWindow] = []
    for s, e in runs:
        hold_s = (e - s) / fps
        if hold_s < min_hold_s:
            continue
        ws, we = max(0, s - pad), min(len(frames), e + pad)
        seg_vis = vis_ok[ws:we]
        coverage = sum(seg_vis) / len(seg_vis) if seg_vis else 0.0
        if coverage < min_coverage:
            continue
        peak = max((v for v in driver_val[s:e] if v is not None),
                   default=threshold_deg)
        windows.append(PresenceWindow(
            ws, we, (we - ws) / fps, round(hold_s, 2), round(peak, 1),
            round(coverage, 3)))

    windows.sort(key=lambda w: (-w.hold_seconds, -w.coverage))
    return windows[:max_windows]


def load_frames(path: str) -> tuple[list[list[list[float]] | None], float]:
    d = json.load(open(path, encoding="utf-8"))
    fps = d.get("recordingMeta", {}).get("fps")
    if not fps:
        raise SystemExit(f"fps yok: {path} — recordingMeta.fps zorunlu "
                         "(sessiz 30 varsayımı yasak, doc 60 §1)")
    frames: list[list[list[float]] | None] = []
    for f in d.get("frames", []):
        frames.append(f.get("lm") if f.get("detected") is not False else None)
    return frames, float(fps)


def presence_from_profile(profile_path: str, movement: str) -> dict:
    """`perMovement[movement].presence` — the driver spec, ONE vocabulary
    (M-F-60 pattern applied to presence, sibling of `.identity`).

    Landmark names resolve through the same BlazePose dictionary
    `triage_landmarks.py`/`fixture_check.py` use; `{side}` triplets expand
    to right+left so either side of camera counts (M-F-06: a reference
    take's "which side" is geometric, not assumed).
    """
    prof = json.loads(open(profile_path, encoding="utf-8").read())
    entry = (prof.get("perMovement") or {}).get(movement)
    if not isinstance(entry, dict) or "presence" not in entry:
        raise SystemExit(
            f"{profile_path}: perMovement['{movement}'].presence yok — "
            "presence_isolator bir sürücü olmadan koşamaz (uydurma yasak)"
        )
    spec = entry["presence"]
    required = {"proximal", "joint", "distal", "op", "thresholdDeg", "minHoldS",
               "status", "basis"}
    missing = required - set(spec)
    if missing:
        raise SystemExit(f"presence['{movement}']: eksik alan(lar) — {missing}")
    if spec["status"] == "pending":
        raise SystemExit(
            f"presence['{movement}']: status=pending — ölçülmemiş eşik "
            "isolatöre taşınmaz (G-043 dersi)"
        )
    return spec


NAME_TO_INDEX = {
    "LEFT_SHOULDER": L_SHOULDER, "RIGHT_SHOULDER": R_SHOULDER,
    "LEFT_ELBOW": L_ELBOW, "RIGHT_ELBOW": R_ELBOW,
    "LEFT_HIP": L_HIP, "RIGHT_HIP": R_HIP,
    "LEFT_KNEE": L_KNEE, "RIGHT_KNEE": R_KNEE,
    "LEFT_ANKLE": L_ANKLE, "RIGHT_ANKLE": R_ANKLE,
    "MID_HIP": (L_HIP, R_HIP), "MID_SHOULDER": (L_SHOULDER, R_SHOULDER),
}


def _resolve_triplets(
    spec: dict,
) -> list[tuple[int | tuple[int, int], int | tuple[int, int], int | tuple[int, int]]]:
    """`{side}`-templated landmark names -> concrete right/left triplets.

    `{side}` substitutes into the UPPERCASE BlazePose name (`{side}_SHOULDER`
    -> `RIGHT_SHOULDER`), mirroring `fixture_check.py`'s own `{side}`/mirror
    handling. `MID_*` names are virtual — `MID_HIP` resolves to the ACTUAL
    midpoint of `LEFT_HIP`/`RIGHT_HIP` (see `_resolve_point`), never to
    "whichever side": a trunk-direction reference should not silently swap
    which hip it means depending on which arm is being read.
    """
    def one(name: str, side: str) -> int | tuple[int, int]:
        n = name.replace("{side}", side.upper())
        if n not in NAME_TO_INDEX:
            raise SystemExit(f"bilinmeyen landmark adı: {n!r}")
        return NAME_TO_INDEX[n]

    names = (spec["proximal"], spec["joint"], spec["distal"])
    if any("{side}" in n for n in names):
        return [tuple(one(n, side) for n in names)
                for side in ("right", "left")]
    return [tuple(one(n, "right") for n in names)]


# --------------------------------------------------------------------------
# Synthetic landmark generation for self-test.
#
# Geometry: HIP directly below SHOULDER (hip.y > shoulder.y), so the
# shoulder->hip ray points "down". A driver angle of 0 deg places the elbow
# along that same ray from the shoulder (arm at the side); 180 deg places it
# on the opposite ray (arm overhead) — matching shoulder_flexion's own
# 0=down/180=overhead convention, so test thresholds read naturally.

def _synth_frame(flex_deg: float, *, torso_vis: float = 1.0,
                 driver_vis: float = 1.0, legs_vis: float = 1.0) -> list[list[float]]:
    lm = [[0.5, 0.9, 0.0, 1.0] for _ in range(33)]
    lm[R_HIP] = [0.55, 0.60, 0, torso_vis]
    lm[L_HIP] = [0.45, 0.60, 0, torso_vis]
    lm[R_SHOULDER] = [0.55, 0.35, 0, torso_vis]
    lm[L_SHOULDER] = [0.45, 0.35, 0, torso_vis]
    theta = math.radians(flex_deg)
    ex = 0.55 - 0.20 * math.sin(theta)
    ey = 0.35 + 0.20 * math.cos(theta)
    lm[R_ELBOW] = [ex, ey, 0, driver_vis]
    lm[L_ELBOW] = [0.45 - (ex - 0.55), ey, 0, driver_vis]
    for i in (L_KNEE, R_KNEE, L_ANKLE, R_ANKLE):
        lm[i] = [0.5, 0.85, 0, legs_vis]
    return lm


def _synth_rep(fps: float, *, rise_s: float, hold_s: float, fall_s: float,
              peak_deg: float, pre_s: float = 2.0, post_s: float = 2.0,
              **kw) -> list[list[list[float]]]:
    """0 -> peak (rise_s) -> peak (hold_s) -> 0 (fall_s), padded by rest."""
    frames: list[list[list[float]]] = []
    for _ in range(round(pre_s * fps)):
        frames.append(_synth_frame(0.0, **kw))
    n_rise = round(rise_s * fps)
    for i in range(n_rise):
        frames.append(_synth_frame(peak_deg * i / max(1, n_rise), **kw))
    for _ in range(round(hold_s * fps)):
        frames.append(_synth_frame(peak_deg, **kw))
    n_fall = round(fall_s * fps)
    for i in range(n_fall):
        frames.append(_synth_frame(peak_deg * (1 - i / max(1, n_fall)), **kw))
    for _ in range(round(post_s * fps)):
        frames.append(_synth_frame(0.0, **kw))
    return frames


def _synth_gesture_spike(fps: float, values_deg: list[float],
                         step_s: float = 0.5, **kw) -> list[list[list[float]]]:
    """Erratic value sequence at fixed intervals — L-151's measured trace."""
    frames: list[list[list[float]]] = []
    step_n = max(1, round(step_s * fps))
    for v in values_deg:
        for _ in range(step_n):
            frames.append(_synth_frame(v, **kw))
    return frames


TRIPLET = (R_HIP, R_SHOULDER, R_ELBOW)


def self_test() -> int:
    print("presence isolator — measured behaviour\n")
    print(f"{'scenario':<48}{'windows':>8}{'tutuş':>8}{'tepe':>8}")
    fails = 0

    def run(label, frames, fps, expect_found, **kw):
        nonlocal fails
        ws = find_presence_windows(
            frames, fps=fps, driver_triplets=[TRIPLET], op=">=",
            threshold_deg=140.0, min_hold_s=1.0, **kw)
        top = ws[0] if ws else None
        print(f"{label:<48}{len(ws):>8}"
              f"{(top.hold_seconds if top else 0):>8.2f}"
              f"{(top.peak_value if top else 0):>8.1f}")
        if bool(ws) != expect_found:
            fails += 1
            print(f"  ❌ beklenen: {'bulunur' if expect_found else 'reddedilir'}")
        return ws

    # 1. Hedef-hareket kabulü: yavaşça 150 dereceye çık, 2sn tut, in.
    run("hedef-hareket (yavaş kalk, 2sn tut, in)",
        _synth_rep(30, rise_s=1.5, hold_s=2.0, fall_s=1.5, peak_deg=150.0),
        30, True)

    # 2. KONUŞMA-JESTİ reddi — L-151'in ölçtüğü gerçek sıçrama, sentetikleştirildi.
    # (overhead_reach, Igzmhbghcd4/T8KTiE9bTZI'nin karışımı: hızlı, fizyolojik
    # olarak imkânsız sıçramalar, hiçbiri 1sn sürmüyor.)
    gesture = [116.9, 10.5, 6.8, 36.2, 114.0, 17.1, 9.4, 18.2, 118.9, 11.4,
              7.1, 74.7, 117.1, 0.3, 16.6]
    run("KONUŞMA JESTİ (L-151'in ölçtüğü sıçrama)",
        _synth_gesture_spike(30, gesture, step_s=0.5),
        30, False)

    # 3. Yavaş-sürüklenme: hedefe ulaşmak 6 saniye sürüyor (tipik 1,5sn'in
    # 4 katı) ama GERÇEK ve sürdürülüyor — velocity-tabanlı bir kapı
    # (L-135'in kusuru) bunu tanımaz; presence eşik+süre tabanlı olduğu
    # için tanımalı.
    run("yavaş-sürüklenme (6sn'de kalkan GERÇEK hareket — kabul)",
        _synth_rep(30, rise_s=6.0, hold_s=1.5, fall_s=6.0, peak_deg=150.0),
        30, True)

    # 4/5. Bel-üstü çekim — bacaklar yapısal kadraj dışı.
    waist_up = _synth_rep(30, rise_s=1.5, hold_s=2.0, fall_s=1.5,
                          peak_deg=150.0, legs_vis=0.05)
    run("bel-üstü çekim, scope=fullBody (haklı ret)",
        waist_up, 30, False, scope="fullBody")
    run("bel-üstü çekim, scope=upperBody (M-O-43 kabul)",
        waist_up, 30, True, scope="upperBody")

    # 6. İki-hız: aynı fiziksel tekrar 30 ve 60 fps'te aynı sınıfta bulunmalı.
    w30 = run("aynı tekrar @30fps",
             _synth_rep(30, rise_s=1.5, hold_s=2.0, fall_s=1.5, peak_deg=150.0),
             30, True)
    w60 = run("aynı tekrar @60fps",
             _synth_rep(60, rise_s=1.5, hold_s=2.0, fall_s=1.5, peak_deg=150.0),
             60, True)
    if w30 and w60 and not math.isclose(
            w30[0].hold_seconds, w60[0].hold_seconds, rel_tol=0.15, abs_tol=0.1):
        fails += 1
        print("  ❌ iki-hız tutuş-süresi sınıfı tutmadı")

    # M-O-42 aynası: gövde görünür ama güvenilir değil (piyano deseni).
    run("gövde var ama güvensiz (M-O-42 reddi)",
        _synth_rep(30, rise_s=1.5, hold_s=2.0, fall_s=1.5, peak_deg=150.0,
                  torso_vis=0.55),
        30, False)

    # 7. J-052-v2 (JabLab measured, hold_isolator's `required_ids`): a
    # proportional scope share does not guarantee any ONE landmark. The
    # actual hold (value >= 140) is UNAFFECTED here — only the padding
    # region (the rise/return context around it) loses the right elbow's
    # visibility, from just past the hold onward. Left elbow, both wrists,
    # both shoulders, both hips stay visible: 7/8 of upperBody (87.5%)
    # clears the proportional `min_share` (80%) easily. Without
    # `required_ids` this window would be found (verified: min_coverage=0
    # returns it, coverage=0.756 — high, not near-empty); WITH it, the
    # padding's coverage drops below `min_coverage` because the one
    # landmark the driver actually scores is the one going dark.
    j052 = _synth_rep(30, rise_s=1.5, hold_s=2.0, fall_s=1.5, peak_deg=150.0,
                      post_s=10.0)
    for fr in j052[175:]:
        fr[R_ELBOW] = [fr[R_ELBOW][0], fr[R_ELBOW][1], 0, 0.05]
    run("J-052-v2: oransal geçer (7/8) ama sürücü eklem PENCEREDE görünmez",
        j052, 30, False)

    if fails:
        print(f"\nSELF-TEST FAIL ({fails})")
        return 1
    print("\nSELF-TEST OK")
    print("\nThe 'KONUŞMA JESTİ' row is the one that matters: it is the "
          "exact trace movement_isolator scored 0.98-periodic on real "
          "footage (L-151) — presence_isolator rejects it by construction, "
          "not by a tuned exception.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()

    fixture = None
    profile = None
    movement = None
    scope = None
    i = 1
    while i < len(argv):
        if argv[i] == "--fixture":
            fixture, i = argv[i + 1], i + 2
        elif argv[i] == "--profile":
            profile, i = argv[i + 1], i + 2
        elif argv[i] == "--movement":
            movement, i = argv[i + 1], i + 2
        elif argv[i] == "--scope":
            scope, i = argv[i + 1], i + 2
        else:
            print(f"bilinmeyen argüman: {argv[i]}", file=sys.stderr)
            return 64
    if not fixture or not profile or not movement:
        print("kullanım: presence_isolator.py --fixture <landmarks.json> "
              "--profile <triage-profile.json> --movement <id> "
              "[--scope fullBody|upperBody|lowerBody] | --self-test",
              file=sys.stderr)
        return 64

    spec = presence_from_profile(profile, movement)
    triplets = _resolve_triplets(spec)
    frames, fps = load_frames(fixture)
    windows = find_presence_windows(
        frames, fps=fps, driver_triplets=triplets, op=spec["op"],
        threshold_deg=float(spec["thresholdDeg"]),
        min_hold_s=float(spec["minHoldS"]),
        scope=scope or "upperBody",
    )
    if not windows:
        print(f"pencere bulunamadı — {movement} ({spec['status']}: "
              f"{spec['basis']})")
        return 1
    for w in windows:
        print(w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
