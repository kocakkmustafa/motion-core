"""motion-core — fixture JSON şema sözleşmesi (10-ARAC-KATALOGU §6).

Aile-geneli: 5 app aynı şemayı kullanır, replay harness tektir.
Bu dosya TEK doğruluk kaynağıdır; şema değişirse schemaVersion artar ve
motion-core DEFTER'ine M-kaydı düşer.
"""

SCHEMA_VERSION = 1

# BlazePose GHUM 33 landmark — MediaPipe Pose Landmarker sırası.
LANDMARK_NAMES = [
    "nose",
    "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer",
    "left_ear", "right_ear",
    "mouth_left", "mouth_right",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_pinky", "right_pinky",
    "left_index", "right_index",
    "left_thumb", "right_thumb",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
]

IDX = {name: i for i, name in enumerate(LANDMARK_NAMES)}

# D2 protokolü §2: visibility ayrıştırması için vücut bölgeleri.
# "fast" = analiz edilen uzuv (yumruk atan kol) — çağıran taraf yanı seçer.
REGIONS = {
    "trunk": ["left_shoulder", "right_shoulder", "left_hip", "right_hip"],
    "base": ["left_ankle", "right_ankle", "left_heel", "right_heel",
             "left_foot_index", "right_foot_index"],
    "head": ["nose", "left_ear", "right_ear"],
}


def arm_region(side: str) -> list[str]:
    """Bir tarafın kol landmark'ları (omuz hariç — omuz trunk'a ait)."""
    assert side in ("left", "right")
    return [f"{side}_elbow", f"{side}_wrist", f"{side}_index"]


def empty_fixture(app: str, technique: str, recording_meta: dict,
                  model_version: str) -> dict:
    """Katalog §6 şemasının boş iskeleti."""
    return {
        "schemaVersion": SCHEMA_VERSION,
        "app": app,
        "technique": technique,
        "recordingMeta": recording_meta,
        "modelVersion": model_version,
        "frames": [],
        "labels": [],
    }


REQUIRED_RECORDING_META = ["device", "fps", "lighting", "bodyProfile", "cameraSetup"]


def validate(fixture: dict) -> list[str]:
    """Şema ihlallerini liste olarak döner (boş liste = geçerli)."""
    errs: list[str] = []
    for key in ("schemaVersion", "app", "technique", "recordingMeta",
                "modelVersion", "frames", "labels"):
        if key not in fixture:
            errs.append(f"eksik alan: {key}")
    if errs:
        return errs

    if fixture["schemaVersion"] != SCHEMA_VERSION:
        errs.append(
            f"schemaVersion {fixture['schemaVersion']} != {SCHEMA_VERSION}")

    for key in REQUIRED_RECORDING_META:
        if key not in fixture["recordingMeta"]:
            errs.append(f"recordingMeta eksik: {key}")

    for i, frame in enumerate(fixture["frames"]):
        if "t" not in frame or "landmarks" not in frame:
            errs.append(f"frame[{i}]: t/landmarks eksik")
            break
        lms = frame["landmarks"]
        if lms is not None and len(lms) != 33:
            errs.append(f"frame[{i}]: landmark sayısı {len(lms)} != 33")
            break

    for i, label in enumerate(fixture["labels"]):
        if "tStart" not in label or "tEnd" not in label:
            errs.append(f"labels[{i}]: tStart/tEnd eksik")
            break
        if "phase" not in label and "errorCode" not in label:
            errs.append(f"labels[{i}]: phase veya errorCode zorunlu")
            break

    return errs
