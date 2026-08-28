import importlib.util
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_spec = importlib.util.spec_from_file_location(
    "sync_version", "scripts/sync-version.py",
)
assert _spec and _spec.loader
sync_ver = importlib.util.module_from_spec(_spec)
sys.modules["scripts.sync_version"] = sync_ver
_spec.loader.exec_module(sync_ver)


def test_get_current_branch_success() -> None:
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(stdout="release/1.0.9\n")
        branch = sync_ver.get_current_branch()
        assert branch == "release/1.0.9"


def test_get_current_branch_subprocess_error() -> None:
    with patch("subprocess.run", side_effect=subprocess.SubprocessError("git error")):
        branch = sync_ver.get_current_branch()
        assert branch is None


def test_update_local_properties_non_existent(tmp_path: Path) -> None:
    non_existent = tmp_path / "local.properties"
    with patch.object(sync_ver, "LOCAL_PROPERTIES_PATH", non_existent):
        sync_ver.update_local_properties("1.0.9+2")  # Should not raise


def test_update_local_properties_invalid_version_pattern(tmp_path: Path) -> None:
    loc_file = tmp_path / "local.properties"
    loc_file.write_text("flutter.versionName=1.0.0\n")
    with patch.object(sync_ver, "LOCAL_PROPERTIES_PATH", loc_file):
        sync_ver.update_local_properties("invalid-version")
        assert "flutter.versionName=1.0.0" in loc_file.read_text()


def test_update_local_properties_existing_and_missing_keys(tmp_path: Path) -> None:
    loc_file = tmp_path / "local.properties"
    loc_file.write_text("sdk.dir=/path/to/sdk\nflutter.versionName=1.0.0\n")
    with patch.object(sync_ver, "LOCAL_PROPERTIES_PATH", loc_file):
        sync_ver.update_local_properties("1.2.3")
        content = loc_file.read_text()
        assert "flutter.versionName=1.2.3" in content
        assert "flutter.versionCode=1" in content

    # Test update with build number
    with patch.object(sync_ver, "LOCAL_PROPERTIES_PATH", loc_file):
        sync_ver.update_local_properties("1.2.3+4")
        content = loc_file.read_text()
        assert "flutter.versionName=1.2.3" in content
        assert "flutter.versionCode=4" in content


def test_write_pubspec_version(tmp_path: Path) -> None:
    pubspec = tmp_path / "pubspec.yaml"
    pubspec.write_text("name: nexus\nversion: 1.0.0+1\nenvironment:\n  sdk: ^3.0.0\n")
    loc_file = tmp_path / "local.properties"
    loc_file.write_text("flutter.versionName=1.0.0\n")

    with (
        patch.object(sync_ver, "PUBSPEC_PATH", pubspec),
        patch.object(
            sync_ver,
            "LOCAL_PROPERTIES_PATH",
            loc_file,
        ),
    ):
        updated = sync_ver.write_pubspec_version(pubspec.read_text(), "1.0.1+2")
        assert updated is True
        assert "version: 1.0.1+2" in pubspec.read_text()


def test_resolve_branch_bump_invalid_versions() -> None:
    res = sync_ver._resolve_branch_bump("invalid", "invalid", "", False, False)
    assert res == "invalid"


def test_resolve_branch_bump_less_than_pubspec() -> None:
    with pytest.raises(SystemExit) as exc:
        sync_ver._resolve_branch_bump("1.0.0", "1.1.0+1", "", False, False)
    assert exc.value.code == 1


def test_resolve_branch_bump_equal_version() -> None:
    res = sync_ver._resolve_branch_bump("1.1.0", "1.1.0+1", "", False, False)
    assert res == "1.1.0+1"


def test_resolve_branch_bump_greater_than_pubspec_modes(tmp_path: Path) -> None:
    pubspec = tmp_path / "pubspec.yaml"
    pubspec.write_text("version: 1.0.0+1\n")
    loc_file = tmp_path / "local.properties"
    loc_file.write_text("")

    with (
        patch.object(sync_ver, "PUBSPEC_PATH", pubspec),
        patch.object(
            sync_ver,
            "LOCAL_PROPERTIES_PATH",
            loc_file,
        ),
        patch("subprocess.run") as mock_subproc,
    ):
        # Pre-commit mode
        res_pre = sync_ver._resolve_branch_bump(
            "1.1.0",
            "1.0.0+1",
            pubspec.read_text(),
            pre_commit=True,
            post_checkout=False,
        )
        assert res_pre == "1.1.0+1"
        assert mock_subproc.call_count == 1

        # Post-checkout mode
        res_post = sync_ver._resolve_branch_bump(
            "1.2.0",
            "1.1.0+1",
            pubspec.read_text(),
            pre_commit=False,
            post_checkout=True,
        )
        assert res_post == "1.2.0+1"

        # Default mode
        res_def = sync_ver._resolve_branch_bump(
            "1.3.0",
            "1.2.0+1",
            pubspec.read_text(),
            pre_commit=False,
            post_checkout=False,
        )
        assert res_def == "1.3.0+1"


def test_sync_version_main_missing_pubspec() -> None:
    with (
        patch("scripts.sync_version.read_pubspec_version", return_value=(None, "")),
        pytest.raises(SystemExit) as exc,
    ):
        sync_ver.main()
    assert exc.value.code == 1


def test_sync_version_main_branches() -> None:
    with (
        patch(
            "scripts.sync_version.read_pubspec_version",
            return_value=("1.0.8+1", "version: 1.0.8+1\n"),
        ),
        patch("scripts.sync_version.get_current_branch", return_value="main"),
        patch(
            "scripts.sync_version.update_local_properties",
        ) as mock_update,
    ):
        sync_ver.main()
        mock_update.assert_called_once_with("1.0.8+1")

    # Release branch triggers resolution
    with (
        patch(
            "scripts.sync_version.read_pubspec_version",
            return_value=("1.0.8+1", "version: 1.0.8+1\n"),
        ),
        patch("scripts.sync_version.get_current_branch", return_value="release/1.0.9"),
        patch(
            "scripts.sync_version._resolve_branch_bump",
            return_value="1.0.9+1",
        ) as mock_resolve,
        patch(
            "scripts.sync_version.update_local_properties",
        ) as mock_update,
    ):
        sync_ver.main()
        assert mock_resolve.call_count == 1
        mock_update.assert_called_once_with("1.0.9+1")


def test_sync_version_main_entrypoint() -> None:
    with (
        patch(
            "scripts.sync_version.read_pubspec_version",
            return_value=("1.0.8+1", "version: 1.0.8+1\n"),
        ),
        patch("scripts.sync_version.get_current_branch", return_value="main"),
        patch(
            "scripts.sync_version.update_local_properties",
        ),
        patch.object(sys, "argv", ["sync-version.py"]),
    ):
        import runpy

        runpy.run_path("scripts/sync-version.py", run_name="__main__")
