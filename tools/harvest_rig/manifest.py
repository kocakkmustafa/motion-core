"""Hasat manifesti — provenance ZORUNLU (M-F-13).

Her indirilen video için tek JSON manifest tutulur. Kaynak URL'i, kanal,
lisans, indirme tarihi ve araç sürümleri olmayan hiçbir klip boru hattında
ilerleyemez: referansa dönüşen her landmark'ın nereden geldiği, hangi araçla
çıkarıldığı sonradan sorgulanabilir olmalı (fixture v2 `provenance` blokuna
birebir akar).
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MANIFEST_VERSION = 1


def _tool_version(cmd: list[str]) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return out.stdout.strip().splitlines()[0] if out.stdout else "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable"


def tool_versions() -> dict[str, str]:
    """Boru hattındaki araçların sürüm damgaları."""
    versions: dict[str, str] = {
        "ytDlp": _tool_version(["yt-dlp", "--version"]),
        "ffmpeg": _tool_version(["ffmpeg", "-version"]),
    }
    try:
        import cv2  # noqa: PLC0415 - sürüm damgası için yerel import

        versions["openCv"] = cv2.__version__
    except ImportError:
        versions["openCv"] = "unavailable"
    try:
        import mediapipe  # noqa: PLC0415

        versions["mediapipe"] = mediapipe.__version__
    except ImportError:
        versions["mediapipe"] = "unavailable"
    return versions


@dataclass
class StageRecord:
    """Bir boru hattı aşamasının sonucu."""

    stage: str  # pull | triage | extract | dedup | transcribe
    status: str  # ok | rejected | skipped | error
    at: str
    detail: dict[str, Any] = field(default_factory=dict)


@dataclass
class HarvestManifest:
    """Tek videonun hasat kaydı."""

    manifest_version: int
    app: str
    video_id: str
    source_url: str
    channel: str | None
    uploader: str | None
    license: str | None  # info-json 'license' — yoksa "standard-youtube"
    upload_date: str | None  # YYYYMMDD (info-json)
    retrieved_at: str
    tool_versions: dict[str, str]
    local_path: str | None = None
    dedup_signature: str | None = None
    #: M-F-43: gösterim modu sınıflandırması kaynağın kendi ANLATISINDAN
    #: yapılır (başlık/açıklama/transkript), landmark'tan DEĞİL — klinisyen
    #: kolu kaldırdığında iz aktif hareketle birebir aynıdır.
    title: str | None = None
    description: str | None = None
    rom_mode: str | None = None
    reference_eligible: bool | None = None
    #: M-F-51 eki: dışlamanın NEDENİ. Aykırı raporlanırken sebebi de taşınır;
    #: "dışlandı" tek başına kaynak-kötü ile tanım-dar'ı ayırt ettirmiyor.
    context_tags: list[str] = field(default_factory=list)
    context_source: str | None = None
    #: G-057: hangi HAREKET için hasat edildiği. Kaydedilmezse çok-hareketli
    #: bir kütüphanede her fixture her hareketin havuzuna girebilir ve
    #: nitelenme oranlarının paydasını sessizce kirletir (32 squat videosu
    #: push_up'a "0 tekrar veren eğitmen" olarak sayılırdı).
    movement: str | None = None
    stages: list[StageRecord] = field(default_factory=list)

    @classmethod
    def start(cls, *, app: str, video_id: str, source_url: str) -> "HarvestManifest":
        return cls(
            manifest_version=MANIFEST_VERSION,
            app=app,
            video_id=video_id,
            source_url=source_url,
            channel=None,
            uploader=None,
            license=None,
            upload_date=None,
            retrieved_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            tool_versions=tool_versions(),
        )

    def absorb_info_json(self, info: dict[str, Any]) -> None:
        """yt-dlp --write-info-json çıktısından provenance alanları."""
        self.channel = info.get("channel") or info.get("channel_id")
        self.uploader = info.get("uploader")
        self.license = info.get("license") or "standard-youtube"
        self.upload_date = info.get("upload_date")
        self.title = info.get("title")
        self.description = info.get("description")

    def record(self, stage: str, status: str, **detail: Any) -> None:
        self.stages.append(
            StageRecord(
                stage=stage,
                status=status,
                at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                detail=detail,
            )
        )

    @property
    def rejected(self) -> bool:
        return any(s.status == "rejected" for s in self.stages)

    def provenance_block(self) -> dict[str, Any]:
        """Fixture v2 `provenance` blokuna gömülecek özet."""
        return {
            "sourceUrl": self.source_url,
            "channel": self.channel,
            "license": self.license,
            "uploadDate": self.upload_date,
            "retrievedAt": self.retrieved_at,
            "toolVersions": self.tool_versions,
            # M-F-43: fixture'ın KENDİSİ referansa uygun olup olmadığını
            # taşımalı. Sınıflandırma yalnız manifestte kalırsa aşağı akan
            # ReferenceBuilder onu göremez ve kural sessizce uygulanmaz.
            "romMode": self.rom_mode,
            "referenceEligible": self.reference_eligible,
            "contextTags": self.context_tags,
            "contextSource": self.context_source,
            "movement": self.movement,
        }

    def save(self, path: str | Path) -> None:
        Path(path).write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @classmethod
    def load(cls, path: str | Path) -> "HarvestManifest":
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        stages = [StageRecord(**s) for s in data.pop("stages", [])]
        m = cls(**{k: v for k, v in data.items() if k != "stages"})
        m.stages = stages
        return m
