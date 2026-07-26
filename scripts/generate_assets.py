"""Static Web Asset Generation Script.

Generates favicons, app icons, OpenGraph images, and wide banners from mobile source assets
using Pillow (PIL).
"""

import os

from PIL import Image, ImageDraw


def generate_assets() -> None:
    """Generates favicons, PWA icons, and social card assets for the web app."""

    static_dir = os.path.join(os.path.dirname(__file__), "..", "app", "static")
    os.makedirs(static_dir, exist_ok=True)

    src_logo_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "mobile",
        "assets",
        "nexus.png",
    )
    src_fg_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "mobile",
        "assets",
        "nexus_foreground.png",
    )

    img_logo = Image.open(src_logo_path).convert("RGBA")
    img_fg = Image.open(src_fg_path).convert("RGBA")

    # 1. logo.png (512x512)
    logo_512 = img_logo.resize((512, 512), Image.Resampling.LANCZOS)
    logo_512.save(os.path.join(static_dir, "logo.png"), "PNG")

    # 2. logo-foreground.png (512x512)
    fg_512 = img_fg.resize((512, 512), Image.Resampling.LANCZOS)
    fg_512.save(os.path.join(static_dir, "logo-foreground.png"), "PNG")

    # 3. favicon-16x16.png
    fav_16 = img_logo.resize((16, 16), Image.Resampling.LANCZOS)
    fav_16.save(os.path.join(static_dir, "favicon-16x16.png"), "PNG")

    # 4. favicon-32x32.png
    fav_32 = img_logo.resize((32, 32), Image.Resampling.LANCZOS)
    fav_32.save(os.path.join(static_dir, "favicon-32x32.png"), "PNG")

    # 5. apple-touch-icon.png (180x180)
    fav_180 = img_logo.resize((180, 180), Image.Resampling.LANCZOS)
    fav_180.save(os.path.join(static_dir, "apple-touch-icon.png"), "PNG")

    # 6. android-chrome-192x192.png
    fav_192 = img_logo.resize((192, 192), Image.Resampling.LANCZOS)
    fav_192.save(os.path.join(static_dir, "android-chrome-192x192.png"), "PNG")

    # 7. android-chrome-512x512.png
    logo_512.save(os.path.join(static_dir, "android-chrome-512x512.png"), "PNG")

    # 8. favicon.ico containing 16x16, 32x32, 48x48
    fav_48 = img_logo.resize((48, 48), Image.Resampling.LANCZOS)
    fav_32.save(
        os.path.join(static_dir, "favicon.ico"),
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48)],
        append_images=[fav_16, fav_48],
    )

    # 9. og-image.png (1200x630) social share card
    og_img = Image.new("RGBA", (1200, 630), (8, 6, 22, 255))

    # Gradient background glow
    glow = Image.new("RGBA", (1200, 630), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse([200, 50, 1000, 580], fill=(139, 92, 246, 35))
    glow_draw.ellipse([400, 150, 800, 480], fill=(8, 145, 178, 45))
    og_img = Image.alpha_composite(og_img, glow)

    # Paste logo in center top
    logo_center = img_logo.resize((240, 240), Image.Resampling.LANCZOS)
    og_img.paste(logo_center, (480, 80), logo_center)

    # Save og-image.png
    og_img = og_img.convert("RGB")
    og_img.save(os.path.join(static_dir, "og-image.png"), "PNG")

    # 10. site.webmanifest
    manifest_content = """{
  "name": "Nexus - Sync Your Circle",
  "short_name": "Nexus",
  "icons": [
    {
      "src": "/static/android-chrome-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/static/android-chrome-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ],
  "theme_color": "#080616",
  "background_color": "#080616",
  "display": "standalone",
  "orientation": "portrait",
  "scope": "/",
  "start_url": "/"
}"""
    with open(os.path.join(static_dir, "site.webmanifest"), "w") as f:
        f.write(manifest_content)


if __name__ == "__main__":
    generate_assets()
