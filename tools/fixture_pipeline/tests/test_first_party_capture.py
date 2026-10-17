import copy
import json
from pathlib import Path
import sys
import tempfile
import subprocess
import shutil
import unittest

# Both staged development and the canonical fixture_pipeline/tests location.
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent if HERE.name == "tests" else HERE))
import first_party_capture as capture

def clip(index=1, partition="reference"):
    return {
        "clip_id": f"clip-{index}", "app": "gravita", "area": "bodyweight",
        "movement_id": "push_up", "lesson_id": "cal-01", "course_sha256": "a"*64,
        "participant_id": f"person-{index}", "session_id": f"session-{index}",
        "source_recording_id": f"source-{index}", "path": f"clip-{index}.mp4",
        "sha256": str(index)*64, "bytes": 12, "partition": partition,
        "purpose": "evaluation" if partition == "test" else "calibration",
        "view": "sagittal_left", "mirrored": False, "rotation_deg": 0,
        "duration_s": 6, "width": 1280, "height": 720, "fps": 30,
        "device": {"model":"qa-synthetic", "os":"qa", "camera":"rear", "timestamp_domain":"media_pts"},
        "audio": {"condition": "none", "sample_rate_hz": 0},
        "permissions": {"evidence_path": "permissions.txt", "evidence_sha256": "b"*64,
            "training": True, "evaluation": True, "demo_distribution": False,
            "no_bystanders": True, "private_details_checked": True, "music_rights": False},
        "annotations": [{"start_s": 1, "end_s": 3, "event": "rep",
            "observation": "observed", "label_origin": "human", "annotator_id": "reviewer-1"}],
    }

def manifest():
    return {"schema_version": 1, "dataset_id": "qa-synthetic-not-real-data",
            "clips": [clip(1, "train"), clip(2, "validation"), clip(3, "test")]}

def scope(doc):
    return {key: doc["clips"][0][key] for key in capture.SCOPE_FIELDS}

def targets(doc):
    grouped = {}
    for c in doc["clips"]:
        courses = grouped.setdefault((c["app"], c["area"]), {})
        courses.setdefault(c["course_sha256"], set()).add(c["lesson_id"])
    return {"areas": [{"app": app, "area": area, "courses": [
        {"sha256": sha, "lesson_ids": sorted(lessons)} for sha, lessons in courses.items()]}
        for (app, area), courses in grouped.items()]}

def synthetic_media(doc, root):
    (root / "permissions.txt").write_text("Synthetic fixture: no participant or real consent")
    for c in doc["clips"]:
        path = root / c["path"]
        path.write_bytes(("synthetic-no-human-" + c["clip_id"]).encode())
        c.update(sha256=capture.file_sha(path), bytes=path.stat().st_size)
        c["permissions"]["evidence_sha256"] = capture.file_sha(root / "permissions.txt")

def options(doc, root):
    return {"root": root, "scope": scope(doc), "catalog": targets(doc)}

