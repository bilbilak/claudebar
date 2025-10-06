#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Regenerate the per-size ClaudeBar app icons used by the Linux panel
# plugins (MATE, XFCE, Budgie, LXQt). The KDE Plasmoid bundles its own
# copy inside the .plasmoid package and is not touched here.
#
# Source:  .github/assets/icon.png  (512x512, RGBA)
# Targets: apps/linux/common/icons/<size>x<size>/claudebar.png
#
# Each DE's build glob-installs the resulting tree into
# $PREFIX/share/icons/hicolor/<size>x<size>/apps/ so GTK/Qt icon lookup
# resolves `Icon=claudebar` at every panel size without runtime scaling.
#
# Run from the repo root:
#
#     nix-shell -p python3Packages.pillow --run 'python3 scripts/regenerate-linux-icons.py'
#
# or, on a host with Pillow already installed:
#
#     python3 scripts/regenerate-linux-icons.py
#
# The generated PNGs are committed to the repo so end-user builds do not
# require Pillow.

import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.stderr.write(
        "error: Pillow is required. Install via pip or run under "
        "`nix-shell -p python3Packages.pillow`.\n"
    )
    sys.exit(1)

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / ".github" / "assets" / "icon.png"
OUT_DIR = REPO_ROOT / "apps" / "linux" / "common" / "icons"

# Sizes the freedesktop icon spec recommends for application icons.
# Panel-applet hosts query 22/24/32/48 most often; 16 covers menus,
# 64/128/256/512 cover the About dialog and high-DPI scaling.
SIZES = [16, 22, 24, 32, 48, 64, 128, 256, 512]


def main() -> int:
    if not SOURCE.is_file():
        sys.stderr.write(f"error: source icon not found at {SOURCE}\n")
        return 1

    src = Image.open(SOURCE).convert("RGBA")
    if src.size[0] != src.size[1]:
        sys.stderr.write(
            f"error: source must be square, got {src.size[0]}x{src.size[1]}\n"
        )
        return 1

    for size in SIZES:
        target_dir = OUT_DIR / f"{size}x{size}"
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / "claudebar.png"
        # LANCZOS gives the best downscale quality; for the native size we
        # just copy pixels through to avoid the resampler entirely.
        if size == src.size[0]:
            resized = src.copy()
        else:
            resized = src.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(target, format="PNG", optimize=True)
        print(f"wrote {target.relative_to(REPO_ROOT)} ({size}x{size})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
