"""Faz config yorumlayıcısı — A7/A8 ölçümü için TASLAK köprü.

⚠️ GEÇİCİ. Kanonik faz makinesi Dart çekirdeğindedir (`PhaseStateMachine`).
Bu modül yalnız kapı ölçümünü açmak için var: faz config'inin ürettiği dizilim
ve geçersizlik davranışı sentetik dizilerle ölçülebilsin diye. Core'da
config→makine köprüsü çıktığında bu dosya SİLİNİR ve ölçüm oraya devreder
(koordinatör onayı: "taslak köprünle ölç, core sürümü çıkınca devret").

Çift implementasyon riski bilinçli kabul edildi ve sınırlandı: burada yalnız
config YORUMU vardır, ölçüm matematiği yoktur — açılar `measures.py`'den gelir.

Koşullar veri olarak yorumlanır; hiçbir yerde kod dizesi çalıştırılmaz.

Şema önerisi (core köprüsü bunu temel alabilir):
    faz     := {id, enter, exit?, abort?, abortCode?, timeoutMs?,
                minDurationMs?, measureHere?, isTerminal?, requiredLandmarks?}
    koşul   := {kind: metric|delta|timeInPhase|confidence|all|any, ...}
"""

from __future__ import annotations

import json
import operator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import numpy as np

from . import geometry as geo
from . import measures as mz

OPS: dict[str, Callable[[float, float], bool]] = {
    ">": operator.gt, ">=": operator.ge, "<": operator.lt,
    "<=": operator.le, "==": operator.eq, "!=": operator.ne,
}

#: Bir denemenin nasıl bittiği — Dart `AttemptOutcome` ile aynı sözlük.
COMPLETED, TIMED_OUT, ABORTED, INCOMPLETE = (
    "completed", "timedOut", "aborted", "incomplete",
)


@dataclass
class Transition:
    from_phase: str | None
    to_phase: str
    t_ms: float


@dataclass
class AttemptResult:
    test_id: str
    transitions: list[Transition] = field(default_factory=list)
    outcome: str = INCOMPLETE
    abort_code: str | None = None
    measured_at_ms: float | None = None

    @property
    def phase_sequence(self) -> list[str]:
        return [t.to_phase for t in self.transitions]


class PhaseRunner:
    """Bir testin faz dizisini kare akışı üzerinde koşturur."""

    def __init__(self, test_def: dict[str, Any], mset: mz.MetricSet, *, side: str = "right"):
        self.test_id = test_def["testId"]
        self.side = side
        self.mset = mset
        self.phases = test_def["phases"]

    # --- koşul yorumu -----------------------------------------------------

    def _metric_value(self, name: str, frame: geo.Frame) -> float | None:
        name = name.replace("{side}", self.side)
        m = self.mset.metrics.get(name)
        if m is None:
            raise KeyError(f"{self.test_id}: config tanımsız metrik istiyor — {name}")
        res = mz.evaluate(m, frame)
        return res.value if np.isfinite(res.value) else None

    def _holds(self, cond: dict[str, Any], frame: geo.Frame,
               prev: geo.Frame | None, t_in_phase_ms: float) -> bool:
        """Koşul bu karede sağlanıyor mu — saf veri yorumu."""
        kind = cond["kind"]
        if kind == "all":
            return all(self._holds(c, frame, prev, t_in_phase_ms) for c in cond["of"])
        if kind == "any":
            return any(self._holds(c, frame, prev, t_in_phase_ms) for c in cond["of"])
        op = OPS[cond["op"]]
        if kind == "timeInPhase":
            return op(t_in_phase_ms, cond["valueMs"])
        if kind == "confidence":
            # Kare kalitesi: tüm landmark'ların taşıdığı en zayıf güven.
            return op(frame.confidence(tuple(range(33))), cond["value"])
        if kind == "metric":
            v = self._metric_value(cond["metric"], frame)
            return v is not None and op(v, cond["value"])
        if kind == "delta":
            if prev is None:
                return False
            now = self._metric_value(cond["metric"], frame)
            before = self._metric_value(cond["metric"], prev)
            if now is None or before is None:
                return False
            dt_s = (frame.t_ms - prev.t_ms) / 1000.0
            if dt_s <= 0:
                return False
            # L-070: eşik SANİYE başına. Kare-başına eşik iki yönden kırılgandı:
            # küçük genlikli hareketlerde hiç tetiklenmiyordu (33°'lik yana
            # eğilme 0,73°/kare) ve cihaz fps'i değişince sessizce yarıya
            # düşüyordu.
            if "valuePerSecond" not in cond:
                raise ValueError(
                    f"{self.test_id}: delta koşulu `valuePerSecond` ister "
                    f"(kare-başına `value` kaldırıldı — L-070). Koşul: {cond}"
                )
            return op((now - before) / dt_s, cond["valuePerSecond"])
        raise ValueError(f"bilinmeyen koşul tipi: {kind}")

    # --- koşum ------------------------------------------------------------

    def run(self, frames: list[geo.Frame]) -> AttemptResult:
        res = AttemptResult(self.test_id)
        idx = 0                      # beklenen faz
        entered_at: float | None = None
        prev: geo.Frame | None = None

        for frame in frames:
            t = frame.t_ms
            if idx >= len(self.phases):
                break
            cur = self.phases[idx]
            t_in = 0.0 if entered_at is None else t - entered_at

            # Henüz girilmemiş faz: enter koşulu bekleniyor.
            if entered_at is None:
                if self._holds(cur["enter"], frame, prev, 0.0):
                    entered_at = t
                    res.transitions.append(
                        Transition(
                            res.transitions[-1].to_phase if res.transitions else None,
                            cur["id"], t,
                        )
                    )
                    if cur.get("measureHere"):
                        res.measured_at_ms = t
                    if cur.get("isTerminal"):
                        res.outcome = COMPLETED
                        return res
                prev = frame
                continue

            # Girilmiş faz: abort > timeout > ilerleme sırası.
            if cur.get("abort") and self._holds(cur["abort"], frame, prev, t_in):
                res.outcome = ABORTED
                res.abort_code = cur.get("abortCode")
                return res
            if cur.get("timeoutMs") and t_in > cur["timeoutMs"]:
                res.outcome = TIMED_OUT
                return res
            if t_in >= cur.get("minDurationMs", 0) and idx + 1 < len(self.phases):
                nxt = self.phases[idx + 1]
                if self._holds(nxt["enter"], frame, prev, t_in):
                    idx += 1
                    entered_at = t
                    res.transitions.append(Transition(cur["id"], nxt["id"], t))
                    if nxt.get("measureHere"):
                        res.measured_at_ms = t
                    if nxt.get("isTerminal"):
                        res.outcome = COMPLETED
                        return res
            prev = frame

        return res


def load_phase_set(path: str | Path) -> dict[str, dict[str, Any]]:
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    if int(doc.get("schemaVersion", 0)) != 1:
        raise ValueError(f"{path}: schemaVersion 1 bekleniyor")
    return {t["testId"]: t for t in doc["tests"]}
