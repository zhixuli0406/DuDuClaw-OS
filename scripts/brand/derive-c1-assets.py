#!/usr/bin/env python3
"""Derive every in-tree DuDuClaw OS brand raster from the C1 masters.

    scripts/brand/derive-c1-assets.py            # (re)write all derived files
    scripts/brand/derive-c1-assets.py --check    # rebuild into a temp dir and
                                                 # diff against the tree

Masters (hand-placed, never written by this script) live in
appliance/branding/:

  duduclaw-os-mark.svg          C1 cat mark, `ink` layer #102B48 navy and
                                `accent` layer #CC8B2D amber (Codex C1 kit,
                                Dudu_Brand_C1_Web/svg/duduclaw-os-mark.svg)
  duduclaw-os-app-icon-1024.png the cat with the "OS" badge on a cream tile
                                (Codex C1 kit, app-icon 1024 px rep)
  duduclaw-os-app-icon.ico      Codex C1 kit app-icon.ico (16-256 px)
  duduclaw-os-app-icon.icns     Codex C1 kit app-icon.icns (not read here)

The mark PNGs below are rendered from the SVG, not copied from the kit's
icon-<N>.png: the kit's own spec puts the SVG within IoU >= 0.9975 of the
master per colour layer, and one vector source keeps the navy and cream
sets and every size geometrically identical. The kit's icon PNGs also carry
~12% padding for app-icon use; these are full-bleed (the SVG's ~2%).

Everything else below is DERIVED and must not be edited by hand:

  appliance/branding/duduclaw-os-mark-mono.svg       both layers currentColor
  appliance/branding/duduclaw-os-mark-reverse.svg    ink layer #F5F4F0 cream,
                                                     for dark backgrounds
  appliance/branding/png/duduclaw-os-mark-<N>.png            N = 16 ... 1024
  appliance/branding/png/duduclaw-os-mark-reverse-<N>.png    N = 32 ... 1024
  crates/duduclaw-shell/assets/branding/duduclaw-os-mark{,-reverse}-{32,512}.png
  crates/duduclaw-native-gui/assets/duduclaw-os-app-icon-256.png
  crates/duduclaw-native-gui/assets/duduclaw-os-mark-reverse-128.png
  meta-duduclaw/recipes-duduclaw/duduclaw-boot-splash/files/theme/*.png

Tools: Pillow plus an SVG rasterizer, `resvg` (preferred: the same usvg
renderer gpui uses; macOS `brew install resvg`) or `rsvg-convert` (Debian
librsvg2-bin) as a fallback. The 2026-10-16 committed set was written with
resvg 0.48.1 + Pillow 12.3.0 on macOS.

Output is deterministic for a given rasterizer + Pillow pair (no
timestamps are written into the PNGs), which is what makes --check usable;
--check against a tree written by the OTHER rasterizer reports every PNG as
stale (anti-aliasing differs), so regenerate with the same tool.
Snapshots under meta-duduclaw/recipes-duduclaw/*/files/*-src pick up the
crate copies on the next refresh-src.sh run; this script never touches them.
"""
import argparse
import filecmp
import math
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRANDING = os.path.join(ROOT, "appliance", "branding")

NAVY = "#102B48"
AMBER = "#CC8B2D"
CREAM = "#F5F4F0"
CREAM_RGB = (0xF5, 0xF4, 0xF0)
AMBER_RGB = (0xCC, 0x8B, 0x2D)
NAVY_RGB = (0x10, 0x2B, 0x48)
RULE_DARK_RGB = (0x24, 0x40, 0x5F)  # WEB-DESIGN-SPEC dark --rule

MARK_SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)
REVERSE_SIZES = (32, 64, 128, 256, 512, 1024)
SHELL_SIZES = (32, 512)

# Boot splash geometry (see the recipe's duduclaw.plymouth for placement).
SPLASH_MARK_PX = 168
THROBBER_PX = 32
THROBBER_FRAMES = 36
SUPERSAMPLE = 8


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def recolor_svg(master, ink, accent):
    if master.count(f'fill="{NAVY}"') != 1 or master.count(f'fill="{AMBER}"') != 1:
        sys.exit("derive-c1-assets: master SVG no longer has exactly one navy ink and one amber accent fill; refusing to guess")
    return master.replace(f'fill="{NAVY}"', f'fill="{ink}"').replace(f'fill="{AMBER}"', f'fill="{accent}"')


