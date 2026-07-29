#!/usr/bin/env python3
"""Finds the stretch of a tutorial where the step is actually being danced.

APPLICABILITY (M-F-31 — measure before adopting): the signal here is
periodicity, so this tool is for REPETITIVE content — dance steps, reps,
strike combinations. It is the wrong question for single-direction ROM
sweeps, one-off holds (plank, balance) and 3-rep assessment clips: Lissom
measured that on such material the high "periodicity" scores are low-lag
autocorrelation artifacts (adjacent frames always correlate), with the
reported period pinned to the search floor. For phase-defined tests the
movement window is the phase state machine's own output, not a pre-filter.

The harvest gates answer "is this footage usable" — framing, sharpness, camera
angle. None of them answer "is this part the movement", and that gap broke the
first real reference build (M-C-16): three takes that all passed the camera gate
still produced DTW costs of 0.06-0.18 and near-zero joint dispersion, because
most of each window was the instructor standing and talking. Consensus and
variance-derived tolerance cannot work on material that is mostly explanation.

The signal used here is periodicity. A dance step is, by definition, a movement
that repeats — an instructor demonstrating one repeats it several times, and
almost nothing else in a tutorial does.

The trap this has to avoid is that **standing still is perfectly periodic**: a
static pose correlates with itself at every lag. Periodicity alone would score
the talking sections highest of all. So a window qualifies only when it is both
repeating AND moving.

Self-check:  python3 tools/movement_isolator.py --self-test
"""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import sys
from dataclasses import dataclass

L_SHOULDER, R_SHOULDER = 11, 12
L_HIP, R_HIP = 23, 24

# Joints that carry a dance step. Face and hand-detail landmarks are excluded:
# they are noisy and they move while the instructor talks, which is exactly the
# section we are trying to reject.
BODY = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]


@dataclass
class MovementWindow:
    start_frame: int
    end_frame: int
    seconds: float
    periodicity: float
    motion_energy: float
    period_s: float

    def __str__(self) -> str:
        return (f"{self.start_frame}-{self.end_frame} ({self.seconds:.1f}s) "
                f"per={self.periodicity:.2f} enerji={self.motion_energy:.4f} "
                f"periyot={self.period_s:.2f}s")


def normalized_series(frames: list[list[list[float]]]) -> list[list[float]]:
    """Torso-relative body landmarks, flattened per frame.

    Same normalization idea as the engine: origin at the hip midpoint, scaled by
    torso length, so that a dancer stepping toward the camera does not read as
    movement.
    """
    out = []
    for lm in frames:
        hx = (lm[L_HIP][0] + lm[R_HIP][0]) / 2
        hy = (lm[L_HIP][1] + lm[R_HIP][1]) / 2
        sx = (lm[L_SHOULDER][0] + lm[R_SHOULDER][0]) / 2
        sy = (lm[L_SHOULDER][1] + lm[R_SHOULDER][1]) / 2
        torso = math.hypot(sx - hx, sy - hy)
        if torso < 1e-6:
            out.append(None)
            continue
        row = []
        for i in BODY:
            row.append((lm[i][0] - hx) / torso)
            row.append((lm[i][1] - hy) / torso)
        out.append(row)
    return out


def _motion_energy(seg: list[list[float]]) -> float:
    """Mean per-frame change — how much the body is actually moving."""
    if len(seg) < 2:
        return 0.0
    total = 0.0
    for a, b in zip(seg, seg[1:]):
        total += sum(abs(x - y) for x, y in zip(a, b)) / len(a)
    return total / (len(seg) - 1)


