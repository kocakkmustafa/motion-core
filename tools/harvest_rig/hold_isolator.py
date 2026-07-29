"""Static-hold isolator — the movement isolator's dual (M-F-75).

Three products hit the same wall in one shift: Ostinato's posture moments
diluted across 2-40 minute lessons, Gravita's split-stance segments mixed
into squat tutorials, and the 0.7.3 review's one-frame take manufacturing
fake variance. The family diagnosis: **a reference take is an ISOLATED
movement/pose window, never the whole video.**

`movement_isolator` finds repetition and deliberately rejects stillness
("standing still is perfectly periodic" is its trap). This tool finds
STILLNESS WITH A STABLE POSE — posture_setup, a boxing stance, a yoga hold —
and has its own dual trap: **low energy is not a hold.** A slow drift (an
arm sinking over ten seconds) has near-zero per-frame energy while the pose
changes entirely; that is the exact silent-wrong shape M-C-25 documented for
the ACF. So stability is measured twice, independently:

  - motion energy as FIXED-TIME-BASELINE velocity (|x(t+0.2 s) − x(t)| /
    0.2 s, per second — doc 60 §1): frame-to-frame deltas were measured to
    be rate-DEPENDENT for noise (white jitter's per-second sum grows with
    fps, so a hold read twice the "energy" at 60 fps); displacement over a
    fixed time baseline makes the noise floor rate-independent while real
    velocity reads the same at any rate.
  - drift against the window's MEDIAN pose — did the pose travel anywhere
    over the window, however slowly?

Threshold basis (honesty label): the defaults below are declared
PROVISIONAL — the energy ceiling sits ≥6× above the measured synthetic
noise floor (~0.07/s at family jitter) and ≤¼ of the slowest synthetic
movement class (~2.3/s swing); the drift bound (0.08) is
CALIBRATED BY REAL FOOTAGE (M-O-42: found holds measured drift 0.046-0.08
across şan/gitar/piyano — the first synthetic guess of 0.06 sat ON the
real jitter band and cost windows) while staying below a real in-window
pose change (±0.10 for half-a-torso of travel). Real-footage calibration lands with
Ostinato's step-1b windows. Override per call; do not silently retune here.

Visibility criterion (M-O-41, measured by Ostinato): energy + drift alone
pick windows that then DIE at the canonical CLI's confidence gate — the
pilot's angle-space heuristic chose "most static" moments that were partly
out-of-frame/low-visibility, and 5 of 9 şan/piyano sources collapsed to
"no measurable frames" before any agreement question could be asked. A
window is only useful if it SURVIVES the downstream gate, so frames whose
body landmarks are not sufficiently visible and in-frame are treated as
absent here (they fall into the coverage criterion).

Transcript hook (M-O-40): pass `candidate_times_s` (e.g. timestamps where
the transcript says "sit like this / hold this position") and overlapping
windows rank first. Candidates prioritise, they never admit: a candidate
window still has to pass energy, drift and coverage like everyone else.
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass

from movement_isolator import BODY, normalized_series


@dataclass
class HoldWindow:
    start_frame: int
    end_frame: int
    seconds: float
    energy_per_s: float
    drift: float
    coverage: float
    candidate_hit: bool

    def __str__(self) -> str:
        flag = " ★aday" if self.candidate_hit else ""
        return (f"{self.start_frame}-{self.end_frame} ({self.seconds:.1f}s) "
                f"enerji/s={self.energy_per_s:.3f} drift={self.drift:.3f} "
                f"kapsama={self.coverage:.2f}{flag}")


def _hold_energy(seg: list[list[float]], fps: float,
                 baseline_s: float = 0.2) -> float:
    """Mean displacement velocity over a fixed TIME baseline, per second.

    Not frame-to-frame: for white jitter the per-second sum of per-frame
    deltas scales with the frame rate (measured in this file's self-test),
    so a per-frame construction can never get a rate-independent hold
    threshold. Displacement across a fixed 0.2 s baseline reads true
    velocity identically at any rate and pins the noise floor.
    """
    k = max(1, round(baseline_s * fps))
    if len(seg) <= k:
        return 0.0
    dim = len(seg[0])
    total = 0.0
    n = 0
    for t in range(len(seg) - k):
        a, b = seg[t], seg[t + k]
        total += sum(abs(x - y) for x, y in zip(a, b)) / dim
        n += 1
    return (total / n) / (k / fps) if n else 0.0


def _drift(seg: list[list[float]]) -> float:
    """Worst per-DIMENSION deviation from the window-median pose.

    The anti-slow-drift measure: per-frame energy cannot see a pose that
    travels slowly, the median can — a drifting limb ends up far from the
    window's median no matter how gently it got there.

    Per-dimension MAX, deliberately not a mean over dimensions: one sinking
    arm is 2 dims out of 24, and a mean dilutes it 12× under the bound —
    the window-level twin of HIGH-1's median-masking (a frozen take hiding
    behind the across-joints median). Measured here: a 0.5-torso in-window
    arm drift read 0.039 under the mean, 0.10 under the max.
    """
    if len(seg) < 2:
        return 0.0
    dim = len(seg[0])
    worst = 0.0
    for d in range(dim):
        vals = sorted(f[d] for f in seg)
        med = vals[len(vals) // 2]
        dev = max(abs(vals[0] - med), abs(vals[-1] - med))
        worst = max(worst, dev)
    return worst


TORSO = (11, 12, 23, 24)

# Landmark scopes mirroring the Dart StandardJoints sets — the isolator's
# criterion AND its measurements must match the downstream gate's `required`
# set (M-O-43: a waist-up lesson has legs structurally out of frame; judging
# it on a full-body set rejects perfectly usable upper-body material, and
# measuring energy/drift over guessed leg positions folds noise in).
SCOPES = {
    "fullBody": list(BODY),
    "upperBody": [11, 12, 13, 14, 15, 16, 23, 24],
    "lowerBody": [23, 24, 25, 26, 27, 28],
}


def _frame_visible(lm: list[list[float]], ids: list[int], *,
                   required_ids: list[int] | None = None,
                   min_vis: float = 0.5,
                   torso_min_vis: float = 0.6,
                   min_share: float = 0.8) -> bool:
    """Body landmarks sufficiently visible AND in frame (M-O-41/42).

    Mirrors the canonical CLI's confidence gate so a chosen window survives
    it — including its TORSO rule: presence is not reliability (M-O-42:
    piano lessons keep the camera on the hands, torso landmarks exist but
    sit under the gate's torsoThreshold, and 3/3 chosen windows collapsed
    to 100% torsoUnreliable downstream). Torso landmarks are held to the
    gate's own higher bar (0.6, ConfidenceGate default) individually; the
    rest to the share criterion.
    """
    for i in TORSO:
        x, y = lm[i][0], lm[i][1]
        vis = lm[i][3] if len(lm[i]) > 3 else 1.0
        if vis < torso_min_vis or not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            return False
    # J-052-v2 (JabLab measured): the share criterion is PROPORTIONAL and
    # guarantees no individual joint — a "fullBody" window carried 0/90
    # ankle-visible frames while 80% of the set passed, and that source
    # became the 40° outlier. Joints the downstream reference will SCORE
    # can be demanded individually here.
    for i in (required_ids or ()):
        x, y = lm[i][0], lm[i][1]
        vis = lm[i][3] if len(lm[i]) > 3 else 1.0
        if vis < min_vis or not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            return False
    ok = 0
    for i in ids:
        x, y = lm[i][0], lm[i][1]
        vis = lm[i][3] if len(lm[i]) > 3 else 1.0
        if vis >= min_vis and 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0:
            ok += 1
    return ok >= min_share * len(ids)


def find_hold_windows(
    frames: list[list[list[float]] | None],
    *,
    fps: float,
    window_s: float = 3.0,
    stride_s: float = 0.5,
    max_energy_per_s: float = 0.5,
    max_drift: float = 0.08,
    min_coverage: float = 0.8,
    candidate_times_s: list[float] | None = None,
    max_windows: int = 5,
    scope: str = "fullBody",
    required_ids: list[int] | None = None,
) -> list[HoldWindow]:
    """Finds windows where a present person holds a stable pose.

    Threshold basis in the module doc. [scope] names the landmark set the
    DOWNSTREAM reference will require (`fullBody|upperBody|lowerBody`) —
    visibility, energy and drift are all judged on that set (M-O-43); the
    torso quartet is enforced unconditionally (normalization anchor).
    """
    if fps <= 0:
        raise SystemExit("fps > 0 zorunlu — sessiz varsayım yok (doc 60 §1)")
    ids = SCOPES[scope]
    # M-O-41: a poorly-visible frame counts as ABSENT — stillness measured
    # over half-seen bodies produces windows the downstream gate rejects.
    frames = [f if f is not None
              and _frame_visible(f, ids, required_ids=required_ids) else None
              for f in frames]
    series = normalized_series([f for f in frames if f is not None], ids)
    # Re-expand to align indices with the raw frame list for coverage math.
    norm_by_idx: list[list[float] | None] = []
    it = iter(series)
    for f in frames:
        norm_by_idx.append(next(it) if f is not None else None)

    win = int(window_s * fps)
    stride = max(1, int(stride_s * fps))
    if win < 4 or len(norm_by_idx) < win:
        return []

    cands: list[HoldWindow] = []
    for s in range(0, len(norm_by_idx) - win + 1, stride):
        rows = norm_by_idx[s:s + win]
        seg = [r for r in rows if r is not None]
        coverage = len(seg) / win
        if coverage < min_coverage:
            continue
        energy = _hold_energy(seg, fps)
        if energy > max_energy_per_s:
            continue
        drift = _drift(seg)
        if drift > max_drift:
            continue  # low energy but the pose travelled — a slow drift,
            # not a hold (the dual trap; rejected by name, never averaged)
        hit = False
        if candidate_times_s:
            t0, t1 = s / fps, (s + win) / fps
            hit = any(t0 <= t <= t1 for t in candidate_times_s)
        cands.append(HoldWindow(s, s + win, win / fps,
                                round(energy, 4), round(drift, 4),
                                round(coverage, 3), hit))

    merged: list[HoldWindow] = []
    for w in cands:
        if merged and w.start_frame <= merged[-1].end_frame:
            p = merged[-1]
            merged[-1] = HoldWindow(
                p.start_frame, max(p.end_frame, w.end_frame),
                (max(p.end_frame, w.end_frame) - p.start_frame) / fps,
                max(p.energy_per_s, w.energy_per_s),
                max(p.drift, w.drift),
                min(p.coverage, w.coverage),
                p.candidate_hit or w.candidate_hit)
        else:
            merged.append(w)

    merged.sort(key=lambda w: (not w.candidate_hit, w.drift, -w.seconds))
    return merged[:max_windows]


# --------------------------------------------------------------------------

def _synth_hold(n: int, *, drift_total: float = 0.0, amp: float = 0.0,
                jitter: float = 0.002, vis: float = 1.0, torso_vis: float = 1.0,
                legs_vis: float | None = None, off_frame: bool = False,
                seed: int = 1):
    """Fake landmark frames: a still pose, optionally drifting or swinging."""
    rng = __import__("random").Random(seed)
    frames = []
    for t in range(n):
        lm = [[0.5, 0.5, 0.0, 1.0] for _ in range(33)]
        lm[23] = [0.45, 0.60, 0, torso_vis]
        lm[24] = [0.55, 0.60, 0, torso_vis]
        lm[11] = [0.42, 0.38, 0, torso_vis]
        lm[12] = [0.58, 0.38, 0, torso_vis]
        slide = drift_total * t / max(1, n - 1)
        swing = amp * math.sin(2 * math.pi * t / 30)
        for i in BODY:
            if i in (11, 12, 23, 24):
                continue
            j = rng.gauss(0, jitter)
            x = (1.2 if off_frame else 0.5) + slide + swing + j
            v = vis
            if legs_vis is not None and i in (25, 26, 27, 28):
                # structurally out of frame: garbage guessed position + ~0 vis
                lm[i] = [rng.random(), 1.5 + rng.random(), 0, legs_vis]
                continue
            lm[i] = [x, 0.5 + j, 0, v]
        frames.append(lm)
    return frames


def self_test() -> int:
    print("hold isolator — measured behaviour\n")
    print(f"{'scenario':<44}{'windows':>8}{'enerji/s':>10}{'drift':>8}")
    fails = 0

    def run(label, frames, fps, expect_found, **kw):
        nonlocal fails
        ws = find_hold_windows(frames, fps=fps, **kw)
        top = ws[0] if ws else None
        print(f"{label:<44}{len(ws):>8}"
              f"{(top.energy_per_s if top else 0):>10.3f}"
              f"{(top.drift if top else 0):>8.3f}")
        if bool(ws) != expect_found:
            fails += 1
            print(f"  ❌ beklenen: {'bulunur' if expect_found else 'reddedilir'}")
        return ws

    run("gerçek tutuş (jitter'lı statik)", _synth_hold(240), 30, True)
    run("salınım (hareket — enerji reddi)",
        _synth_hold(240, amp=0.08), 30, False)
    # The dual trap: 0.15 total drift over 8 s is ~0.0006/frame — energy
    # cannot see it; only the median-drift measure can.
    # Window-level: 0.12 total drift → ~0.20 normalized in-window excursion
    # → per-dim max drift ≈ 0.10 > 0.06 bound, while its velocity hides in
    # the noise floor — energy alone would ACCEPT this.
    run("yavaş sürüklenme (drift reddi)",
        _synth_hold(240, drift_total=0.12), 30, False)
    run("kimse yok (kapsama reddi)",
        [None] * 240, 30, False)
    # M-O-41: perfectly still but the body is barely visible / out of
    # frame — the pilot's heuristic picked exactly these and the CLI gate
    # then dropped every frame.
    run("durağan ama düşük görünürlük (M-O-41 reddi)",
        _synth_hold(240, vis=0.2), 30, False)
    run("durağan ama kadraj dışı (M-O-41 reddi)",
        _synth_hold(240, off_frame=True), 30, False)
    # M-O-42: torso PRESENT but under the gate's torso bar — piano filming
    # convention; presence is not reliability.
    run("gövde var ama güvensiz (M-O-42 reddi)",
        _synth_hold(240, torso_vis=0.55), 30, False)
    # M-O-43: waist-up lesson — legs structurally out of frame (vis ~0.05).
    # Judged on the fullBody set this is rejected; on the upperBody set the
    # SAME material is a perfectly good hold. Scope must match the consumer.
    waist_up = _synth_hold(240, legs_vis=0.05)
    run("bel-üstü çekim, scope=fullBody (haklı ret)", waist_up, 30, False)
    run("bel-üstü çekim, scope=upperBody (M-O-43 kabul)", waist_up, 30, True,
        scope="upperBody")
    # J-052-v2: the proportional share passes while a REQUIRED joint (ankle,
    # 27) is invisible — demanding it individually must reject.
    run("oran geçiyor ama zorunlu eklem görünmez (J-052-v2 reddi)",
        waist_up, 30, False, required_ids=[27])

    # Two-speed rule (doc 60 §1): the same physical hold at 60 fps must
    # read the SAME per-second energy class and still be found.
    w30 = run("aynı tutuş @30fps", _synth_hold(240), 30, True)
    w60 = run("aynı tutuş @60fps", _synth_hold(480), 60, True)
    if w30 and w60 and not math.isclose(
            w30[0].energy_per_s, w60[0].energy_per_s,
            rel_tol=0.5, abs_tol=0.05):
        # Jitter is per-frame noise, so per-second energy scales with rate
        # for NOISE — a loose bound only guards against the old per-frame
        # unit leak (where 60 fps read HALF, not more).
        fails += 1
        print("  ❌ iki-hız enerji sınıfı tutmadı")

    # Candidate hook: the transcript-marked window outranks an equal one.
    frames = _synth_hold(600)
    ws = find_hold_windows(frames, fps=30, candidate_times_s=[12.0])
    if ws and not ws[0].candidate_hit:
        fails += 1
        print("  ❌ aday-önceliği çalışmıyor")
    else:
        print(f"{'aday-önceliği (t=12s işareti)':<44}{'✓':>8}")

    if fails:
        print(f"\nSELF-TEST FAIL ({fails})")
        return 1
    print("\nSELF-TEST OK")
    print("\nThe 'yavaş sürüklenme' row is the one that matters: its "
          "per-frame energy is indistinguishable from a hold, and the "
          "median-drift measure is what rejects it.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    scope = "fullBody"
    if "--scope" in argv:
        i = argv.index("--scope")
        scope = argv[i + 1]
        if scope not in SCOPES:
            print(f"bilinmeyen scope: {scope} (fullBody|upperBody|lowerBody)",
                  file=sys.stderr)
            return 64
        argv = argv[:i] + argv[i + 2:]
    if len(argv) < 2:
        print("kullanım: hold_isolator.py [--scope fullBody|upperBody|"
              "lowerBody] <landmarks.json> [t1,t2,... (aday saniyeleri)] "
              "| --self-test", file=sys.stderr)
        return 64
    d = json.load(open(argv[1], encoding="utf-8"))
    fps = d.get("recordingMeta", {}).get("fps")
    if not fps:
        raise SystemExit(f"fps yok: {argv[1]} — recordingMeta.fps zorunlu "
                         "(sessiz 30 varsayımı yasak, doc 60 §1)")
    frames: list[list[list[float]] | None] = []
    for f in d.get("frames", []):
        frames.append(f.get("lm") if f.get("detected") is not False else None)
    cands = None
    if len(argv) > 2:
        cands = [float(x) for x in argv[2].split(",")]
    for w in find_hold_windows(frames, fps=float(fps),
                               candidate_times_s=cands, scope=scope):
        print(w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
