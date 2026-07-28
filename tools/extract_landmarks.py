#!/usr/bin/env python3
"""motion-core — video → MediaPipe Pose Landmarker → fixture JSON.

Aile-geneli çıkarım aracı (JabLab D2, Gravita D1, Lissom değerlendirme aynı hattı kullanır).
Üretim hattıyla AYNI boru: video çek → landmark çıkar → etiketle → JSON fixture
(10-ARAC-KATALOGU §6, "birincil = kendi kayıtlarımız" stratejisi).

Kullanım:
    python extract_landmarks.py VIDEO.mp4 -o out.json --app jablab \
        --technique jab --model models/pose_landmarker_full.task

Notlar:
- VIDEO running mode kullanılır (canlı LIVE_STREAM değil) — deterministik, tekrarlanabilir.
- Model dosyası PİNLENİR; yolu+sha256'sı fixture'ın modelVersion alanına yazılır
  (10-ARAC-KATALOGU §1: MediaPipe "Solutions Preview", sürüm sabitlenmeli).
- Landmark bulunamayan kareler `landmarks: null` ile KORUNUR — kare kaybı bilgisi
  D2 analizinin girdisidir, sessizce atılmaz.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fixture_schema import empty_fixture, validate  # noqa: E402


def sha256_short(path: str, n: int = 12) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:n]


def build_landmarker(model_path: str, num_poses: int = 1):
    base = mp_python.BaseOptions(model_asset_path=model_path)
    opts = vision.PoseLandmarkerOptions(
        base_options=base,
        running_mode=vision.RunningMode.VIDEO,
        num_poses=num_poses,
        # Eşikler bilinçli DÜŞÜK: filtrelemeyi biz güven kapımızda yaparız,
        # modelin sessizce kare düşürmesini istemeyiz (D2 ölçümünün konusu bu).
        min_pose_detection_confidence=0.3,
        min_pose_presence_confidence=0.3,
        min_tracking_confidence=0.3,
        output_segmentation_masks=False,
    )
    return vision.PoseLandmarker.create_from_options(opts)


def extract(video_path: str, model_path: str, app: str, technique: str,
            recording_meta_extra: dict | None = None,
            crop: tuple[float, float, float, float] | None = None) -> dict:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise SystemExit(f"video açılamadı: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if fps <= 0:
        raise SystemExit("fps okunamadı — ffprobe ile doğrula")

    meta = {
        "device": "unknown",
        "fps": round(fps, 4),
        "lighting": "unknown",
        "bodyProfile": "unknown",
        "cameraSetup": "unknown",
        "sourceVideo": os.path.basename(video_path),
        "resolution": f"{width}x{height}",
        "frameCount": n_frames,
        "crop": list(crop) if crop else None,
    }
    meta.update(recording_meta_extra or {})

    model_version = f"{os.path.basename(model_path)}@sha256:{sha256_short(model_path)}"
    fixture = empty_fixture(app, technique, meta, model_version)

    landmarker = build_landmarker(model_path)
    idx = 0
    t_infer_total = 0.0
    missing = 0
    try:
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            if crop:
                x0, y0, x1, y1 = crop
                h, w = frame_bgr.shape[:2]
                frame_bgr = frame_bgr[int(y0 * h):int(y1 * h),
                                      int(x0 * w):int(x1 * w)]
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
            ts_ms = int(round(idx * 1000.0 / fps))

            t0 = time.perf_counter()
            result = landmarker.detect_for_video(mp_image, ts_ms)
            t_infer_total += time.perf_counter() - t0

            if result.pose_landmarks:
                lms = [
                    {"x": round(lm.x, 6), "y": round(lm.y, 6),
                     "z": round(lm.z, 6), "vis": round(lm.visibility, 4)}
                    for lm in result.pose_landmarks[0]
                ]
            else:
                lms = None
                missing += 1

            fixture["frames"].append({"t": ts_ms, "landmarks": lms})
            idx += 1
    finally:
        cap.release()
        landmarker.close()

    fixture["recordingMeta"]["framesProcessed"] = idx
    fixture["recordingMeta"]["framesWithoutPose"] = missing
    # Cihaz-üstü fps DEĞİLDİR (Mac/CPU ölçümü) — yalnız hattın maliyet göstergesi.
    fixture["recordingMeta"]["hostInferenceMsPerFrame"] = (
        round(1000.0 * t_infer_total / idx, 2) if idx else None)

    errs = validate(fixture)
    if errs:
        raise SystemExit("şema ihlali: " + "; ".join(errs))
    return fixture


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("video")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--app", default="jablab")
    ap.add_argument("--technique", default="unknown")
    ap.add_argument("--lighting", default="unknown")
    ap.add_argument("--camera-setup", default="unknown")
    ap.add_argument("--body-profile", default="unknown")
    ap.add_argument("--device", default="unknown")
    ap.add_argument("--source-url", default=None)
    ap.add_argument("--license", default=None)
    ap.add_argument("--crop", default=None,
                    help="x0,y0,x1,y1 oransal kırpma (0-1)")
    args = ap.parse_args()

    crop = None
    if args.crop:
        crop = tuple(float(v) for v in args.crop.split(","))
        if len(crop) != 4:
            raise SystemExit("--crop dört değer ister: x0,y0,x1,y1")

    fixture = extract(
        args.video, args.model, args.app, args.technique,
        recording_meta_extra={
            "lighting": args.lighting,
            "cameraSetup": args.camera_setup,
            "bodyProfile": args.body_profile,
            "device": args.device,
            "sourceUrl": args.source_url,
            "license": args.license,
        },
        crop=crop,
    )
    with open(args.out, "w") as f:
        json.dump(fixture, f)
    m = fixture["recordingMeta"]
    print(f"✓ {args.out}  kare={m['framesProcessed']} "
          f"pozsuz={m['framesWithoutPose']} fps={m['fps']} "
          f"host_ms/kare={m['hostInferenceMsPerFrame']}")


if __name__ == "__main__":
    main()