def _periodicity(
    seg: list[list[float]], lo: int, hi: int, *, min_prominence: float = 0.08
) -> tuple[float, int]:
    """Periodicity as a *prominent local peak* of the autocorrelation.

    Centring is what stops a held pose from scoring 1.0: subtracting the window
    mean leaves a static segment with almost no signal to correlate, so its
    score collapses instead of saturating.

    M-C-25 (P0, measured on real harvest footage): taking the ACF's *global
    maximum* over the lag range is structurally wrong for real recordings.
    Continuous motion makes adjacent frames similar, so the ACF **decays
    monotonically** and its maximum sits at the smallest allowed lag on
    every non-repetitive segment — the reported "period" was the search
    floor, not a measurement (4/5 selected segments had no real peak at
    all). A true repetition instead produces a *local peak rising above the
    decaying envelope* (measured positive case: acf 0.588 at 1.20 s with its
    2.40 s harmonic alongside). So: only interior local maxima with at least
    [min_prominence] of rise over their neighbouring valleys count; a window
    whose ACF has no such peak is *moving but not repeating* and is rejected.
    Synthetic sinusoids cannot catch this defect — their ACF has a genuine
    peak AND a non-decaying envelope — which is how it survived self-tests.
    """
    n = len(seg)
    if n < hi + 2:
        return 0.0, 0
    dim = len(seg[0])
    means = [sum(f[d] for f in seg) / n for d in range(dim)]
    c = [[f[d] - means[d] for d in range(dim)] for f in seg]

    energy = sum(sum(v * v for v in f) for f in c)
    if energy < 1e-9:
        return 0.0, 0

    lags = list(range(lo, hi + 1))
    r: list[float] = []
    for lag in lags:
        num = 0.0
        for t in range(n - lag):
            num += sum(c[t][d] * c[t + lag][d] for d in range(dim))
        # Normalise by the energy of the overlapping span.
        e1 = sum(sum(v * v for v in c[t]) for t in range(n - lag))
        e2 = sum(sum(v * v for v in c[t + lag]) for t in range(n - lag))
        denom = math.sqrt(e1 * e2)
        r.append(num / denom if denom >= 1e-12 else 0.0)

    best, best_lag = 0.0, 0
    for k in range(1, len(r) - 1):
        if not (r[k] > r[k - 1] and r[k] >= r[k + 1]):
            continue  # not an interior local maximum
        # Walk down to the valley on each side; prominence is the rise above
        # the *higher* of the two valleys — a micro-bump on a decaying slope
        # has a shallow uphill side and fails this.
        j = k
        while j > 0 and r[j - 1] < r[j]:
            j -= 1
        left_valley = r[j]
        j = k
        while j < len(r) - 1 and r[j + 1] < r[j]:
            j += 1
        right_valley = r[j]
        prominence = r[k] - max(left_valley, right_valley)
        if prominence < min_prominence:
            continue
        if r[k] > best:
            best, best_lag = r[k], lags[k]
    return best, best_lag


