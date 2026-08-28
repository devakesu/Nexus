from pathlib import Path
from unittest.mock import patch

from PIL import Image

from scripts.generate_assets import generate_assets


def test_generate_assets_flow(tmp_path: Path) -> None:
    static_dir = tmp_path / "app" / "static"
    mobile_assets_dir = tmp_path / "mobile" / "assets"
    mobile_assets_dir.mkdir(parents=True)

    logo_file = mobile_assets_dir / "nexus.png"
    fg_file = mobile_assets_dir / "nexus_foreground.png"
    dummy_img = Image.new("RGBA", (100, 100), (255, 0, 0, 255))
    dummy_img.save(str(logo_file))
    dummy_img.save(str(fg_file))

    scripts_dir = tmp_path / "scripts"
    scripts_dir.mkdir(parents=True)
    script_target = scripts_dir / "generate_assets.py"

    with patch("scripts.generate_assets.__file__", str(script_target)):
        generate_assets()

        assert (static_dir / "logo.png").exists()
        assert (static_dir / "favicon.ico").exists()
        assert (static_dir / "og-image.png").exists()
        assert (static_dir / "site.webmanifest").exists()


def test_generate_assets_main_invocation() -> None:
    dummy_img = Image.new("RGBA", (100, 100), (255, 0, 0, 255))
    with (
        patch("PIL.Image.open", return_value=dummy_img),
        patch(
            "PIL.Image.Image.save",
        ),
        patch("builtins.open"),
    ):
        import runpy

        runpy.run_path("scripts/generate_assets.py", run_name="__main__")
