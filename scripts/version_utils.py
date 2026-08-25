"""Shared version parsing and validation utilities for Nexus build scripts."""

import re
from pathlib import Path

# Regular expression to match semantic versions (X.Y.Z or X.Y.Z+build)
VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")

# Patterns for release branch names (e.g., release/1.2.3, v1.2.3, 1.2.3)
RELEASE_BRANCH_PATTERN = re.compile(r"^(?:release/|v)?(\d+\.\d+\.\d+)$")


def parse_version(version_str: str) -> tuple[tuple[int, int, int], int] | None:
    """Parses a semantic version string into major/minor/patch tuple and build number.

    Args:
        version_str: Raw version string (e.g. '1.2.3+4' or '1.2.3').

    Returns:
        tuple[tuple[int, int, int], int] | None:
            Version tuple ((major, minor, patch), build_num), or None if invalid.
    """
    match = VERSION_PATTERN.match(version_str.strip())
    if not match:
        return None
    major, minor, patch, build = match.groups()
    build_num = int(build) if build else 1
    return (int(major), int(minor), int(patch)), build_num


def read_pubspec_version(
    pubspec_path: Path | str = Path("mobile/pubspec.yaml"),
) -> tuple[str | None, str]:
    """Reads current version string from pubspec.yaml.

    Args:
        pubspec_path: Path to pubspec.yaml file.

    Returns:
        tuple[str | None, str]: Extracted version string and entire pubspec content.
    """
    path = Path(pubspec_path)
    if not path.exists():
        return None, ""

    content = path.read_text(encoding="utf-8")
    for line in content.splitlines():
        if line.startswith("version:"):
            version_str = line.split(":", 1)[1].strip()
            return version_str, content
    return None, content


def extract_app_version(
    pubspec_path: Path | str = Path("mobile/pubspec.yaml"),
) -> str | None:
    """Extracts the base semantic version (without build number) from pubspec.yaml.

    Args:
        pubspec_path: Path to pubspec.yaml file.

    Returns:
        str | None: Base version string (e.g. '1.0.8') or None.
    """
    version_str, _ = read_pubspec_version(pubspec_path)
    if not version_str:
        return None
    parsed = parse_version(version_str)
    if not parsed:
        return version_str.split("+")[0]
    (major, minor, patch), _ = parsed
    return f"{major}.{minor}.{patch}"
