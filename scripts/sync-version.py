#!/usr/bin/env python3
"""Mobile app version synchronization and git pre-commit/post-checkout hook utility.

Synchronizes semantic version numbers across pubspec.yaml and Android
local.properties based on release branch names.
"""

import shutil
import subprocess
import sys
from pathlib import Path

# Add script directory to path if run standalone
sys.path.insert(0, str(Path(__file__).parent.resolve()))

from version_utils import (
    RELEASE_BRANCH_PATTERN,
    VERSION_PATTERN,
    parse_version,
    read_pubspec_version,
)

PUBSPEC_PATH = Path("mobile/pubspec.yaml")


def get_current_branch() -> str | None:
    """Retrieves the active git branch name.

    Returns:
        str | None: Active branch name string or None if not in a git repository.
    """
    git_path = shutil.which("git") or "git"
    try:
        result = subprocess.run(
            [git_path, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.SubprocessError:
        return None



LOCAL_PROPERTIES_PATH = Path("mobile/android/local.properties")


def write_pubspec_version(content: str, new_version_str: str) -> bool:
    """Writes updated version string to mobile/pubspec.yaml and local.properties.

    Args:
        content: Original pubspec.yaml file content.
        new_version_str: Target version string to write.

    Returns:
        bool: True if updated, False otherwise.
    """
    lines: list[str] = []
    updated = False
    for line in content.splitlines():
        if line.startswith("version:"):
            lines.append(f"version: {new_version_str}")
            updated = True
        else:
            lines.append(line)

    PUBSPEC_PATH.write_text("\n".join(lines) + "\n")
    update_local_properties(new_version_str)
    return updated


def update_local_properties(new_version_str: str) -> None:
    """Updates flutter.versionName and flutter.versionCode in local.properties.

    Args:
        new_version_str: Target version string.
    """
    if not LOCAL_PROPERTIES_PATH.exists():
        return

    match = VERSION_PATTERN.match(new_version_str)
    if not match:
        return
    major, minor, patch, build = match.groups()
    version_name = f"{major}.{minor}.{patch}"
    version_code = build if build else "1"

    lines: list[str] = []
    content = LOCAL_PROPERTIES_PATH.read_text()
    has_name = False
    has_code = False

    for line in content.splitlines():
        if line.startswith("flutter.versionName="):
            lines.append(f"flutter.versionName={version_name}")
            has_name = True
        elif line.startswith("flutter.versionCode="):
            lines.append(f"flutter.versionCode={version_code}")
            has_code = True
        else:
            lines.append(line)

    if not has_name:
        lines.append(f"flutter.versionName={version_name}")
    if not has_code:
        lines.append(f"flutter.versionCode={version_code}")

    LOCAL_PROPERTIES_PATH.write_text("\n".join(lines) + "\n")


def _resolve_branch_bump(
    branch_version_str: str,
    pubspec_version_str: str,
    original_content: str,
    pre_commit: bool,
    post_checkout: bool,
) -> str:
    parsed_branch = parse_version(branch_version_str)
    parsed_pubspec = parse_version(pubspec_version_str)

    if not (parsed_branch and parsed_pubspec):
        return pubspec_version_str

    branch_ver, _ = parsed_branch
    pubspec_ver, _ = parsed_pubspec

    if branch_ver < pubspec_ver:
        err_msg = (
            f"Error: Branch version ({branch_version_str}) cannot be "
            f"less than current app version ({pubspec_version_str})."
        )
        print(err_msg)
        sys.exit(1)

    if branch_ver > pubspec_ver:
        new_version_str = f"{branch_version_str}+1"
        git_path = shutil.which("git") or "git"
        if pre_commit:
            msg = f"Auto-bumping version in pubspec.yaml to {new_version_str}..."
            print(msg)
            write_pubspec_version(original_content, new_version_str)
            cmd = [git_path, "add", str(PUBSPEC_PATH), str(LOCAL_PROPERTIES_PATH)]
            subprocess.run(cmd, check=True)
        elif post_checkout:
            msg = f"Auto-bumping pubspec to {new_version_str}..."
            print(msg)
            write_pubspec_version(original_content, new_version_str)
        else:
            write_pubspec_version(original_content, new_version_str)
        return new_version_str

    return pubspec_version_str


def main() -> None:
    """Main execution function for version synchronization across mobile build files."""
    pre_commit = "--pre-commit" in sys.argv
    post_checkout = "--post-checkout" in sys.argv

    pubspec_version_str, original_content = read_pubspec_version()
    if not pubspec_version_str:
        print("Error: Could not parse version from pubspec.yaml")
        sys.exit(1)

    effective_version = pubspec_version_str
    branch = get_current_branch()
    if branch and branch not in ("HEAD", "main", "master", "dev", "develop"):
        match = RELEASE_BRANCH_PATTERN.match(branch)
        if match:
            effective_version = _resolve_branch_bump(
                match.group(1),
                pubspec_version_str,
                original_content,
                pre_commit,
                post_checkout,
            )

    update_local_properties(effective_version)


if __name__ == "__main__":
    main()
