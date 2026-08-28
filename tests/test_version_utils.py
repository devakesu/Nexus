from pathlib import Path

from scripts.version_utils import (
    RELEASE_BRANCH_PATTERN,
    VERSION_PATTERN,
    extract_app_version,
    parse_version,
    read_pubspec_version,
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


def test_version_utils_edge_cases(tmp_path: Path):
    non_existent = tmp_path / "does_not_exist.yaml"
    assert read_pubspec_version(non_existent) == (None, "")
    assert extract_app_version(non_existent) is None

    no_version_line = tmp_path / "no_version.yaml"
    no_version_line.write_text("name: nexus\nauthor: team\n", encoding="utf-8")
    assert read_pubspec_version(no_version_line) == (
        None,
        "name: nexus\nauthor: team\n",
    )
    assert extract_app_version(no_version_line) is None

    invalid_version_line = tmp_path / "invalid_ver.yaml"
    invalid_version_line.write_text("version: 1.0-beta+5\n", encoding="utf-8")
    assert extract_app_version(invalid_version_line) == "1.0-beta"
