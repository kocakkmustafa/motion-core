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


def rig_version() -> dict[str, Any]:
    """Rig'in KENDİ sürüm damgası — bayat-kopya sınıfının panzehiri (M-F-135).

    Neden gerekli: Gravita'nın squat hasadı, M-F-45'in sınıf-düzeyi muafiyet
    mekanizmasını TAŞIMAYAN bayat bir rig kopyasıyla koşmuştu. Çıktı tamamen
    geçerli görünüyordu (provenance düzgün, `referenceEligible` dürüstçe
    yazılmış) — yalnız uygulanan KURAL bir sürüm gerisindeydi ve bunu hiçbir
    alan söylemiyordu. M-F-07 köken alanlarının araç-sürümü karşılığı: hangi
    ARAÇ ürettiğini de damgala, yoksa "hangi kural uygulandı" sorusu
    cevaplanamaz.

    Kopya tespiti SHA'ya güvenmez ve İKİ kademeli:
      1. Dosya o depoda gerçekten TAKİP EDİLİYOR mu (`ls-files`)? Edilmiyorsa
         kopya/vendored — damga sessizce SHA uydurmaz, gürültü yapar.
      2. Depo GERÇEKTEN motion-core mu? Rig başka bir git deposuna kopyalanıp
         orada commit edilirse 1. kademe GEÇER ve `rev-parse HEAD` o deponun
         SHA'sını döndürür: damga İNANDIRICI AMA YANLIŞ olur (ölçüldü). Bu
         yüzden deponun kimliği İÇERİKTEN doğrulanır — motion-core'un kendi
         `packages/motion_core/pubspec.yaml`ı o commit'te var mı. Uzak URL'e
         bakmak kırılgan olurdu (fork, SSH/HTTPS, remote'suz klon).
    """
    here = Path(__file__).resolve().parent

    def git(*args: str) -> str | None:
        try:
            out = subprocess.run(["git", "-C", str(here), *args],
                                 capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return out.stdout.strip() if out.returncode == 0 else None

    tracked = git("ls-files", "--error-unmatch", str(Path(__file__).resolve()))
    sha = git("rev-parse", "HEAD") if tracked is not None else None
    # Kimlik: motion-core'un kendi dosyası bu commit'te var mı?
    is_core = (git("cat-file", "-e", "HEAD:packages/motion_core/pubspec.yaml")
               is not None) if sha else False
    if not sha or not is_core:
        return {
            "sha": None,
            "vendored": True,
            "note": ("rig kaynağı motion-core deposunda TAKİP EDİLMİYOR "
                     "(takipsiz kopya ya da BAŞKA bir depoya kopyalanmış) — "
                     "hangi kuralları uyguladığı doğrulanamaz "
                     "(M-F-135 bayat-kopya sınıfı)"),
            "observedSha": sha,
        }
    return {
        "sha": sha,
        "dirty": bool(git("status", "--porcelain", "--", str(here))),
        "vendored": False,
    }


def tool_versions() -> dict[str, Any]:
    """Boru hattındaki araçların sürüm damgaları."""
    versions: dict[str, Any] = {
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
    # Rig'in KENDİSİ de bir araçtır: hangi sürümün hangi kuralı uyguladığı
    # ancak bu damgayla sorgulanabilir (M-F-135).
    versions["harvestRig"] = rig_version()
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
    tool_versions: dict[str, Any]
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
