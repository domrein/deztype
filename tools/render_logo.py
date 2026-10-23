#!/usr/bin/env python3
"""Render the Deztype mark from the Deseret capital dee in Noto Sans Deseret.

The letter is the first sound of "Dez". Outlines are traced from the font
already shipped with the app, then rasterized for the window icon, the
in-app mark, the web favicon, the macOS icon, and the Windows icon.

Requires: fonttools, Pillow, rsvg-convert, png2icns.
"""

import shutil
import subprocess
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DESERET = ROOT / "src/fonts/NotoSansDeseret-Regular.ttf"


def find_vera() -> Path:
    """Bitstream Vera ships inside the dvui dependency, which is the UI face."""
    roots = [ROOT / "zig-pkg", ROOT / ".zig-cache", Path.home() / ".cache/zig"]
    for base in roots:
        if not base.exists():
            continue
        hits = sorted(base.rglob("Vera.ttf"))
        if hits:
            return hits[0]
    raise SystemExit("Bitstream Vera Sans not found. Run zig build once so dvui is fetched.")


OUT = ROOT / "assets/logo"
MACOS = ROOT / "assets/macos"
WINDOWS = ROOT / "assets/windows"

# Pine ink on warm paper. The same pair is used by the in-app theme.
PINE = "#1E3F38"
PAPER = "#F4F0E6"
INK = "#1C2428"

MARK = 256
# Glyph occupies this fraction of the mark, centered. Large enough that the
# two counters of capital dee stay open at 16px.
GLYPH_SCALE = 0.70


def trace_transformed(font_path: Path, codepoint: int, box: float, ox: float, oy: float) -> str:
    font = TTFont(font_path)
    glyphset = font.getGlyphSet()
    name = font.getBestCmap()[codepoint]
    glyph = glyphset[name]
    bounds_pen = BoundsPen(glyphset)
    glyph.draw(bounds_pen)
    xmin, ymin, xmax, ymax = bounds_pen.bounds
    scale = (box * GLYPH_SCALE) / max(xmax - xmin, ymax - ymin)
    cx = (xmin + xmax) / 2
    cy = (ymin + ymax) / 2
    tx = ox + box / 2 - scale * cx
    ty = oy + box / 2 + scale * cy
    out = SVGPathPen(glyphset)
    pen = TransformPen(out, Transform(scale, 0, 0, -scale, tx, ty))
    glyph.draw(pen)
    return out.getCommands()


def trace_text(font_path: Path, text: str, size: float, x: float, baseline: float) -> tuple[str, float]:
    font = TTFont(font_path)
    glyphset = font.getGlyphSet()
    cmap = font.getBestCmap()
    upem = font["head"].unitsPerEm
    scale = size / upem
    cursor = x
    parts: list[str] = []
    for ch in text:
        name = cmap[ord(ch)]
        glyph = glyphset[name]
        out = SVGPathPen(glyphset)
        pen = TransformPen(out, Transform(scale, 0, 0, -scale, cursor, baseline))
        glyph.draw(pen)
        parts.append(out.getCommands())
        cursor += glyph.width * scale
    return "".join(parts), cursor


def write_mark_svg(path: Path) -> None:
    dee = trace_transformed(DESERET, 0x10414, MARK, 0, 0)
    radius = round(MARK * 0.22)
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {MARK} {MARK}" width="{MARK}" height="{MARK}">
  <!-- Deztype mark. The letter is Noto Sans Deseret capital dee (U+10414), the first sound of Dez. -->
  <rect width="{MARK}" height="{MARK}" rx="{radius}" fill="{PINE}"/>
  <path fill="{PAPER}" d="{dee}"/>
</svg>
""",
        encoding="utf-8",
    )


def write_lockup_svg(path: Path) -> None:
    mark = MARK
    gap = 36
    text_size = 132
    # Vera cap height is about 0.73 of the em. Center that band on the mark.
    cap_ratio = 0.728
    baseline = (mark + text_size * cap_ratio) / 2
    vera = find_vera()
    dez, after_dez = trace_text(vera, "Dez", text_size, mark + gap, baseline)
    type_path, end = trace_text(vera, "type", text_size, after_dez, baseline)
    width = round(end + 8)
    radius = round(mark * 0.22)
    dee = trace_transformed(DESERET, 0x10414, mark, 0, 0)
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {mark}" width="{width}" height="{mark}">
  <!-- Deztype lockup. Mark plus the word set in Bitstream Vera Sans, the interface face. -->
  <rect width="{mark}" height="{mark}" rx="{radius}" fill="{PINE}"/>
  <path fill="{PAPER}" d="{dee}"/>
  <path fill="{INK}" d="{dez}"/>
  <path fill="{PINE}" d="{type_path}"/>
</svg>
""",
        encoding="utf-8",
    )


def rasterize(svg: Path, png: Path, size: int) -> None:
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
        check=True,
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    MACOS.mkdir(parents=True, exist_ok=True)
    WINDOWS.mkdir(parents=True, exist_ok=True)

    mark_svg = OUT / "mark.svg"
    lockup_svg = OUT / "lockup.svg"
    write_mark_svg(mark_svg)
    write_lockup_svg(lockup_svg)

    sizes = [16, 32, 48, 64, 128, 256, 512, 1024]
    pngs: dict[int, Path] = {}
    for size in sizes:
        dest = OUT / f"mark-{size}.png"
        rasterize(mark_svg, dest, size)
        pngs[size] = dest

    # @embedFile cannot leave the Zig package root (src/), so the in-app
    # and window-icon bytes live next to the module that embeds them.
    embedded = ROOT / "src/logo"
    embedded.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(pngs[256], embedded / "mark-256.png")
    shutil.copyfile(pngs[128], embedded / "mark-128.png")

    # Favicon used by the web build. 32px is the size browsers request first.
    shutil.copyfile(pngs[32], ROOT / "web/favicon.png")

    lockup_png = OUT / "lockup.png"
    # Lockup is wider than it is tall. Rasterize to a fixed height.
    subprocess.run(
        ["rsvg-convert", "-h", "256", "-o", str(lockup_png), str(lockup_svg)],
        check=True,
    )

    Image.open(pngs[256]).save(
        WINDOWS / "deztype.ico",
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    icns_inputs = [pngs[s] for s in (16, 32, 64, 128, 256, 512, 1024)]
    subprocess.run(["png2icns", str(MACOS / "AppIcon.icns"), *map(str, icns_inputs)], check=True)

    # Contact sheet for visual checks. Not an app asset.
    sheet = Image.new("RGB", (16 + 32 + 48 + 64 + 128 + 40, 160), (243, 238, 230))
    x = 8
    for size in (16, 32, 48, 64, 128):
        im = Image.open(pngs[size]).convert("RGBA")
        y = 80 - size // 2
        sheet.paste(im, (x, y), im)
        x += size + 8
    sheet.save("/tmp/logo-sheet.png")
    print("wrote", mark_svg)
    print("wrote", lockup_svg)


if __name__ == "__main__":
    main()
