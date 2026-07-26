"""Fixture JSON şeması — aile-geneli sözleşme (10-ARAC-KATALOGU §6).

5 app aynı şemayı kullanır; replay harness core'da tektir. Ham video ASLA
buraya girmez: yalnız landmark dizisi + çekim üstverisi saklanır.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from . import geometry as geo

SCHEMA_VERSION = 1

#: Çekim listesindeki dosya adı sözleşmesi:
#: <testId>__<subject>__<side>__<plane>__<light>__<clothing>__<distance>__<take>
FILENAME_RE = re.compile(
    r"^(?P<test>[a-z0-9_]+)__"
    r"(?P<subject>[a-z0-9]+)__"
    r"(?P<side>left|right|bilateral)__"
    r"(?P<plane>sagittal|frontal|diagonal)__"
    r"(?P<light>bright|dim)__"
    r"(?P<clothing>tight|loose)__"
    r"(?P<distance>\d+)__"
    r"(?P<take>[a-z0-9\-]+)$"
)


@dataclass
class RecordingMeta:
    """Çekimin koşulları — kapı ölçümü bunlara göre gruplanır."""

    test: str
    subject: str
    side: str
    plane: str
    light: str
    clothing: str
    distance_cm: int
    take: str
    device: str = "unknown"
    fps: float = 0.0
    frame_count: int = 0
    #: `take` "invalid-*" ile başlıyorsa bu klip KASITLI bozuktur; motor onu
    #: reddetmelidir. Kapı kriteri B7 bunu kullanır.
    intentionally_invalid: bool = False
    invalid_reason: str | None = None

    @classmethod
    def from_filename(cls, path: str | Path) -> "RecordingMeta":
        stem = Path(path).stem
        m = FILENAME_RE.match(stem)
        if not m:
            raise ValueError(
                f"Dosya adı sözleşmeye uymuyor: {stem!r}\n"
                "Beklenen: <test>__<subject>__<side>__<plane>__<light>__"
                "<clothing>__<distance>__<take>\n"
                "Bkz. FIXTURE-CEKIM-LISTESI.md §0"
            )
        d = m.groupdict()
        take = d["take"]
        invalid = take.startswith("invalid-")
        return cls(
            test=d["test"],
            subject=d["subject"],
            side=d["side"],
            plane=d["plane"],
            light=d["light"],
            clothing=d["clothing"],
            distance_cm=int(d["distance"]),
            take=take,
            intentionally_invalid=invalid,
            invalid_reason=take[len("invalid-"):] if invalid else None,
        )


@dataclass
class Label:
    """Elle etiketlenmiş zaman aralığı (faz veya hata kodu)."""

    t_start_ms: float
    t_end_ms: float
    kind: str  # "phase" | "error" | "rep"
    value: str
    annotator: str = "unlabeled"
    confidence: float = 1.0


@dataclass
class Fixture:
    """Bir çekimin tam kaydı."""

    schema_version: int
    app: str
    meta: RecordingMeta
    model_version: str
    model_sha256: str
    frames: list[dict[str, Any]] = field(default_factory=list)
    labels: list[Label] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(
            {
                "schemaVersion": self.schema_version,
                "app": self.app,
                "recordingMeta": asdict(self.meta),
                "modelVersion": self.model_version,
                "modelSha256": self.model_sha256,
                "frames": self.frames,
                "labels": [asdict(l) for l in self.labels],
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )

    @staticmethod
    def frame_record(
        t_ms: float,
        landmarks: list[Any] | None,
        world: list[Any] | None,
    ) -> dict[str, Any]:
        """Tek karenin serileştirilebilir hali.

        Koordinatlar 5 ondalığa yuvarlanır: MediaPipe'ın kendi hassasiyeti
        bunun çok altında ve tam float dosyayı ~3x şişiriyor.
        """
        if not landmarks:
            return {"t": round(t_ms, 2), "detected": False}
        return {
            "t": round(t_ms, 2),
            "detected": True,
            "lm": [
                [round(p.x, 5), round(p.y, 5), round(p.z, 5),
                 round(p.visibility, 4), round(p.presence, 4)]
                for p in landmarks
            ],
            "world": [
                [round(p.x, 5), round(p.y, 5), round(p.z, 5)] for p in (world or [])
            ],
        }


def load(path: str | Path) -> tuple[RecordingMeta, list[geo.Frame], dict[str, Any]]:
    """Fixture JSON'u geri yükle — replay harness'ın girdisi.

    Dönen Frame'ler WORLD uzayındadır (ölçüm motorunun beklediği uzay).
    Tespit edilemeyen kareler atlanır ama sayısı raporda döner.
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    sv = int(data.get("schemaVersion", 0))
    if sv != SCHEMA_VERSION:
        raise ValueError(f"{path}: schemaVersion {sv}, bu okuyucu {SCHEMA_VERSION} bekliyor")

    meta = RecordingMeta(**data["recordingMeta"])
    frames: list[geo.Frame] = []
    missed = 0
    for rec in data["frames"]:
        if not rec.get("detected"):
            missed += 1
            continue
        lm_arr = np.array(rec["lm"], dtype=float)
        world = np.array(rec["world"], dtype=float)
        if world.shape != (33, 3):
            missed += 1
            continue
        frames.append(
            geo.Frame(
                xyz=world,
                visibility=lm_arr[:, 3],
                presence=lm_arr[:, 4],
                t_ms=float(rec["t"]),
            )
        )
    stats = {
        "total": len(data["frames"]),
        "detected": len(frames),
        "missed": missed,
        "detectionRate": len(frames) / max(1, len(data["frames"])),
    }
    return meta, frames, stats