class IntakeTests(unittest.TestCase):
    def rejected(self, doc, contains):
        with self.assertRaisesRegex(capture.IntakeError, contains):
            capture.validate(doc)

    def test_empty_template_never_becomes_training_or_physical_acceptance(self):
        d = manifest(); d["clips"] = []
        result = capture.validate(d)
        self.assertEqual(result["status"], "DRAFT_NO_DATA")
        self.assertFalse(result["trained"] or result["physically_validated"])

    def test_three_independent_groups_and_all_25_areas(self):
        self.assertTrue(capture.validate(manifest())["independent_evaluation_ready"])
        self.assertEqual(sum(map(len, capture.AREAS.values())), 25)
        for app, areas in capture.AREAS.items():
            for area in areas:
                d = manifest(); d["clips"][0].update(app=app, area=area)
                capture.validate(d)

    def test_single_performer_reference_only_is_collection_not_independent_test(self):
        d = manifest(); d["clips"] = [clip()]
        self.assertFalse(capture.validate(d)["independent_evaluation_ready"])

    def test_subject_leakage_across_apps(self):
        d = manifest(); d["clips"][2].update(app="lissom", area="hatha", participant_id="person-1")
        self.rejected(d, "split leakage: participant_id")

    def test_recording_session_and_exact_duplicate_leakage(self):
        for field in ["source_recording_id", "session_id", "sha256"]:
            d = manifest(); d["clips"][2][field] = d["clips"][0][field]
            self.rejected(d, "split leakage: " + field)

    def test_predictor_cannot_supply_ground_truth(self):
        d = manifest(); d["clips"][0]["annotations"][0]["label_origin"] = "mediapipe"
        self.rejected(d, "ground truth")

    def test_uncertain_and_unobservable_annotations_are_retained(self):
        for value in ["uncertain", "unobservable", "negative_control"]:
            d = manifest(); d["clips"][0]["annotations"][0]["observation"] = value
            capture.validate(d)

    def test_missing_or_wrong_permission_does_not_promote_video(self):
        for key in ["training", "no_bystanders", "private_details_checked"]:
            d = manifest(); d["clips"][0]["permissions"][key] = False
            self.rejected(d, "permission|privacy")
        d = manifest(); d["clips"][0]["purpose"] = "demonstration"
        self.rejected(d, "demo_distribution")

    def test_audio_rights_are_separate(self):
        d = manifest(); c=d["clips"][0]; c["audio"]={"condition":"licensed_music", "sample_rate_hz":48000}
        self.rejected(d, "music permission")

    def test_invalid_time_and_overlapping_events(self):
        for number in [float("nan"), float("inf"), -1, 1000, True]:
            d = manifest(); d["clips"][0]["annotations"][0]["end_s"] = number
            self.rejected(d, "number|unordered")
        d = manifest(); d["clips"][0]["annotations"] *= 2
        self.rejected(d, "overlapping")

    def test_unknown_fields_and_unknown_area_fail_closed(self):
        d = manifest(); d["clips"][0]["physical_accepted"] = True
        self.rejected(d, "unknown fields")
        d = manifest(); d["clips"][0]["area"] = "any_new_course"
        self.rejected(d, "unknown product/area")

    def test_media_hash_permission_hash_probe_and_path(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); (root/"permissions.txt").write_text("QA synthetic permission fixture; no real consent")
            (root/"clip-1.mp4").write_bytes(b"synthetic-not-a-demonstration")
            d=manifest(); d["clips"]=[clip()]; c=d["clips"][0]
            c["sha256"]=capture.file_sha(root/c["path"]); c["bytes"]=(root/c["path"]).stat().st_size
            c["permissions"]["evidence_sha256"]=capture.file_sha(root/"permissions.txt")
            probe=lambda _: dict(width=1280,height=720,fps=30,duration_s=6,sample_rate_hz=0,rotation_deg=0,constant_frame_timing=True)
            result=capture.verify_media(d, root, probe)
            self.assertFalse(result["visual_quality_or_expert_review_verified"])
            for name in ["../clip-1.mp4", "/etc/passwd", "https://example.test/a.mp4"]:
                bad=copy.deepcopy(d); bad["clips"][0]["path"]=name
                with self.assertRaises(capture.IntakeError): capture.verify_media(bad, root)
            (root/"alias.mp4").symlink_to(root/"clip-1.mp4")
            c["path"]="alias.mp4"
            with self.assertRaisesRegex(capture.IntakeError,"symlink"):capture.verify_media(d,root)
            c["path"]="clip-1.mp4"; (root/c["path"]).write_bytes(b"corrupted")
            with self.assertRaisesRegex(capture.IntakeError,"hash mismatch"):capture.verify_media(d,root)

    def test_undeclared_audio_rejected_by_probe(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); (root/"permissions.txt").write_text("synthetic")
            (root/"clip-1.mp4").write_bytes(b"synthetic")
            d=manifest(); d["clips"]=[clip()];c=d["clips"][0]
            c.update(sha256=capture.file_sha(root/c["path"]),bytes=9)
            c["permissions"]["evidence_sha256"]=capture.file_sha(root/"permissions.txt")
            probe=lambda _:dict(width=1280,height=720,fps=30,duration_s=6,sample_rate_hz=48000,rotation_deg=0,constant_frame_timing=True)
            with self.assertRaisesRegex(capture.IntakeError,"undeclared audio"):capture.verify_media(d,root,probe)

    def test_freeze_drift_and_one_time_test_open(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); artifact=root/"qa-parameters.json"; pipeline=root/"qa-pipeline.py"
            artifact.write_text('{"synthetic":true}');pipeline.write_text("# QA only, never a trainer")
            d=manifest(); synthetic_media(d,root); v={"scope":scope(d), "partition":"validation","manifest_sha256":capture.digest(d),
                "artifact_sha256":capture.file_sha(artifact),"pipeline_sha256":capture.file_sha(pipeline)}
            frozen=capture.freeze(d,artifact,pipeline,v,root/"freeze.json",**options(d,root))
            with self.assertRaises(FileExistsError):capture.freeze(d,artifact,pipeline,v,root/"freeze.json",**options(d,root))
            changed=copy.deepcopy(d);changed["clips"][0]["view"]="frontal"
            with self.assertRaisesRegex(capture.IntakeError,"drift"):capture.open_test(changed,frozen,artifact,pipeline,v,root/("test-opened-"+d["dataset_id"]+".json"),state_root=root,**options(d,root))
            result=capture.open_test(d,frozen,artifact,pipeline,v,root/("test-opened-"+d["dataset_id"]+".json"),state_root=root,**options(d,root))
            self.assertEqual(result["test_clip_ids"],["clip-3"])
            self.assertEqual(result["status"],"TEST_OPENED_NO_RESULT")
            with self.assertRaises(FileExistsError):capture.open_test(d,frozen,artifact,pipeline,v,root/("test-opened-"+d["dataset_id"]+".json"),state_root=root,**options(d,root))
            artifact.write_text("changed after test")
            with self.assertRaisesRegex(capture.IntakeError,"drift"):capture.open_test(d,frozen,artifact,pipeline,v,root/("test-opened-"+d["dataset_id"]+".json"),state_root=root,**options(d,root))

    def test_cannot_freeze_without_real_split_population(self):
        d=manifest();d["clips"]=[clip()]
        with self.assertRaisesRegex(capture.IntakeError,"not ready"):
            capture.freeze(d,Path("absent"),Path("absent"),{},Path("absent"),**options(d,Path(".")))

    def test_cli_new_candidate_cannot_select_another_test_marker(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); d=manifest(); synthetic_media(d,root); m=root/"manifest.json"
            m.write_text(json.dumps(d));a=root/"artifact";p=root/"pipeline";v=root/"validation.json"
            a.write_text("synthetic");p.write_text("synthetic")
            validation={"scope":scope(d), "partition":"validation","manifest_sha256":capture.digest(d),
                "artifact_sha256":capture.file_sha(a),"pipeline_sha256":capture.file_sha(p)}
            v.write_text(json.dumps(validation));receipt=root/"freeze.json"
            capture.freeze(d,a,p,validation,receipt,**options(d,root))
            targets=root/"targets.json"
            targets.write_text(json.dumps({"areas":[{"app":"gravita","area":"bodyweight",
                "courses":[{"sha256":"a"*64,"lesson_ids":["cal-01"]}]}]}))
            scope_file=root/"scope.json";scope_file.write_text(json.dumps(scope(d)))
            cmd=[sys.executable,str(Path(capture.__file__)),"open-test","--root",str(root),"--scope",str(scope_file),"--manifest",str(m),
                "--artifact",str(a),"--pipeline",str(p),"--validation",str(v),"--receipt",str(receipt),"--targets",str(targets)]
            wrong=subprocess.run(cmd+["--out",str(root/"new-candidate-marker.json")],capture_output=True,text=True)
            self.assertEqual(wrong.returncode,2);self.assertIn("fixed",wrong.stdout)
            fixed=root/("test-opened-"+d["dataset_id"]+".json")
            opened=subprocess.run(cmd+["--out",str(fixed)],capture_output=True,text=True)
            self.assertEqual(opened.returncode,0,opened.stdout)
            # Different candidate receipt still shares the dataset's marker.
            receipt2=root/"another-candidate.json";capture.freeze(d,a,p,validation,receipt2,**options(d,root))
            cmd[cmd.index(str(receipt))]=str(receipt2)
            repeated=subprocess.run(cmd+["--out",str(fixed)],capture_output=True,text=True)
            self.assertEqual(repeated.returncode,2)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),"existing local media CLI unavailable")
    def test_actual_probe_of_synthetic_technical_video_not_human_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);video=root/"clip-1.mp4"
            subprocess.run(["ffmpeg","-v","error","-f","lavfi","-i",
                "color=c=black:s=1280x720:r=30","-t","6","-an","-c:v","mpeg4",
                "-threads","1","-q:v","31",str(video)],check=True,timeout=20)
            (root/"permissions.txt").write_text("synthetic fixture; no human or rights claim")
            d=manifest();d["clips"]=[clip()];c=d["clips"][0]
            c.update(sha256=capture.file_sha(video),bytes=video.stat().st_size)
            c["permissions"]["evidence_sha256"]=capture.file_sha(root/"permissions.txt")
            result=capture.verify_media(d,root,capture.ffprobe)
            self.assertTrue(result["technical_probe_verified"])
            self.assertFalse(result["physically_validated"])

    def test_vfr_reordered_or_missing_pts_cannot_feed_index_fps_timing(self):
        self.assertTrue(capture.constant_clock([0,1/30,2/30],30))
        for pts in [[0,.033,.12],[0,.033,.033],[0,.033,.01],[],[0,float('nan')]]:
            self.assertFalse(capture.constant_clock(pts,30))

    def test_exact_course_version_and_lesson_binding(self):
        d=manifest();catalog={"areas":[{"app":"gravita","area":"bodyweight",
          "courses":[{"sha256":"a"*64,"lesson_ids":["cal-01"]}]}]}
        capture.verify_bindings(d,catalog)
        for field,value in [("course_sha256","b"*64),("lesson_id","invented"),("area","barbell")]:
            bad=copy.deepcopy(d);bad["clips"][0][field]=value
            with self.assertRaisesRegex(capture.IntakeError,"binding"):capture.verify_bindings(bad,catalog)

if __name__ == "__main__":
    unittest.main()
