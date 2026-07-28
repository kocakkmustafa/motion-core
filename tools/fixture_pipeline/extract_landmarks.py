#!/usr/bin/env python
"""Video -> fixture JSON çıkarma hattı — AİLENİN TEK ÇIKARIM ARACI.

Ham video HİÇBİR YERE kopyalanmaz; yalnız landmark dizisi ve çekim üstverisi
JSON'a yazılır.

İki mod (M-F-03 birleşimi — Lissom batch hattı + JabLab tekil hattı):

  1. BATCH — çekim-listesi sözleşmeli klasör (dosya adından meta):
       ./.venv/bin/python extract_landmarks.py \
           --input ~/lissom-fixtures/raw --output ~/lissom-fixtures/landmarks \
           --variant heavy --app lissom

  2. SINGLE — tekil video, serbest meta (D2 ölçümü, hasat klibi):
       ./.venv/bin/python extract_landmarks.py \
           --file bag_full.mp4 --out fixtures/bag_full.json --app jablab \
           --technique jab --variant full --min-confidence 0.3 \
           --source-url https://... --license standard-youtube

Notlar:
- VIDEO running mode (deterministik, tekrarlanabilir); LIVE_STREAM değil.
- Model dosyaları PİNLİDİR (models/MODELS.md, SHA-256 fixture'a gömülür).
- Tespit eşiği varsayılan 0.5; ölçüm kapıları (D2 gibi) modelin sessizce kare
  düşürmesini İSTEMEZ -> --min-confidence 0.3 verilir, filtreleme güven
  kapısında yapılır.
- Pozsuz kareler fixture'da korunur (detected:false) — kare kaybı bilgisi
  kapı analizinin girdisidir, sessizce atılmaz.
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


def _model_path(variant: str) -> Path:
    model_path = MODELS_DIR / VARIANTS[variant]
    if not model_path.exists():
        raise FileNotFoundError(f"Model yok: {model_path}\nİndirme: models/MODELS.md")
    return model_path


def _run_video(
    video: Path,
    model_path: Path,
    *,
    min_confidence: float,
    crop: tuple[float, float, float, float] | None,
) -> tuple[list[dict[str, object]], float, float, str]:
    """Videoyu koş; (frames, fps, host_ms_per_frame, resolution) döner."""
    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        raise RuntimeError(f"Video açılamadı: {video}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=min_confidence,
        min_pose_presence_confidence=min_confidence,
        min_tracking_confidence=min_confidence,
        output_segmentation_masks=False,
    )

    frames: list[dict[str, object]] = []
    t_infer = 0.0
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        i = 0
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            if crop:
                x0, y0, x1, y1 = crop
                h, w = bgr.shape[:2]
                bgr = bgr[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)]
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            # VIDEO modu KESİNLİKLE artan timestamp ister; kare indeksinden
            # deterministik üretiyoruz ki aynı video hep aynı fixture'ı versin.
            t_ms = i * 1000.0 / fps
            t0 = time.perf_counter()
            result = landmarker.detect_for_video(image, int(t_ms))
            t_infer += time.perf_counter() - t0
            lms = result.pose_landmarks[0] if result.pose_landmarks else None
            world = (
                result.pose_world_landmarks[0]
                if result.pose_world_landmarks
                else None
            )
            frames.append(fx.Fixture.frame_record(t_ms, lms, world))
            i += 1
    cap.release()
    host_ms = round(1000.0 * t_infer / len(frames), 2) if frames else 0.0
    return frames, round(float(fps), 3), host_ms, f"{width}x{height}"


def _finish(
    meta: fx.RecordingMeta,
    frames: list[dict[str, object]],
    *,
    app: str,
    variant: str,
    model_path: Path,
    fps: float,
    host_ms: float,
    resolution: str,
    provenance: dict[str, object] | None,
) -> fx.Fixture:
    meta.fps = fps
    meta.frame_count = len(frames)
    meta.resolution = resolution
    meta.frames_without_pose = sum(1 for f in frames if not f.get("detected"))
    meta.host_inference_ms_per_frame = host_ms
    fixture = fx.Fixture(
        schema_version=fx.SCHEMA_VERSION,
        app=app,
        meta=meta,
        model_version=f"pose_landmarker_{variant}/float16/1",
        model_sha256=_sha256(model_path),
        provenance=provenance,
    )
    fixture.frames = frames
    return fixture


def extract_batch_one(
    video: Path, out_dir: Path, *, variant: str, app: str, overwrite: bool,
    min_confidence: float,
) -> dict[str, object]:
    meta = fx.RecordingMeta.from_filename(video)  # şemaya uymayan ad = hata
    out_path = out_dir / f"{video.stem}.{variant}.json"
    if out_path.exists() and not overwrite:
        return {"file": video.name, "status": "skipped (var)", "out": out_path.name}

    model_path = _model_path(variant)
    t0 = time.perf_counter()
    frames, fps, host_ms, resolution = _run_video(
        video, model_path, min_confidence=min_confidence, crop=None
    )
    elapsed = time.perf_counter() - t0

    fixture = _finish(
        meta, frames, app=app, variant=variant, model_path=model_path,
        fps=fps, host_ms=host_ms, resolution=resolution, provenance=None,
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path.write_text(fixture.to_json(), encoding="utf-8")

    detected = sum(1 for f in frames if f.get("detected"))
    return {
        "file": video.name,
        "status": "ok",
        "frames": len(frames),
        "detected": detected,
        "rate": f"{detected / max(1, len(frames)):.1%}",
        "sec": f"{elapsed:.1f}",
        "out": out_path.name,
    }


def extract_single(args: argparse.Namespace) -> None:
    video = Path(args.file).expanduser()
    out_path = Path(args.out).expanduser()
    model_path = _model_path(args.variant)

    crop = None
    if args.crop:
        parts = tuple(float(v) for v in args.crop.split(","))
        if len(parts) != 4:
            raise SystemExit("--crop dört değer ister: x0,y0,x1,y1 (0-1 oransal)")
        crop = parts

    frames, fps, host_ms, resolution = _run_video(
        video, model_path, min_confidence=args.min_confidence, crop=crop
    )

    meta = fx.RecordingMeta.freeform(
        technique=args.technique,
        device=args.device,
        lighting=args.lighting,
        camera_setup=args.camera_setup,
        body_profile=args.body_profile,
        source_video=video.name,
    )
    provenance = None
    if args.source_url or args.license:
        provenance = {
            "sourceUrl": args.source_url,
            "license": args.license,
            "extractor": "extract_landmarks.py",
        }

    fixture = _finish(
        meta, frames, app=args.app, variant=args.variant, model_path=model_path,
        fps=fps, host_ms=host_ms, resolution=resolution, provenance=provenance,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(fixture.to_json(), encoding="utf-8")

    detected = sum(1 for f in frames if f.get("detected"))
    print(
        f"✓ {out_path}  kare={len(frames)} tespit={detected} "
        f"({detected / max(1, len(frames)):.1%}) fps={fps} host_ms/kare={host_ms}"
    )


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--variant", default="heavy", choices=sorted(VARIANTS))
    ap.add_argument("--app", default=None, help="hangi app'in fixture'ı (zorunlu)")
    ap.add_argument(
        "--min-confidence", type=float, default=0.5,
        help="MediaPipe tespit/izleme eşiği (ölçüm kapıları 0.3 kullanır)",
    )
    # BATCH modu
    ap.add_argument("--input", help="çekim-listesi sözleşmeli video klasörü")
    ap.add_argument("--output", help="fixture çıktı klasörü")
    ap.add_argument("--overwrite", action="store_true")
    # SINGLE modu
    ap.add_argument("--file", help="tekil video (serbest meta modu)")
    ap.add_argument("--out", help="tekil fixture çıktı yolu")
    ap.add_argument("--technique", default="unknown")
    ap.add_argument("--lighting", default="unknown")
    ap.add_argument("--camera-setup", default="unknown")
    ap.add_argument("--body-profile", default="unknown")
    ap.add_argument("--device", default="unknown")
    ap.add_argument("--source-url", default=None)
    ap.add_argument("--license", default=None)
    ap.add_argument("--crop", default=None, help="x0,y0,x1,y1 oransal kırpma (0-1)")
    args = ap.parse_args()

    if args.file:
        if not args.app:
            print("HATA: --file modunda --app zorunlu "
                  "(lissom/jablab/gravita/ostinato/choreia)", file=sys.stderr)
            return 2
        if not args.out:
            print("HATA: --file modunda --out zorunlu", file=sys.stderr)
            return 2
        extract_single(args)
        return 0

    if not args.app:
        # Çekim-listesi sözleşmesi şu an yalnız Lissom'da — eski komutlar
        # kırılmasın diye batch varsayılanı korunur.
        args.app = "lissom"

    if not (args.input and args.output):
        print("HATA: ya --file/--out ya da --input/--output verilmeli",
              file=sys.stderr)
        return 2

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
            r = extract_batch_one(
                v, out_dir, variant=args.variant, app=args.app,
                overwrite=args.overwrite, min_confidence=args.min_confidence,
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
