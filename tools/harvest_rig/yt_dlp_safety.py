"""Fail-closed yt-dlp discovery and command construction.

The harvest rig accepts remote media, so the downloader is part of the trust
boundary rather than an incidental workstation dependency.  Every networked
invocation must pass through this module.
"""
from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Sequence

MINIMUM_YT_DLP_RELEASE = (2026, 6, 9)
MINIMUM_YT_DLP_VERSION = "2026.06.09"

# Command-line values are parsed after configuration values, so these switches
# both suppress ambient extension points and override unsafe earlier settings.
HERMETIC_YT_DLP_FLAGS = (
    "--ignore-config",
    "--no-plugin-dirs",
    "--no-remote-components",
    "--no-exec",
)

_POLICY_CONTROLLED_OPTIONS = frozenset({
    "--config-locations",
    "--exec",
    "--exec-before-download",
    "--plugin-dirs",
    "--remote-components",
})

_VERSION_PATTERN = re.compile(
    r"^(?P<year>\d{4})\.(?P<month>\d{1,2})\.(?P<day>\d{1,2})"
    r"(?:\.\d+)?$"
)
_PORTABLE_VIDEO_ID_PATTERN = re.compile(
    r"^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$"
)


class YtDlpSafetyError(RuntimeError):
    """Raised before remote input reaches an untrusted yt-dlp boundary."""


def validate_video_id(value: object) -> str:
    """Return one portable media ID, or reject it before URL/path use."""
    if not isinstance(value, str) or not _PORTABLE_VIDEO_ID_PATTERN.fullmatch(value):
        raise ValueError(
            "yt-dlp media id is not a safe portable identifier"
        )
    return value


@dataclass(frozen=True)
class SafeYtDlp:
    """A resolved yt-dlp executable whose release passed the safety floor."""

    path: str
    version: str
    release: tuple[int, int, int]

    def command(self, options: Sequence[str], source: str) -> list[str]:
        """Build one hermetic invocation with an owned argument terminator."""
        for option in options:
            option_name = option.split("=", maxsplit=1)[0]
            if option == "--" or option_name in _POLICY_CONTROLLED_OPTIONS:
                raise YtDlpSafetyError(
                    f"yt-dlp option is controlled by safety policy: {option_name}"
                )
        if not isinstance(source, str) or not source:
            raise YtDlpSafetyError("yt-dlp source must be a non-empty string")
        return [
            self.path,
            *options,
            *HERMETIC_YT_DLP_FLAGS,
            "--",
            source,
        ]


def _parse_release(raw_version: str) -> tuple[int, int, int]:
    match = _VERSION_PATTERN.fullmatch(raw_version)
    if match is None:
        raise YtDlpSafetyError(
            f"yt-dlp version is not a supported date release: {raw_version!r}"
        )
    release = tuple(int(match.group(name)) for name in ("year", "month", "day"))
    try:
        date(*release)
    except ValueError as error:
        raise YtDlpSafetyError(
            f"yt-dlp version contains an invalid release date: {raw_version!r}"
        ) from error
    return release


def require_safe_yt_dlp(*, timeout_s: int = 15) -> SafeYtDlp:
    """Resolve and verify yt-dlp before any attacker-influenced media is read."""
    candidate = shutil.which("yt-dlp")
    if candidate is None:
        raise YtDlpSafetyError(
            f"yt-dlp not found; install release >= {MINIMUM_YT_DLP_VERSION}"
        )
    try:
        executable = str(Path(candidate).resolve(strict=True))
    except OSError as error:
        raise YtDlpSafetyError("yt-dlp executable could not be resolved") from error

    probe = [executable, *HERMETIC_YT_DLP_FLAGS, "--version"]
    try:
        completed = subprocess.run(
            probe,
            capture_output=True,
            text=True,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired as error:
        raise YtDlpSafetyError("yt-dlp version probe timed out") from error
    except OSError as error:
        raise YtDlpSafetyError("yt-dlp version probe could not run") from error

    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()[-400:]
        suffix = f": {detail}" if detail else ""
        raise YtDlpSafetyError(f"yt-dlp version probe failed{suffix}")

    version = (completed.stdout or "").strip()
    release = _parse_release(version)
    if release < MINIMUM_YT_DLP_RELEASE:
        raise YtDlpSafetyError(
            "yt-dlp release is below the security minimum "
            f"{MINIMUM_YT_DLP_VERSION}: {version}"
        )
    return SafeYtDlp(path=executable, version=version, release=release)


def optional_safe_yt_dlp_version() -> str:
    """Return a verified provenance stamp without weakening required callers."""
    try:
        return require_safe_yt_dlp().version
    except YtDlpSafetyError:
        return "unavailable-or-unsafe"