def rasterizer():
    for tool in ("resvg", "rsvg-convert"):
        if shutil.which(tool):
            return tool
    sys.exit("derive-c1-assets: neither resvg nor rsvg-convert found; see this script's docstring")


def rsvg(svg_path, size, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    tool = rasterizer()
    if tool == "resvg":
        cmd = ["resvg", "-w", str(size), "-h", str(size), svg_path, out_path]
    else:
        cmd = ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out_path, svg_path]
    subprocess.run(cmd, check=True)
    # Re-save through Pillow so every PNG this script writes goes through the
    # same encoder (each rasterizer writes its own ancillary chunks).
    Image.open(out_path).convert("RGBA").save(out_path, optimize=True)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def downsample(big, size):
    return big.resize((size, size) if isinstance(size, int) else size, Image.LANCZOS)


def throbber_frame(index):
    """A thin cream track with a 100-degree amber arc, rotated per frame."""
    s = THROBBER_PX * SUPERSAMPLE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    width = int(2.5 * SUPERSAMPLE)
    pad = int(3 * SUPERSAMPLE)
    box = (pad, pad, s - pad, s - pad)
    draw.ellipse(box, outline=CREAM_RGB + (46,), width=width)
    start = index * (360 / THROBBER_FRAMES) - 90
    draw.arc(box, start=start, end=start + 100, fill=AMBER_RGB + (255,), width=width)
    # Round caps on the arc ends.
    r = (s - 2 * pad) / 2 - width / 2
    cx = cy = s / 2
    for angle in (start, start + 100):
        x = cx + r * math.cos(math.radians(angle))
        y = cy + r * math.sin(math.radians(angle))
        draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=AMBER_RGB + (255,))
    return downsample(img, THROBBER_PX)


def lock_icon():
    """Cream padlock, 24x30 logical px, for two-step's password prompt."""
    w, h = 24 * SUPERSAMPLE, 30 * SUPERSAMPLE
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    stroke = int(3 * SUPERSAMPLE)
    draw.arc((5 * SUPERSAMPLE, 1 * SUPERSAMPLE, 19 * SUPERSAMPLE, 22 * SUPERSAMPLE), start=180, end=360, fill=CREAM_RGB + (255,), width=stroke)
    draw.line((5 * SUPERSAMPLE + stroke / 2, 11 * SUPERSAMPLE, 5 * SUPERSAMPLE + stroke / 2, 15 * SUPERSAMPLE), fill=CREAM_RGB + (255,), width=stroke)
    draw.line((19 * SUPERSAMPLE - stroke / 2, 11 * SUPERSAMPLE, 19 * SUPERSAMPLE - stroke / 2, 15 * SUPERSAMPLE), fill=CREAM_RGB + (255,), width=stroke)
    draw.rounded_rectangle((1 * SUPERSAMPLE, 13 * SUPERSAMPLE, 23 * SUPERSAMPLE, 29 * SUPERSAMPLE), radius=3 * SUPERSAMPLE, fill=CREAM_RGB + (255,))
    draw.ellipse((10 * SUPERSAMPLE, 18 * SUPERSAMPLE, 14 * SUPERSAMPLE, 22 * SUPERSAMPLE), fill=NAVY_RGB + (255,))
    return img.resize((24, 30), Image.LANCZOS)


def entry_box():
    """Password field: navy surface, dark-theme hairline, 8 px radius."""
    w, h = 320, 40
    big = Image.new("RGBA", (w * SUPERSAMPLE, h * SUPERSAMPLE), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1), radius=8 * SUPERSAMPLE,
        fill=NAVY_RGB + (255,), outline=RULE_DARK_RGB + (255,), width=SUPERSAMPLE)
    return big.resize((w, h), Image.LANCZOS)


def bullet():
    s = 10 * SUPERSAMPLE
    big = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse((0, 0, s - 1, s - 1), fill=CREAM_RGB + (255,))
    return big.resize((10, 10), Image.LANCZOS)


