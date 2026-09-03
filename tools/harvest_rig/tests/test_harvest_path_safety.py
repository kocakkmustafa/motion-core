#!/usr/bin/env python
"""Network-free regression tests for harvest output-path containment."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# This suite exercises only path construction. Keep it runnable without the
# heavyweight video stack and make any accidental CV use fail loudly.
sys.modules.setdefault("cv2", ModuleType("cv2"))
sys.modules.setdefault("numpy", ModuleType("numpy"))

import harvest  # noqa: E402
from yt_dlp_safety import SafeYtDlp  # noqa: E402


class HarvestPathSafetyTest(unittest.TestCase):
    def test_accepts_existing_portable_video_id_shapes(self) -> None:
        for video_id in ("JrCgR4xwg0A", "_G-hONZsj1w", "clip.01"):
            self.assertEqual(harvest.validate_video_id(video_id), video_id)

    def test_rejects_traversal_encoded_and_non_string_ids(self) -> None:
        unsafe_ids = (
            None,
            42,
            "",
            ".",
            "..",
            "../outside",
            "/tmp/outside",
            r"..\outside",
            r"C:\tmp\outside",
            "nested/id",
            "%2Ftmp%2Foutside",
            "..%252Foutside",
            "abc\n",
            "abc\x00def",
            "x" * 129,
        )
        for video_id in unsafe_ids:
            with self.subTest(video_id=video_id):
                with self.assertRaises(ValueError):
                    harvest.validate_video_id(video_id)

    def test_pull_rejects_malicious_info_id_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            raw_dir = Path(temp_dir) / "raw"
            raw_dir.mkdir()
            (raw_dir / "safe.info.json").write_text(
                json.dumps({"id": "/tmp/outside", "webpage_url": "fixture"}),
                encoding="utf-8",
            )
            completed = SimpleNamespace(returncode=0, stderr="")
            binary = SafeYtDlp(
                path="/trusted/yt-dlp",
                version="2026.07.04",
                release=(2026, 7, 4),
            )

            def write_malicious_metadata(command, **_kwargs):
                staging = Path(command[command.index("-o") + 1]).parent
                staging.joinpath("unsafe.info.json").write_text(
                    json.dumps({
                        "id": "/tmp/outside",
                        "webpage_url": "fixture",
                    }),
                    encoding="utf-8",
                )
                return completed

            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess, "run", side_effect=write_malicious_metadata
            ):
                with self.assertRaises(ValueError):
                    harvest.pull("https://example.invalid/video", raw_dir, app="jablab")

    def test_output_path_must_resolve_to_a_direct_child(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "library" / "manifests"
            root.mkdir(parents=True)

            safe = harvest.direct_child_output_path(root, "abc123.json")
            self.assertEqual(safe.parent, root.resolve())

            for filename in (
                "../outside.json",
                "/tmp/outside.json",
                "nested/x.json",
                r"..\outside.json",
            ):
                with self.subTest(filename=filename):
                    with self.assertRaises(ValueError):
                        harvest.direct_child_output_path(root, filename)

            outside = Path(temp_dir) / "outside.json"
            outside.write_text("preserve", encoding="utf-8")
            (root / "linked.json").symlink_to(outside)
            with self.assertRaises(ValueError):
                harvest.direct_child_output_path(root, "linked.json")
            self.assertEqual(outside.read_text(encoding="utf-8"), "preserve")

    def test_cmd_run_rechecks_manifest_id_before_any_manifest_write(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            library = Path(temp_dir) / "library"
            escaped = Path(temp_dir) / "outside.json"
            manifest = SimpleNamespace(video_id="../../outside", movement=None)
            args = SimpleNamespace(
                library=str(library),
                url="https://example.invalid/video",
                app="jablab",
                movement=None,
            )

            with mock.patch.object(harvest, "pull", return_value=manifest):
                with self.assertRaises(ValueError):
                    harvest.cmd_run(args)

            self.assertFalse(escaped.exists())


if __name__ == "__main__":
    unittest.main()