def find_movement_windows(
    frames: list[list[list[float]]],
    *,
    fps: float,
    window_s: float = 6.0,
    stride_s: float = 1.0,
    min_period_s: float = 0.4,
    max_period_s: float = 4.0,
    min_periodicity: float = 0.5,
    min_energy: float = 0.010,
    max_windows: int = 5,
) -> list[MovementWindow]:
    """Windows that are both repeating and moving."""
    series = normalized_series(frames)
    usable = [i for i, r in enumerate(series) if r is not None]
    if len(usable) < 10 or fps <= 0:
        return []

    win = max(4, int(window_s * fps))
    stride = max(1, int(stride_s * fps))
    lo = max(1, int(min_period_s * fps))

    # A lag may not exceed a third of the window. At larger lags the two
    # compared spans barely overlap, so the normalized correlation is computed
    # from very little data and inflates — the first run on real takes reported
    # "periods" of 4-8 s for a step that repeats about once a second, which was
    # this artefact rather than a finding. Requiring three repetitions inside
    # the window also matches what a demonstration actually looks like.
    hi = min(int(max_period_s * fps), win // 3)
    if hi <= lo:
        return []

    cands: list[MovementWindow] = []
    for s in range(0, len(series) - win + 1, stride):
        seg = [r for r in series[s:s + win] if r is not None]
        if len(seg) < win * 0.8:
            continue
        energy = _motion_energy(seg)
        if energy < min_energy:
            continue                      # standing still — reject before the
                                          # autocorrelation can flatter it
        per, lag = _periodicity(seg, lo, min(hi, len(seg) - 2))
        if per < min_periodicity:
            continue
        cands.append(MovementWindow(s, s + win, win / fps, round(per, 3),
                                    round(energy, 4), round(lag / fps, 2)))

    merged: list[MovementWindow] = []
    for w in cands:
        if merged and w.start_frame <= merged[-1].end_frame:
            p = merged[-1]
            merged[-1] = MovementWindow(
                p.start_frame, max(p.end_frame, w.end_frame),
                (max(p.end_frame, w.end_frame) - p.start_frame) / fps,
                max(p.periodicity, w.periodicity),
                max(p.motion_energy, w.motion_energy),
                p.period_s if p.periodicity >= w.periodicity else w.period_s)
        else:
            merged.append(w)

    merged.sort(key=lambda w: (-w.periodicity, -w.seconds))
    return merged[:max_windows]


def load_frames(path: str) -> tuple[list[list[list[float]]], float]:
    d = json.load(open(path, encoding="utf-8"))
    fps = d.get("recordingMeta", {}).get("fps", 30) or 30
    out = []
    for f in d.get("frames", []):
        if f.get("detected") is False:
            continue
        lm = f.get("lm")
        if lm:
            out.append(lm)
    return out, float(fps)


# --------------------------------------------------------------------------

def _synth(n: int, *, period: int, amp: float, seed: int = 1):
    """Fake landmark frames: a limb swinging with a given period."""
    rng = __import__("random").Random(seed)
    frames = []
    for t in range(n):
        ph = 2 * math.pi * t / period if period else 0
        lm = [[0.5, 0.5, 0.0, 1.0] for _ in range(33)]
        lm[L_HIP] = [0.45, 0.60, 0, 1]
        lm[R_HIP] = [0.55, 0.60, 0, 1]
        lm[L_SHOULDER] = [0.42, 0.38, 0, 1]
        lm[R_SHOULDER] = [0.58, 0.38, 0, 1]
        for i in BODY:
            if i in (L_HIP, R_HIP, L_SHOULDER, R_SHOULDER):
                continue
            j = rng.gauss(0, 0.002)
            lm[i] = [0.5 + amp * math.sin(ph) + j, 0.5 + amp * math.cos(ph) + j,
                     0, 1]
        frames.append(lm)
    return frames


def self_test() -> int:
    print("movement isolator — measured behaviour\n")
    print(f"{'scenario':<40}{'windows':>8}{'per':>7}{'energy':>9}")
    fails = 0

    def run(label, frames, expect_found):
        nonlocal fails
        ws = find_movement_windows(frames, fps=30, window_s=4.0)
        top = ws[0] if ws else None
        print(f"{label:<40}{len(ws):>8}"
              f"{(top.periodicity if top else 0):>7.2f}"
              f"{(top.motion_energy if top else 0):>9.4f}")
        if bool(ws) != expect_found:
            print(f"    ! expected {'a window' if expect_found else 'none'}")
            fails += 1

    run("repeating step (1.0s period)", _synth(300, period=30, amp=0.10), True)
    run("repeating step (0.6s period)", _synth(300, period=18, amp=0.08), True)
    # The trap: a held pose is perfectly self-similar at every lag.
    run("standing still (the trap)", _synth(300, period=0, amp=0.0), False)
    run("tiny idle sway", _synth(300, period=30, amp=0.004), False)
    run("moving but not repeating", _synth(300, period=400, amp=0.10), False)

    # M-C-25 class in its purest form: continuous, energetic, NEVER repeating.
    # Its ACF decays monotonically — under the old global-max rule this scored
    # "periodic" at the search floor on every real tutorial's talking segments.
    rng = __import__("random").Random(7)
    walk = []
    wx, wy = 0.5, 0.5
    for _t in range(300):
        wx += rng.gauss(0, 0.004)
        wy += rng.gauss(0, 0.004)
        lm = [[0.5, 0.5, 0.0, 1.0] for _ in range(33)]
        lm[L_HIP] = [0.45, 0.60, 0, 1]
        lm[R_HIP] = [0.55, 0.60, 0, 1]
        lm[L_SHOULDER] = [0.42, 0.38, 0, 1]
        lm[R_SHOULDER] = [0.58, 0.38, 0, 1]
        for i in BODY:
            if i in (L_HIP, R_HIP, L_SHOULDER, R_SHOULDER):
                continue
            lm[i] = [wx, wy, 0, 1]
        walk.append(lm)
    run("random walk (M-C-25 class)", walk, False)

    print()
    if fails:
        print(f"SELF-TEST FAILED ({fails})")
        return 1
    print("SELF-TEST OK")
    print("\nThe 'standing still' row is the one that matters: periodicity "
          "alone would rank it top, and requiring motion is what rejects it.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--fixture")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.fixture:
        frames, fps = load_frames(os.path.expanduser(args.fixture))
        for w in find_movement_windows(frames, fps=fps):
            print(w)
        return 0
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