def derive(out_root):
    """Write every derived file under out_root (the repo root, or a temp dir)."""
    def out(*parts):
        return os.path.join(out_root, *parts)

    master = read(os.path.join(BRANDING, "duduclaw-os-mark.svg"))
    reverse = recolor_svg(master, CREAM, AMBER)
    mono = recolor_svg(master, "currentColor", "currentColor")
    write_text(out("appliance", "branding", "duduclaw-os-mark-reverse.svg"), reverse)
    write_text(out("appliance", "branding", "duduclaw-os-mark-mono.svg"), mono)

    with tempfile.TemporaryDirectory() as tmp:
        color_svg = os.path.join(tmp, "color.svg")
        reverse_svg = os.path.join(tmp, "reverse.svg")
        write_text(color_svg, master)
        write_text(reverse_svg, reverse)

        for n in MARK_SIZES:
            rsvg(color_svg, n, out("appliance", "branding", "png", f"duduclaw-os-mark-{n}.png"))
        for n in REVERSE_SIZES:
            rsvg(reverse_svg, n, out("appliance", "branding", "png", f"duduclaw-os-mark-reverse-{n}.png"))

        shell = ("crates", "duduclaw-shell", "assets", "branding")
        for n in SHELL_SIZES:
            copy(out("appliance", "branding", "png", f"duduclaw-os-mark-{n}.png"), out(*shell, f"duduclaw-os-mark-{n}.png"))
            copy(out("appliance", "branding", "png", f"duduclaw-os-mark-reverse-{n}.png"), out(*shell, f"duduclaw-os-mark-reverse-{n}.png"))

        theme = ("meta-duduclaw", "recipes-duduclaw", "duduclaw-boot-splash", "files", "theme")
        rsvg(reverse_svg, SPLASH_MARK_PX, out(*theme, "watermark.png"))

    copy(out("appliance", "branding", "png", "duduclaw-os-mark-reverse-128.png"),
         out("crates", "duduclaw-native-gui", "assets", "duduclaw-os-mark-reverse-128.png"))

    app_icon = Image.open(os.path.join(BRANDING, "duduclaw-os-app-icon-1024.png")).convert("RGBA")
    save(downsample(app_icon, 256), out("crates", "duduclaw-native-gui", "assets", "duduclaw-os-app-icon-256.png"))

    theme = ("meta-duduclaw", "recipes-duduclaw", "duduclaw-boot-splash", "files", "theme")
    for i in range(THROBBER_FRAMES):
        save(throbber_frame(i), out(*theme, f"throbber-{i + 1:04d}.png"))
    save(lock_icon(), out(*theme, "lock.png"))
    save(entry_box(), out(*theme, "entry.png"))
    save(bullet(), out(*theme, "bullet.png"))


def derived_files(root):
    """Every path derive() writes, relative to root."""
    files = [
        "appliance/branding/duduclaw-os-mark-reverse.svg",
        "appliance/branding/duduclaw-os-mark-mono.svg",
        "crates/duduclaw-native-gui/assets/duduclaw-os-app-icon-256.png",
        "crates/duduclaw-native-gui/assets/duduclaw-os-mark-reverse-128.png",
    ]
    files += [f"appliance/branding/png/duduclaw-os-mark-{n}.png" for n in MARK_SIZES]
    files += [f"appliance/branding/png/duduclaw-os-mark-reverse-{n}.png" for n in REVERSE_SIZES]
    for n in SHELL_SIZES:
        files += [f"crates/duduclaw-shell/assets/branding/duduclaw-os-mark-{n}.png",
                  f"crates/duduclaw-shell/assets/branding/duduclaw-os-mark-reverse-{n}.png"]
    theme = "meta-duduclaw/recipes-duduclaw/duduclaw-boot-splash/files/theme"
    files += [f"{theme}/watermark.png", f"{theme}/lock.png", f"{theme}/entry.png", f"{theme}/bullet.png"]
    files += [f"{theme}/throbber-{i + 1:04d}.png" for i in range(THROBBER_FRAMES)]
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify the tree matches a fresh derivation")
    args = parser.parse_args()

    rasterizer()

    if not args.check:
        derive(ROOT)
        print(f"derive-c1-assets: wrote {len(derived_files(ROOT))} files")
        return

    with tempfile.TemporaryDirectory() as tmp:
        derive(tmp)
        stale = [rel for rel in derived_files(ROOT)
                 if not os.path.exists(os.path.join(ROOT, rel))
                 or not filecmp.cmp(os.path.join(ROOT, rel), os.path.join(tmp, rel), shallow=False)]
    if stale:
        print("derive-c1-assets: --check FAILED, stale or missing:", *stale, sep="\n  ", file=sys.stderr)
        sys.exit(1)
    print(f"derive-c1-assets: --check OK ({len(derived_files(ROOT))} files)")


if __name__ == "__main__":
    main()
