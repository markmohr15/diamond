#!/usr/bin/env python3
"""Generate Diamond's mark as SVG, at every size the platforms want.

The mark is two shapes (Claude Design, Turn 03): a chalk baseline diamond and
a clay home plate at its near vertex. Ratios are read out of the design's CSS
rather than eyeballed — see RATIOS below for the source numbers.

SVG is the committed source; PNGs are rendered from it. Nothing here is drawn
by hand twice.
"""
import math, subprocess, sys, os

OUT = "app/assets/brand"

# 1A / 2A, already in brand_baseline.dart.
GRASS, CHALK, CLAY = "#2E5E3E", "#B4643C", "#B4643C"
CHALK = "#F4F2EB"
INK = "#16211C"
GRASS_LIT, CLAY_LIT = "#5FA97A", "#D07E4E"
HAIRLINE = "#2A3A32"

# Icon ratios, from the 208px reference panel: border-radius 47, diamond
# square 83 with an 8px border, plate 21 at top 152.
#
# The plate's `left:93` in that panel puts its center at 103.5 against an icon
# center of 104 — a half-pixel of rounding, since the 120/76/40px panels all
# center it exactly. Centered here.
ICON = dict(square=83/208, border=8/208, plate=21/208, plate_top=152/208)

# Splash ratios, from the 104px unenclosed lockup: diamond 44 with a 5px
# border, plate 11 at top 78. Larger relative to its box than the icon's,
# because there is no rounded container padding it in.
SPLASH = dict(square=44/104, border=5/104, plate=11/104, plate_top=78/104)


def mark(size, r, line, fill, bg=None, hairline=None, radius=None, scale=1.0):
    """One mark. `scale` shrinks the art inside the canvas (Android's adaptive
    safe zone shows only the middle ~66% of the layer)."""
    c = size / 2
    s = r["square"] * size * scale
    b = r["border"] * size * scale
    # A square rotated 45 degrees is a diamond whose half-diagonal is
    # side * sqrt(2) / 2. Computed rather than expressed as a transform: the
    # renderers here disagree about transforms and never about polygons.
    out = s * math.sqrt(2) / 2
    inn = (s - 2 * b) * math.sqrt(2) / 2

    def diamond(a):
        return " ".join(f"{x:.3f},{y:.3f}" for x, y in
                        [(c - a, c), (c, c - a), (c + a, c), (c, c + a)])

    p = r["plate"] * size * scale
    # Keep the plate's offset from center proportional when scaling.
    ptop = c + (r["plate_top"] * size - size / 2) * scale
    left, right = c - p / 2, c + p / 2
    shoulder = ptop + 0.45 * p
    plate = " ".join(f"{x:.3f},{y:.3f}" for x, y in
                     [(left, ptop), (right, ptop), (right, shoulder),
                      (c, ptop + p), (left, shoulder)])

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
             f'height="{size}" viewBox="0 0 {size} {size}">']
    if bg:
        rx = f' rx="{radius}"' if radius else ""
        parts.append(f'<rect width="{size}" height="{size}"{rx} fill="{bg}"/>')
    if hairline:
        parts.append(f'<rect x="0.5" y="0.5" width="{size-1}" '
                     f'height="{size-1}" rx="{radius or 0}" fill="none" '
                     f'stroke="{hairline}" stroke-width="1"/>')
    # The outline is two filled polygons rather than a stroke: a stroked
    # rotated square miters its corners outward, which fattens the vertices
    # exactly where the plate meets them.
    parts.append(f'<polygon points="{diamond(out)}" fill="{line}"/>')
    inner = bg if bg else "none"
    if bg:
        parts.append(f'<polygon points="{diamond(inn)}" fill="{inner}"/>')
    else:
        # No background to punch through, so cut the hole with even-odd.
        parts[-1] = (f'<path fill="{line}" fill-rule="evenodd" '
                     f'd="M{diamond(out).replace(" ", "L").replace(",", " ")}Z '
                     f'M{diamond(inn).replace(" ", "L").replace(",", " ")}Z"/>')
    parts.append(f'<polygon points="{plate}" fill="{fill}"/>')
    parts.append("</svg>")
    return "\n".join(parts)


def write(name, svg):
    path = os.path.join(OUT, name)
    open(path, "w").write(svg + "\n")
    return path


TARGETS = [
    # The launcher icon. Square and unrounded on purpose: iOS applies its own
    # squircle and Android its own mask, so rounding here would be masked
    # twice and read as a dark seam.
    ("icon.svg", mark(1024, ICON, CHALK, CLAY, bg=GRASS)),
    # Android adaptive: background and foreground are separate layers, and the
    # launcher shows only the middle of them.
    ("icon_foreground.svg", mark(1024, ICON, CHALK, CLAY, scale=0.667)),
    # The splash lockup, unenclosed, on transparency.
    ("mark_light.svg", mark(512, SPLASH, GRASS, CLAY)),
    ("mark_dark.svg", mark(512, SPLASH, GRASS_LIT, CLAY_LIT)),
]

# How each PNG has to be encoded, because the platforms disagree:
#
#   opaque      iOS rejects an app icon that carries an alpha channel at all.
#   transparent Android's adaptive foreground is nothing but alpha, and the
#               splash mark sits on a background the OS paints.
ENCODING = {
    "icon.svg": ("opaque", GRASS),
    "icon_foreground.svg": ("transparent", None),
    "mark_light.svg": ("transparent", None),
    "mark_dark.svg": ("transparent", None),
}


def render(svg_name):
    src = os.path.join(OUT, svg_name)
    dst = src[:-4] + ".png"
    kind, bg = ENCODING[svg_name]
    # -strip is what makes this reproducible: ImageMagick otherwise stamps
    # date:create/date:modify into every file, so a regeneration that changed
    # nothing would still show up as four modified binaries in the diff — and
    # a generator whose output always looks changed is one nobody re-runs.
    if kind == "opaque":
        cmd = ["magick", src, "-background", bg,
               "-alpha", "remove", "-alpha", "off", "-strip", "PNG24:" + dst]
    else:
        cmd = ["magick", "-background", "none", src, "-strip", "PNG32:" + dst]
    subprocess.run(cmd, check=True)
    return dst


for name, svg in TARGETS:
    print("wrote", write(name, svg))
    print("wrote", render(name))
