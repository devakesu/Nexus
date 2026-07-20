#!/usr/bin/env python3
import re
import shutil
import subprocess
import sys
from pathlib import Path

PUBSPEC_PATH = Path("mobile/pubspec.yaml")

# Regular expression to match semantic versions (X.Y.Z)
VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")

# Patterns for release branch names (e.g., release/1.2.3, v1.2.3, 1.2.3)
RELEASE_BRANCH_PATTERN = re.compile(r"^(?:release/|v)?(\d+\.\d+\.\d+)$")


def get_current_branch() -> str | None:
    git_path = shutil.which("git") or "git"
    try:
        result = subprocess.run(  # noqa: S603
            [git_path, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.SubprocessError:
        return None


def parse_version(version_str: str) -> tuple[tuple[int, int, int], int] | None:
    match = VERSION_PATTERN.match(version_str)
    if not match:
        return None
    major, minor, patch, build = match.groups()
    build_num = int(build) if build else 1
    return (int(major), int(minor), int(patch)), build_num


def read_pubspec_version() -> tuple[str | None, str]:
    if not PUBSPEC_PATH.exists():
        print(f"Error: {PUBSPEC_PATH} not found.")  # noqa: T201
        sys.exit(1)

    content = PUBSPEC_PATH.read_text()
    for line in content.splitlines():
        if line.startswith("version:"):
            version_str = line.split(":", 1)[1].strip()
            return version_str, content
    return None, content


def write_pubspec_version(content: str, new_version_str: str) -> bool:
    lines: list[str] = []
    updated = False
    for line in content.splitlines():
        if line.startswith("version:"):
            lines.append(f"version: {new_version_str}")
            updated = True
        else:
            lines.append(line)

    PUBSPEC_PATH.write_text("\n".join(lines) + "\n")
    return updated


def main() -> None:  # noqa: C901
    # Detect running mode
    pre_commit = "--pre-commit" in sys.argv
    post_checkout = "--post-checkout" in sys.argv

    branch = get_current_branch()
    if not branch or branch in ("HEAD", "main", "master", "dev", "develop"):
        # Ignore main development branches
        return

    # Check if this is a release branch
    match = RELEASE_BRANCH_PATTERN.match(branch)
    if not match:
        # Non-release branches do not trigger version checks or bumps
        return

    branch_version_str = match.group(1)
    parsed_branch = parse_version(branch_version_str)
    if not parsed_branch:
        print(f"Error: Invalid branch version format: {branch_version_str}")  # noqa: T201
        sys.exit(1)
    branch_ver, _ = parsed_branch

    pubspec_version_str, original_content = read_pubspec_version()
    if not pubspec_version_str:
        print("Error: Could not parse version from pubspec.yaml")  # noqa: T201
        sys.exit(1)

    parsed_pubspec = parse_version(pubspec_version_str)
    if not parsed_pubspec:
        print(f"Error: Invalid pubspec version format: {pubspec_version_str}")  # noqa: T201
        sys.exit(1)
    pubspec_ver, _ = parsed_pubspec

    # 1. Enforce branch version is greater than or equal to pubspec version
    if branch_ver < pubspec_ver:
        err_msg = (
            f"Error: Branch version ({branch_version_str}) cannot be less than "
            f"the current app version ({pubspec_version_str})."
        )
        print(err_msg)  # noqa: T201
        sys.exit(1)

    # 2. Auto-bump version in pubspec if the branch version is greater
    if branch_ver > pubspec_ver:
        # Reset build number to 1 for the new version
        new_version_str = f"{branch_version_str}+1"
        git_path = shutil.which("git") or "git"
        if pre_commit:
            print(f"Auto-bumping version in pubspec.yaml to {new_version_str}...")  # noqa: T201
            write_pubspec_version(original_content, new_version_str)
            subprocess.run(  # noqa: S603
                [git_path, "add", str(PUBSPEC_PATH)],
                check=True,
            )
        elif post_checkout:
            msg = f"Auto-bumping pubspec to {new_version_str}..."
            print(msg)  # noqa: T201
            write_pubspec_version(original_content, new_version_str)
        else:
            # Standard run, just update
            write_pubspec_version(original_content, new_version_str)


if __name__ == "__main__":
    main()
