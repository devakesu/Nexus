from pathlib import Path
from scripts.version_utils import (
    VERSION_PATTERN,
    RELEASE_BRANCH_PATTERN,
    parse_version,
    read_pubspec_version,
    extract_app_version,
)


def test_version_pattern_matches_valid_versions():
    assert VERSION_PATTERN.match("1.0.0")
    assert VERSION_PATTERN.match("1.0.8+1")
    assert VERSION_PATTERN.match("2.14.3+105")
    assert not VERSION_PATTERN.match("1.0")
    assert not VERSION_PATTERN.match("v1.0.0")
    assert not VERSION_PATTERN.match("invalid")


def test_release_branch_pattern_matches_branches():
    m1 = RELEASE_BRANCH_PATTERN.match("release/1.0.8")
    assert m1 and m1.group(1) == "1.0.8"

    m2 = RELEASE_BRANCH_PATTERN.match("v1.2.3")
    assert m2 and m2.group(1) == "1.2.3"

    m3 = RELEASE_BRANCH_PATTERN.match("2.0.0")
    assert m3 and m3.group(1) == "2.0.0"

    assert not RELEASE_BRANCH_PATTERN.match("feature/login")
    assert not RELEASE_BRANCH_PATTERN.match("main")


def test_parse_version():
    assert parse_version("1.2.3") == ((1, 2, 3), 1)
    assert parse_version("1.2.3+45") == ((1, 2, 3), 45)
    assert parse_version("invalid") is None


def test_read_pubspec_version_and_extract(tmp_path: Path):
    pubspec = tmp_path / "pubspec.yaml"
    pubspec.write_text("name: nexus\nversion: 1.0.8+1\n", encoding="utf-8")

    version_str, content = read_pubspec_version(pubspec)
    assert version_str == "1.0.8+1"
    assert "name: nexus" in content

    base_version = extract_app_version(pubspec)
    assert base_version == "1.0.8"
