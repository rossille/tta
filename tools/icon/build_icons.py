#!/usr/bin/env python3
"""Generate platform icon files from a single 1024x1024 master PNG.

Outputs (at project root):
  - icon.png   1024x1024 PNG, used by Godot as the project/window icon
  - icon.icns  macOS bundle icon (via iconutil)
  - icon.ico   Windows multi-resolution icon (via Pillow)

Re-run this script after editing tools/icon/icon.html and re-screenshotting
to tools/icon/icon-master.png (open the HTML at 1024x1024, take a viewport
screenshot, save as icon-master.png).
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLS_DIR = REPO_ROOT / "tools" / "icon"
MASTER = TOOLS_DIR / "icon-master.png"

# Output files (at repo root)
ICON_PNG = REPO_ROOT / "icon.png"
ICON_ICNS = REPO_ROOT / "icon.icns"
ICON_ICO = REPO_ROOT / "icon.ico"

# iconutil expects this naming convention inside a .iconset folder
ICNS_SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

# Windows .ico — embed multiple sizes; Windows picks the right one at display time
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"Master icon not found: {MASTER}")

    master = Image.open(MASTER).convert("RGBA")
    if master.size != (1024, 1024):
        raise SystemExit(f"Master must be 1024x1024, got {master.size}")

    # 1) Project icon (Godot)
    shutil.copy(MASTER, ICON_PNG)
    print(f"  {ICON_PNG.name}  ({master.size[0]}x{master.size[1]})")

    # 2) macOS .icns via iconutil
    iconset_dir = TOOLS_DIR / "icon.iconset"
    if iconset_dir.exists():
        shutil.rmtree(iconset_dir)
    iconset_dir.mkdir()
    for size, name in ICNS_SIZES:
        img = master.resize((size, size), Image.LANCZOS)
        img.save(iconset_dir / name, "PNG", optimize=True)
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset_dir), "-o", str(ICON_ICNS)],
        check=True,
    )
    shutil.rmtree(iconset_dir)
    print(f"  {ICON_ICNS.name}  ({ICON_ICNS.stat().st_size // 1024} KB, {len(ICNS_SIZES)} sizes)")

    # 3) Windows .ico — Pillow handles multi-resolution natively
    sizes = [(s, s) for s in ICO_SIZES]
    master.save(ICON_ICO, format="ICO", sizes=sizes)
    print(f"  {ICON_ICO.name}   ({ICON_ICO.stat().st_size // 1024} KB, {len(sizes)} sizes)")


if __name__ == "__main__":
    main()
