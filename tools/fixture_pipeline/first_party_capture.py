#!/usr/bin/env python3
"""Offline first-party intake and evaluation bookkeeping; never trains/deploys.

Companion to extract_landmarks.py, not a second extractor. No network, copying,
deletion, thresholds or runtime promotion. Receipts constrain this workflow,
not direct filesystem access. Consent/labels are attestations, not legal or
pedagogical certification. No participant-independent claim from one person.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import subprocess
from pathlib import Path

SCOPE_FIELDS = ("app", "area", "course_sha256", "lesson_id", "movement_id")
TARGETS = Path(__file__).with_name("first_party_capture.targets.v1.json")
PARTITIONS = {"reference", "train", "validation", "test"}
SHA = re.compile(r"[0-9a-f]{64}\Z")
ID = re.compile(r"[a-z0-9][a-z0-9_-]{0,95}\Z")
MAX_BYTES = 512 * 1024 * 1024
AREAS = {
    "gravita": {"bodyweight", "dbkb", "barbell", "rings", "hands"},
    "lissom": {"hatha", "chair", "vinyasa", "yin", "ashtanga"},
    "jablab": {"boxing", "taichi", "kickboxing", "karate", "muaythai"},
    "ostinato": {"guitar", "piano", "vocal", "ukulele", "bass"},
    "choreia": {"hiphop", "salsa", "line", "latin", "shortform"},
}

class IntakeError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise IntakeError(message)

def exact(obj, fields, label):
    require(isinstance(obj, dict) and set(obj) == set(fields.split()),
            f"{label}: missing/unknown fields")

def finite(value, minimum, maximum, label):
    require(type(value) in (int, float) and math.isfinite(value)
            and minimum <= value <= maximum, f"{label}: invalid number")

def identifier(value, label):
    require(isinstance(value, str) and ID.fullmatch(value), f"{label}: use pseudonymous id")

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False, allow_nan=False).encode()).hexdigest()

def file_sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()

def local_path(root, name):
    require(isinstance(name, str) and name and not Path(name).is_absolute()
            and ".." not in Path(name).parts and "\\" not in name and ":" not in name,
            "relative local path required")
    root = root.resolve(strict=True)
    p = root
    for part in Path(name).parts:
        p = p / part
        require(not p.is_symlink(), "symlink intake is not allowed")
    require(p.is_file() and p.resolve().is_relative_to(root), "missing local file")
    return p

def read(path):
    require(path.stat().st_size <= 8 * 1024 * 1024, "oversized JSON")
    return json.loads(path.read_text(), parse_constant=lambda x: (_ for _ in ()).throw(IntakeError("non-finite JSON")))

def validate(doc):
    exact(doc, "schema_version dataset_id clips", "manifest")
    require(doc["schema_version"] == 1, "schema_version must be 1")
    identifier(doc["dataset_id"], "dataset_id")
    require(isinstance(doc["clips"], list) and len(doc["clips"]) <= 10000, "clips list required")
    ids = set()
    groups = {key: {} for key in ("participant_id", "session_id", "source_recording_id", "sha256")}
    for c in doc["clips"]:
        exact(c, "clip_id app area movement_id lesson_id course_sha256 participant_id session_id source_recording_id path sha256 bytes partition purpose view mirrored rotation_deg duration_s width height fps device audio permissions annotations", "clip")
        for field in ("clip_id", "participant_id", "session_id", "source_recording_id", "movement_id"):
            identifier(c[field], field)
        require(c["clip_id"] not in ids, "duplicate clip id")
        ids.add(c["clip_id"])
        require(c["app"] in AREAS and c["area"] in AREAS[c["app"]], "unknown product/area")
        require(isinstance(c["lesson_id"], str) and 0 < len(c["lesson_id"]) <= 128,
                "exact course lesson id required; no invented runtime binding")
        require(SHA.fullmatch(c["sha256"]) and SHA.fullmatch(c["course_sha256"]), "invalid SHA256")
        require(type(c["bytes"]) is int and 0 < c["bytes"] <= MAX_BYTES, "file byte limit")
        require(c["partition"] in PARTITIONS, "unknown partition")
        require(c["purpose"] in {"demonstration", "calibration", "evaluation"}, "unknown purpose")
        require((c["partition"] == "test") == (c["purpose"] == "evaluation"), "test purpose must be evaluation")
        require(c["view"] in {"frontal", "sagittal_left", "sagittal_right", "diagonal", "hands_closeup"}, "unknown view")
        require(c["mirrored"] is False and type(c["rotation_deg"]) is int
                and c["rotation_deg"] in (0, 90, 180, 270), "original unmirrored input required")
        finite(c["duration_s"], 5, 90, "duration_s")
        for field in ("width", "height"):
            require(type(c[field]) is int and 720 <= c[field] <= 7680, "720p or higher required")
        finite(c["fps"], 29, 120, "fps")
        exact(c["device"], "model os camera timestamp_domain", "device")
        for field in ("model", "os"):
            require(isinstance(c["device"][field], str) and 0 < len(c["device"][field]) <= 128, "device model/OS required; no serial")
        require(c["device"]["camera"] in {"front", "rear", "external"}
                and c["device"]["timestamp_domain"] == "media_pts", "declare source camera/media PTS")
        exact(c["audio"], "condition sample_rate_hz", "audio")
        require(c["audio"]["condition"] in {"none", "original_instrument", "original_voice", "owned_click", "licensed_music"}, "audio condition")
        finite(c["audio"]["sample_rate_hz"], 0, 192000, "sample_rate_hz")
        if c["audio"]["condition"] != "none":
            require(c["audio"]["sample_rate_hz"] >= 44100, "audio needs >=44100Hz")
        if c["app"] == "ostinato":
            require(c["audio"]["condition"] in {"original_instrument", "original_voice", "none"}, "no backing track for audio calibration")
        exact(c["permissions"], "evidence_path evidence_sha256 training evaluation demo_distribution no_bystanders private_details_checked music_rights", "permissions")
        p = c["permissions"]
        require(SHA.fullmatch(p["evidence_sha256"]), "consent evidence hash required")
        for field in ("training", "evaluation", "demo_distribution", "no_bystanders", "private_details_checked", "music_rights"):
            require(type(p[field]) is bool, "permission must be explicit boolean")
        require(p["no_bystanders"] and p["private_details_checked"], "privacy review missing")
        needed = { {"demonstration": "demo_distribution", "calibration": "training",
                    "evaluation": "evaluation"}[c["purpose"]] }
        # A descriptive purpose never authorizes the operational split role.
        if c["partition"] in {"train", "validation"}:
            needed.add("training")
        if c["partition"] in {"validation", "test"}:
            needed.add("evaluation")
        for permission in sorted(needed):
            require(p[permission], f"permission missing: {permission}")
        if c["audio"]["condition"] == "licensed_music":
            require(p["music_rights"], "music permission missing")
        require(isinstance(c["annotations"], list) and c["annotations"], "human annotation required")
        previous = -1.0
        for a in c["annotations"]:
            exact(a, "start_s end_s event observation label_origin annotator_id", "annotation")
            finite(a["start_s"], 0, c["duration_s"], "start_s")
            finite(a["end_s"], 0, c["duration_s"], "end_s")
            require(a["start_s"] >= previous and a["start_s"] < a["end_s"], "unordered/overlapping events")
            previous = a["end_s"]
            identifier(a["event"], "event")
            identifier(a["annotator_id"], "annotator_id")
            require(a["observation"] in {"observed", "uncertain", "unobservable", "negative_control"}, "annotation observation")
            require(a["label_origin"] == "human", "extractor predictions cannot be ground truth")
        # Across ALL products: frames, alternate views, edits and derivatives
        # of a person/recording cannot quietly become another split.
        for field, seen in groups.items():
            value = c[field]
            require(value not in seen or seen[value] == c["partition"], f"split leakage: {field}")
            seen[value] = c["partition"]
    scopes = {}
    for c in doc["clips"]:
        key = tuple(c[field] for field in SCOPE_FIELDS)
        population = scopes.setdefault(key, set())
        if c["partition"] in {"train", "reference"} and c["permissions"]["training"]:
            population.add("development")
        elif c["partition"] in {"validation", "test"}:
            population.add(c["partition"])
    readiness = [{"scope": dict(zip(SCOPE_FIELDS, key)),
                  "independent_evaluation_ready": {"development", "validation", "test"}.issubset(population)}
                 for key, population in sorted(scopes.items())]
    return {"status": "VALID_COLLECTION" if ids else "DRAFT_NO_DATA", "clips": len(ids),
            "manifest_sha256": digest(doc), "trained": False, "physically_validated": False,
            "media_hashes_verified": False, "visual_quality_or_expert_review_verified": False,
            "scope_readiness": readiness,
            # Conservative collection summary; freeze checks its exact scope.
            "independent_evaluation_ready": bool(readiness) and
            all(row["independent_evaluation_ready"] for row in readiness)}


def candidate_scope(value):
    exact(value, " ".join(SCOPE_FIELDS), "candidate scope")
    require(all(isinstance(value[key], str) for key in SCOPE_FIELDS), "scope fields must be strings")
    require(value["app"] in AREAS and value["area"] in AREAS[value["app"]], "unknown scope product/area")
    require(SHA.fullmatch(value["course_sha256"]), "invalid scope course SHA256")
    require(0 < len(value["lesson_id"]) <= 128, "scope lesson id required")
    identifier(value["movement_id"], "scope movement_id")
    return {key: value[key] for key in SCOPE_FIELDS}

def verify_media(doc, root, probe=None):
    status = validate(doc)
    for c in doc["clips"]:
        p = local_path(root, c["path"])
        require(p.suffix.lower() in {".mp4", ".mov"}, "original MP4/MOV required")
        require(p.stat().st_size == c["bytes"] and file_sha(p) == c["sha256"], "media bytes/hash mismatch")
        permission = local_path(root, c["permissions"]["evidence_path"])
        require(file_sha(permission) == c["permissions"]["evidence_sha256"], "permission evidence mismatch")
        if probe:
            data = probe(p)
            require(data["width"] == c["width"] and data["height"] == c["height"], "probe dimensions mismatch")
            require(abs(data["duration_s"]-c["duration_s"]) <= max(.1, 1/c["fps"]), "probe duration mismatch")
            require(abs(data["fps"]-c["fps"]) <= 1, "probe fps mismatch")
            require(data["rotation_deg"] == c["rotation_deg"], "probe rotation mismatch")
            if c["purpose"] != "demonstration":
                require(data["constant_frame_timing"], "VFR/non-monotonic timing: current index/fps extractor needs a PTS-preserving proposal before calibration")
            if c["audio"]["condition"] != "none":
                require(data["sample_rate_hz"] == c["audio"]["sample_rate_hz"], "probe audio mismatch")
            else:
                require(data["sample_rate_hz"] == 0, "undeclared audio: review privacy/music rights")
    return dict(status, media_hashes_verified=True, technical_probe_verified=probe is not None,
                visual_quality_or_expert_review_verified=False)

def verify_bindings(doc, catalog):
    """Bind only an actual course/version/lesson, never infer physical truth."""
    for c in doc["clips"]:
        rows = [r for r in catalog["areas"] if r["app"] == c["app"] and r["area"] == c["area"]]
        matches = [course for row in rows for course in row["courses"]
                   if course["sha256"] == c["course_sha256"]
                   and c["lesson_id"] in course["lesson_ids"]]
        require(len(matches) == 1, "course/lesson/version binding missing or ambiguous; define/review target first")

def ffprobe(path):
    cmd = ["ffprobe", "-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries",
           "format=duration:stream=codec_type,width,height,avg_frame_rate,sample_rate:stream_side_data=rotation", "-of", "json", str(path)]
    run = subprocess.run(cmd, capture_output=True, text=True, timeout=15, check=True)
    d = json.loads(run.stdout)
    videos = [s for s in d["streams"] if s["codec_type"] == "video"]
    require(len(videos) == 1, "one video stream required")
    v = videos[0]
    n, denominator = map(float, v["avg_frame_rate"].split("/"))
    require(denominator > 0, "invalid video timebase")
    audio = [s for s in d["streams"] if s["codec_type"] == "audio"]
    rotation = next((int(s["rotation"]) % 360 for s in v.get("side_data_list", []) if "rotation" in s), 0)
    clock = subprocess.run(["ffprobe", "-v", "error", "-protocol_whitelist", "file,pipe",
          "-select_streams", "v:0", "-show_entries", "frame=best_effort_timestamp_time",
          "-of", "csv=p=0", str(path)], capture_output=True, text=True, timeout=30, check=True)
    pts = [float(line.split(',')[0]) for line in clock.stdout.splitlines() if line.split(',')[0].strip()]
    return {"width": v["width"], "height": v["height"], "fps": n/denominator,
            "duration_s": float(d["format"]["duration"]),
            "rotation_deg": rotation, "constant_frame_timing": constant_clock(pts, n/denominator),
            "sample_rate_hz": int(audio[0]["sample_rate"]) if audio else 0}

def constant_clock(pts, fps):
    # Technical ingestion tolerance, never a physical/model accuracy threshold.
    if len(pts) < 2 or not math.isfinite(fps) or fps <= 0:
        return False
    period = 1 / fps
    return all(math.isfinite(a) and math.isfinite(b) and b > a
               and abs((b-a)-period) <= max(.002, period*.05)
               for a,b in zip(pts,pts[1:]))

def write_new(path, data):
    # Exclusive reservation remains after interruption; no overwrite/retry.
    with path.open("x") as stream:
        json.dump(data, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        stream.flush()
        __import__("os").fsync(stream.fileno())

def frozen_candidate(doc, artifact, pipeline, validation, *, root, scope, catalog=None, probe=None):
    result = validate(doc)
    verify_bindings(doc, read(TARGETS) if catalog is None else catalog)
    selected = candidate_scope(scope)
    require(any(row["scope"] == selected and row["independent_evaluation_ready"]
                for row in result["scope_readiness"]), "candidate scope data not ready")
    require(isinstance(validation, dict) and validation.get("partition") == "validation",
            "validation partition required")
    require(candidate_scope(validation.get("scope")) == selected, "validation scope mismatch")
    artifact_sha, pipeline_sha = file_sha(artifact), file_sha(pipeline)
    require(validation.get("manifest_sha256") == digest(doc)
            and validation.get("artifact_sha256") == artifact_sha
            and validation.get("pipeline_sha256") == pipeline_sha, "validation binding mismatch")
    # Re-read every declared media/consent file at BOTH lifecycle writes.
    # This is workflow verification, not a snapshot against filesystem writers.
    verified = verify_media(doc, root, probe)
    return {"receipt_version": 2, "scope": selected, "manifest_sha256": digest(doc),
            "artifact_sha256": artifact_sha, "pipeline_sha256": pipeline_sha,
            "validation_sha256": digest(validation),
            "media_verification_sha256": digest(verified),
            "status": "FROZEN_NOT_ACCEPTED", "trained_by_this_tool": False}


def freeze(doc, artifact, pipeline, validation, output, *, root, scope, catalog=None, probe=None):
    receipt = frozen_candidate(doc, artifact, pipeline, validation,
                               root=root, scope=scope, catalog=catalog, probe=probe)
    write_new(output, receipt)
    return receipt


def open_test(doc, receipt, artifact, pipeline, validation, marker, *, root, scope,
              state_root, catalog=None, probe=None):
    # Keep the dataset-wide one-shot reservation even across candidate scopes.
    expected_marker = state_root.resolve(strict=True) / ("test-opened-" + doc["dataset_id"] + ".json")
    require(marker.resolve() == expected_marker.resolve(),
            "test marker must be the dataset's fixed test-opened-<dataset_id>.json sibling; a new candidate cannot reset it")
    try:
        expected = frozen_candidate(doc, artifact, pipeline, validation,
                                    root=root, scope=scope, catalog=catalog, probe=probe)
    except IntakeError as error:
        raise IntakeError(f"freeze drift: {error}") from error
    require(receipt == expected, "freeze drift or unrecognized receipt version")
    clips = [c["clip_id"] for c in doc["clips"] if c["partition"] == "test"
             and all(c[key] == expected["scope"][key] for key in SCOPE_FIELDS)]
    require(clips, "no test clips for candidate scope")
    write_new(marker, {"receipt_sha256": digest(receipt), "test_clip_ids": clips,
                       "scope": expected["scope"],
                       "media_verification_sha256": expected["media_verification_sha256"],
                       "status": "TEST_OPENED_NO_RESULT", "reuse_for_tuning_allowed": False})
    return {"test_clip_ids": clips, "scope": expected["scope"], "status": "TEST_OPENED_NO_RESULT"}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["validate", "verify-media", "freeze", "open-test"])
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--targets", type=Path, default=TARGETS)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--scope", type=Path, help="Exact candidate app/area/course SHA/lesson/movement JSON; required for freeze/open-test")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--pipeline", type=Path)
    parser.add_argument("--validation", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--out", type=Path)
    a = parser.parse_args()
    try:
        doc = read(a.manifest)
        validate(doc)
        catalog = read(a.targets)
        verify_bindings(doc, catalog)
        if a.action == "validate":
            result = validate(doc)
        elif a.action == "verify-media":
            require(a.root is not None, "--root required")
            result = verify_media(doc, a.root, ffprobe if a.probe else None)
        else:
            require(all((a.artifact, a.pipeline, a.validation, a.out, a.root, a.scope)),
                    "artifact/pipeline/validation/out/root/scope required")
            options = {"root": a.root, "scope": read(a.scope), "catalog": catalog,
                       "probe": ffprobe if a.probe else None}
            if a.action == "freeze":
                result = freeze(doc, a.artifact, a.pipeline, read(a.validation), a.out, **options)
            else:
                require(a.receipt is not None, "--receipt required")
                result = open_test(doc, read(a.receipt), a.artifact, a.pipeline,
                                   read(a.validation), a.out, state_root=a.manifest.parent, **options)
        print(json.dumps(result, sort_keys=True))
        return 0 if result.get("status") != "DRAFT_NO_DATA" else 2
    except (IntakeError, ValueError, TypeError, KeyError, OSError, subprocess.SubprocessError) as e:
        print(json.dumps({"status": "BLOCKED", "reason": str(e), "trained": False}))
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
