#!/usr/bin/env python
"""Video -> fixture JSON çıkarma hattı (G3).

Ham video HİÇBİR YERE kopyalanmaz; yalnız landmark dizisi ve çekim üstverisi
JSON'a yazılır. Kurucunun `~/lissom-fixtures/raw/` altındaki çekimlerini
`~/lissom-fixtures/landmarks/` altına dönüştürür.

Çalıştırma:
    ./.venv/bin/python extract_landmarks.py \
        --input ~/lissom-fixtures/raw \
        --output ~/lissom-fixtures/landmarks \
        --variant heavy
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import time
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

from mocore import fixture as fx

MODELS_DIR = Path(__file__).parent / "models"
VIDEO_EXT = {".mov", ".mp4", ".m4v", ".avi"}

#: Kapı protokolü §3.5: assessment modunda heavy, günlük seansta full.
#: Fixture çıkarımı assessment tarafındadır -> varsayılan heavy.
VARIANTS = {
    "lite": "pose_landmarker_lite.v1.task",
    "full": "pose_landmarker_full.v1.task",
    "heavy": "pose_landmarker_heavy.v1.task",
}


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract(
    video: Path, out_dir: Path, *, variant: str, app: str, overwrite: bool
) -> dict[str, object]:
    meta = fx.RecordingMeta.from_filename(video)  # şemaya uymayan ad = hata
    out_path = out_dir / f"{video.stem}.{variant}.json"
    if out_path.exists() and not overwrite:
        return {"file": video.name, "status": "skipped (var)", "out": out_path.name}

    model_path = MODELS_DIR / VARIANTS[variant]
    if not model_path.exists():
        raise FileNotFoundError(
            f"Model yok: {model_path}\nİndirme: models/MODELS.md"
        )

    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        raise RuntimeError(f"Video açılamadı: {video}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    meta.fps = round(float(fps), 3)

    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
        output_segmentation_masks=False,
    )

    frames: list[dict[str, object]] = []
    t0 = time.perf_counter()
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        i = 0
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            # VIDEO modu KESİNLİKLE artan timestamp ister; kare indeksinden
            # deterministik üretiyoruz (gerçek kare zamanı yerine) ki aynı
            # video her koşuda birebir aynı fixture'ı versin.
            t_ms = i * 1000.0 / fps
            result = landmarker.detect_for_video(image, int(t_ms))
            lms = result.pose_landmarks[0] if result.pose_landmarks else None
            world = (
                result.pose_world_landmarks[0]
                if result.pose_world_landmarks
                else None
            )
            frames.append(fx.Fixture.frame_record(t_ms, lms, world))
            i += 1
    cap.release()
    elapsed = time.perf_counter() - t0

    meta.frame_count = len(frames)
    detected = sum(1 for f in frames if f.get("detected"))
    fixture = fx.Fixture(
        schema_version=fx.SCHEMA_VERSION,
        app=app,
        meta=meta,
        model_version=f"pose_landmarker_{variant}/float16/1",
        model_sha256=_sha256(model_path),
    )
    fixture.frames = frames
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path.write_text(fixture.to_json(), encoding="utf-8")

    return {
        "file": video.name,
        "status": "ok",
        "frames": len(frames),
        "detected": detected,
        "rate": f"{detected / max(1, len(frames)):.1%}",
        "sec": f"{elapsed:.1f}",
        "out": out_path.name,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--variant", default="heavy", choices=sorted(VARIANTS))
    ap.add_argument("--app", default="lissom")
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()

    in_dir = Path(args.input).expanduser()
    out_dir = Path(args.output).expanduser()
    if not in_dir.is_dir():
        print(f"HATA: girdi klasörü yok: {in_dir}", file=sys.stderr)
        return 2

    videos = sorted(p for p in in_dir.iterdir() if p.suffix.lower() in VIDEO_EXT)
    if not videos:
        print(f"Klasörde video yok: {in_dir}")
        print(f"Beklenen uzantılar: {', '.join(sorted(VIDEO_EXT))}")
        return 0

    print(f"{len(videos)} video · model varyantı: {args.variant}\n")
    failures: list[tuple[str, str]] = []
    for v in videos:
        try:
            r = extract(
                v, out_dir, variant=args.variant, app=args.app,
                overwrite=args.overwrite,
            )
            if r["status"] == "ok":
                print(f"  ✅ {r['file']:<62} {r['detected']}/{r['frames']} kare "
                      f"({r['rate']}) · {r['sec']}s")
            else:
                print(f"  ⏭️  {r['file']:<62} {r['status']}")
        except Exception as exc:  # noqa: BLE001 - toplu işlemde tek klip patlamamalı
            failures.append((v.name, str(exc)))
            print(f"  ❌ {v.name:<62} {exc}")

    print(f"\n{len(videos) - len(failures)}/{len(videos)} klip işlendi -> {out_dir}")
    if failures:
        print(f"\n{len(failures)} başarısız:")
        for name, err in failures:
            print(f"  - {name}: {err.splitlines()[0]}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
