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


LOCAL_PROPERTIES_PATH = Path("mobile/android/local.properties")


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
    update_local_properties(new_version_str)
    return updated


def update_local_properties(new_version_str: str) -> None:
    if not LOCAL_PROPERTIES_PATH.exists():
        return

    # Parse build name (versionName) and build number (versionCode)
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


def main() -> None:  # noqa: C901
    # Detect running mode
    pre_commit = "--pre-commit" in sys.argv
    post_checkout = "--post-checkout" in sys.argv

    pubspec_version_str, original_content = read_pubspec_version()
    if not pubspec_version_str:
        print("Error: Could not parse version from pubspec.yaml")  # noqa: T201
        sys.exit(1)

    effective_version = pubspec_version_str

    branch = get_current_branch()
    if branch and branch not in ("HEAD", "main", "master", "dev", "develop"):
        match = RELEASE_BRANCH_PATTERN.match(branch)
        if match:
            branch_version_str = match.group(1)
            parsed_branch = parse_version(branch_version_str)
            parsed_pubspec = parse_version(pubspec_version_str)

            if parsed_branch and parsed_pubspec:
                branch_ver, _ = parsed_branch
                pubspec_ver, _ = parsed_pubspec

                if branch_ver < pubspec_ver:
                    err_msg = (
                        f"Error: Branch version ({branch_version_str}) cannot be "
                        f"less than current app version ({pubspec_version_str})."
                    )
                    print(err_msg)  # noqa: T201
                    sys.exit(1)

                if branch_ver > pubspec_ver:
                    new_version_str = f"{branch_version_str}+1"
                    effective_version = new_version_str
                    git_path = shutil.which("git") or "git"
                    if pre_commit:
                        msg = (
                            "Auto-bumping version in pubspec.yaml to "
                            f"{new_version_str}..."
                        )
                        print(msg)  # noqa: T201
                        write_pubspec_version(original_content, new_version_str)
                        cmd = [
                            git_path,
                            "add",
                            str(PUBSPEC_PATH),
                            str(LOCAL_PROPERTIES_PATH),
                        ]
                        subprocess.run(cmd, check=True)  # noqa: S603
                    elif post_checkout:
                        msg = f"Auto-bumping pubspec to {new_version_str}..."
                        print(msg)  # noqa: T201
                        write_pubspec_version(original_content, new_version_str)
                    else:
                        write_pubspec_version(original_content, new_version_str)

    # Always ensure local.properties matches the final effective pubspec.yaml version
    update_local_properties(effective_version)


if __name__ == "__main__":
    main()
