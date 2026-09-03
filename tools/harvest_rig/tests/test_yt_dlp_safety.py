#!/usr/bin/env python
"""Network-free tests for the hermetic yt-dlp process boundary."""
from __future__ import annotations

import os
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Importing harvest should not require the heavyweight video stack for these
# subprocess-contract tests.
sys.modules.setdefault("cv2", ModuleType("cv2"))
sys.modules.setdefault("numpy", ModuleType("numpy"))

import d1_gate  # noqa: E402
import harvest  # noqa: E402
import yt_dlp_safety as safety  # noqa: E402


class YtDlpSafetyTest(unittest.TestCase):
    @staticmethod
    def _verified_binary() -> safety.SafeYtDlp:
        return safety.SafeYtDlp(
            path="/trusted/yt-dlp",
            version="2026.07.04",
            release=(2026, 7, 4),
        )

    def _probe(self, version: str) -> safety.SafeYtDlp:
        completed = SimpleNamespace(returncode=0, stdout=f"{version}\n", stderr="")
        with mock.patch.object(
            safety.shutil, "which", return_value=sys.executable
        ), mock.patch.object(safety.subprocess, "run", return_value=completed):
            return safety.require_safe_yt_dlp()

    def test_probe_uses_resolved_binary_and_hermetic_flags(self) -> None:
        completed = SimpleNamespace(
            returncode=0,
            stdout="2026.07.04\n",
            stderr="",
        )
        with mock.patch.object(
            safety.shutil, "which", return_value=sys.executable
        ), mock.patch.object(
            safety.subprocess, "run", return_value=completed
        ) as run:
            binary = safety.require_safe_yt_dlp()

        self.assertEqual(binary.path, str(Path(sys.executable).resolve()))
        self.assertEqual(binary.version, "2026.07.04")
        probe = run.call_args.args[0]
        self.assertEqual(probe[0], binary.path)
        self.assertEqual(probe[-1], "--version")
        for flag in safety.HERMETIC_YT_DLP_FLAGS:
            self.assertIn(flag, probe)

    def test_exact_security_floor_and_newer_date_release_are_accepted(self) -> None:
        self.assertEqual(self._probe("2026.06.09").release, (2026, 6, 9))
        self.assertEqual(self._probe("2026.07.04.232828").release, (2026, 7, 4))

    def test_old_malformed_failed_and_missing_binaries_fail_closed(self) -> None:
        cases = (
            (SimpleNamespace(returncode=0, stdout="2026.06.08\n", stderr=""),
             "minimum"),
            (SimpleNamespace(returncode=0, stdout="rolling\n", stderr=""),
             "version"),
            (SimpleNamespace(returncode=2, stdout="", stderr="bad option"),
             "probe"),
        )
        for completed, marker in cases:
            with self.subTest(marker=marker), mock.patch.object(
                safety.shutil, "which", return_value=sys.executable
            ), mock.patch.object(
                safety.subprocess, "run", return_value=completed
            ):
                with self.assertRaisesRegex(safety.YtDlpSafetyError, marker):
                    safety.require_safe_yt_dlp()

        with mock.patch.object(safety.shutil, "which", return_value=None):
            with self.assertRaisesRegex(safety.YtDlpSafetyError, "not found"):
                safety.require_safe_yt_dlp()

        with mock.patch.object(
            safety.shutil, "which", return_value=sys.executable
        ), mock.patch.object(
            safety.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired("yt-dlp", 10),
        ):
            with self.assertRaisesRegex(safety.YtDlpSafetyError, "timed out"):
                safety.require_safe_yt_dlp()

        with mock.patch.object(
            safety.shutil, "which", return_value=sys.executable
        ), mock.patch.object(
            safety.subprocess, "run", side_effect=OSError("exec denied")
        ):
            with self.assertRaisesRegex(safety.YtDlpSafetyError, "could not run"):
                safety.require_safe_yt_dlp()

        with self.assertRaisesRegex(safety.YtDlpSafetyError, "invalid release date"):
            self._probe("2026.13.40")

    def test_command_owns_the_terminator_before_a_leading_dash_source(self) -> None:
        binary = self._verified_binary()
        command = binary.command(
            ["--skip-download", "--write-auto-subs"],
            "--config-locations=/tmp/hostile.conf",
        )

        self.assertEqual(command[0], "/trusted/yt-dlp")
        self.assertEqual(command[-2:], ["--", "--config-locations=/tmp/hostile.conf"])
        self.assertEqual(command.count("--"), 1)
        for flag in safety.HERMETIC_YT_DLP_FLAGS:
            self.assertIn(flag, command)
            self.assertGreater(command.index(flag), command.index("--write-auto-subs"))

    def test_callers_cannot_override_safety_policy(self) -> None:
        binary = self._verified_binary()
        unsafe_options = (
            "--",
            "--exec=touch /tmp/pwned",
            "--exec-before-download",
            "--config-locations=/tmp/hostile.conf",
            "--plugin-dirs",
            "--remote-components=ejs:github",
        )
        for option in unsafe_options:
            with self.subTest(option=option):
                with self.assertRaisesRegex(
                    safety.YtDlpSafetyError, "controlled by safety policy"
                ):
                    binary.command([option], "https://example.invalid/video")

    def test_pull_cannot_reuse_stale_persistent_metadata(self) -> None:
        binary = self._verified_binary()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            raw_dir = root / "raw"
            raw_dir.mkdir()
            (raw_dir / "safe.info.json").write_text(
                '{"id":"safe","webpage_url":"https://example.invalid/v"}',
                encoding="utf-8",
            )
            (raw_dir / "safe.mp4").write_bytes(b"stale")

            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess, "run", return_value=completed
            ) as pull_run:
                with self.assertRaisesRegex(RuntimeError, "info.json"):
                    harvest.pull(
                        "--config-locations=/tmp/hostile.conf",
                        raw_dir,
                        app="jablab",
                    )

            pull_command = pull_run.call_args.args[0]
            self.assertEqual(
                pull_command[-2:],
                ["--", "--config-locations=/tmp/hostile.conf"],
            )
            self.assertEqual((raw_dir / "safe.mp4").read_bytes(), b"stale")

    def test_pull_publishes_one_exact_staged_pair_and_stamps_version(self) -> None:
        binary = self._verified_binary()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temp_dir:
            raw_dir = Path(temp_dir) / "raw"
            raw_dir.mkdir()
            raw_dir.joinpath("other.info.json").write_text(
                '{"id":"other","webpage_url":"https://example.invalid/old"}',
                encoding="utf-8",
            )
            fake_manifest = SimpleNamespace(local_path=None)
            fake_manifest.absorb_info_json = mock.Mock()
            fake_manifest.record = mock.Mock()

            def successful_download(command, **_kwargs):
                template = Path(command[command.index("-o") + 1])
                self.assertNotEqual(template.parent, raw_dir)
                template.parent.joinpath("safe.info.json").write_text(
                    '{"id":"safe","webpage_url":"https://example.invalid/v"}',
                    encoding="utf-8",
                )
                template.parent.joinpath("safe.mp4").write_bytes(b"fresh")
                return completed

            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess, "run", side_effect=successful_download
            ), mock.patch.object(
                harvest.HarvestManifest, "start", return_value=fake_manifest
            ) as manifest_start:
                result = harvest.pull(
                    "https://example.invalid/current",
                    raw_dir,
                    app="jablab",
                )

            self.assertIs(result, fake_manifest)
            self.assertEqual((raw_dir / "safe.mp4").read_bytes(), b"fresh")
            self.assertTrue((raw_dir / "safe.info.json").is_file())
            self.assertTrue((raw_dir / "other.info.json").is_file())
            self.assertEqual(
                manifest_start.call_args.kwargs["yt_dlp_version"],
                "2026.07.04",
            )
            self.assertEqual(
                fake_manifest.local_path,
                str(raw_dir.resolve() / "safe.mp4"),
            )

    def test_pull_rejects_staged_filename_and_internal_id_mismatch(self) -> None:
        binary = self._verified_binary()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temp_dir:
            raw_dir = Path(temp_dir) / "raw"
            raw_dir.mkdir()

            def mismatched_download(command, **_kwargs):
                staging = Path(command[command.index("-o") + 1]).parent
                staging.joinpath("wrong.info.json").write_text(
                    '{"id":"safe","webpage_url":"https://example.invalid/v"}',
                    encoding="utf-8",
                )
                staging.joinpath("safe.mp4").write_bytes(b"fresh")
                return completed

            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess, "run", side_effect=mismatched_download
            ):
                with self.assertRaisesRegex(RuntimeError, "eşleşmiyor"):
                    harvest.pull(
                        "https://example.invalid/current",
                        raw_dir,
                        app="jablab",
                    )

            self.assertEqual(list(raw_dir.iterdir()), [])

    def test_pull_rejects_multiple_media_and_existing_id_collisions(self) -> None:
        binary = self._verified_binary()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        def staged_download(command, *, extra_media: bool, **_kwargs):
            staging = Path(command[command.index("-o") + 1]).parent
            staging.joinpath("safe.info.json").write_text(
                '{"id":"safe","webpage_url":"https://example.invalid/v"}',
                encoding="utf-8",
            )
            staging.joinpath("safe.mp4").write_bytes(b"fresh")
            if extra_media:
                staging.joinpath("safe.webm").write_bytes(b"ambiguous")
            return completed

        with tempfile.TemporaryDirectory() as temp_dir:
            raw_dir = Path(temp_dir) / "raw"
            raw_dir.mkdir()
            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess,
                "run",
                side_effect=lambda command, **kwargs: staged_download(
                    command, extra_media=True, **kwargs
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "medya dosyası"):
                    harvest.pull(
                        "https://example.invalid/current",
                        raw_dir,
                        app="jablab",
                    )
            self.assertEqual(list(raw_dir.iterdir()), [])

        with tempfile.TemporaryDirectory() as temp_dir:
            raw_dir = Path(temp_dir) / "raw"
            raw_dir.mkdir()
            raw_dir.joinpath("safe.mp4").write_bytes(b"preserve")
            with mock.patch.object(
                harvest, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                harvest.subprocess,
                "run",
                side_effect=lambda command, **kwargs: staged_download(
                    command, extra_media=False, **kwargs
                ),
            ):
                with self.assertRaisesRegex(RuntimeError, "zaten var"):
                    harvest.pull(
                        "https://example.invalid/current",
                        raw_dir,
                        app="jablab",
                    )
            self.assertEqual((raw_dir / "safe.mp4").read_bytes(), b"preserve")

    def test_d1_binds_subtitle_to_one_successful_call(self) -> None:
        binary = self._verified_binary()
        completed = SimpleNamespace(returncode=0, stdout="", stderr="")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            def successful_subtitle(command, **_kwargs):
                template = Path(command[command.index("-o") + 1])
                self.assertNotEqual(template.parent, root)
                template.parent.joinpath("-leadingId.en.json3").write_text(
                    json.dumps({
                        "events": [{
                            "tStartMs": 0,
                            "dDurationMs": 1200,
                            "segs": [{"utf8": "bound subtitle"}],
                        }],
                    }),
                    encoding="utf-8",
                )
                return completed

            with mock.patch.object(
                d1_gate, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                d1_gate.subprocess, "run", side_effect=successful_subtitle
            ) as subtitle_run:
                self.assertEqual(
                    d1_gate.fetch_subtitle("-leadingId", workdir=root),
                    ("bound subtitle", 1.2),
                )

            subtitle_command = subtitle_run.call_args.args[0]
            self.assertIn("--no-playlist", subtitle_command)
            self.assertEqual(
                subtitle_command[-2:],
                ["--", "https://www.youtube.com/watch?v=-leadingId"],
            )

            with mock.patch.object(
                d1_gate,
                "require_safe_yt_dlp",
                side_effect=safety.YtDlpSafetyError("unsafe binary"),
            ):
                with self.assertRaisesRegex(
                    safety.YtDlpSafetyError, "unsafe binary"
                ):
                    d1_gate.fetch_subtitle("safeId", workdir=root)

            with mock.patch.object(
                d1_gate, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                d1_gate.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired("yt-dlp", 5),
            ):
                self.assertEqual(
                    d1_gate.fetch_subtitle("safeId", workdir=root),
                    (None, None),
                )

    def test_d1_rejects_bad_ids_and_never_reuses_prefix_output(self) -> None:
        binary = self._verified_binary()
        failed = SimpleNamespace(returncode=1, stdout="", stderr="network")

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            root.joinpath("abc.en.json3").write_text(
                json.dumps({
                    "events": [{
                        "tStartMs": 0,
                        "dDurationMs": 900,
                        "segs": [{"utf8": "wrong source"}],
                    }],
                }),
                encoding="utf-8",
            )
            with mock.patch.object(
                d1_gate, "require_safe_yt_dlp", return_value=binary
            ), mock.patch.object(
                d1_gate.subprocess, "run", return_value=failed
            ) as run:
                self.assertEqual(
                    d1_gate.fetch_subtitle("ab", workdir=root),
                    (None, None),
                )
                for invalid_id in ("", "../escape", "id&list=playlist", "x/y"):
                    with self.subTest(video_id=invalid_id):
                        with self.assertRaises(ValueError):
                            d1_gate.fetch_subtitle(invalid_id, workdir=root)

            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
