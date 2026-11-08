#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_logo.py
# -----------------------------------------------------------------------------
# PHASE 7 — single source of truth for ar0x raster artwork.
#
# Authority order (ADR-015 / ADR-022):
#   1. config/versions.env            -> exact 8-colour hex palette
#   2. assets/logo/ar0x-logo.svg      -> exact vector geometry (512x512 viewBox)
#   3. THIS MODULE                   -> deterministic raster implementation of
#                                       that geometry, used by BOTH generators:
#                                       tools/gen-theme-assets.sh   (boot art)
#                                       tools/gen-branding-assets.sh (logo PNGs)
#
# WHY A MODULE: Phase 4 shipped a bitmap-font placeholder wordmark. Phase 7
# replaces it with the official logomark. If the two generators each carried
# their own copy of the geometry, the boot splash and the standalone logo would
# silently drift apart. One module, two consumers, one checksum.
#
# The raster is a deliberate APPROXIMATION of the SVG: distance-to-segment gives
# round joins where the SVG polygon has mitre joins. The SVG remains the master
# for any vector/print use; PNGs exist only where a raster is required (GRUB
# gfxmenu, Plymouth script plugin, syslinux vesamenu, icon raster fallback).
#
# No third-party modules. Pure stdlib: os, re, struct, zlib.
# -----------------------------------------------------------------------------

from __future__ import annotations

import os
import re
import struct
import zlib

# --- Palette -----------------------------------------------------------------
PALETTE_KEYS = ("VOID", "SURFACE", "CYAN", "MAGENTA", "LIME", "TEXT", "MUTED", "ALERT")

# Fallback values; load_palette() ALWAYS asserts these equal versions.env.
_FALLBACK_HEX = {
    "VOID": "#07090F",
    "SURFACE": "#11151F",
    "CYAN": "#00E5FF",
    "MAGENTA": "#FF2E88",
    "LIME": "#A8FF60",
    "TEXT": "#D7E0EE",
    "MUTED": "#6B7891",
    "ALERT": "#FF5C57",
}

GRID = (0x1A, 0x23, 0x30)  # derived grid line colour, not a brand pin


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    """'#RRGGBB' -> (r, g, b). Rejects anything else (no 'fff' shorthand)."""
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        raise ValueError("not a 6-digit hex colour: %r" % value)
    return (int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16))


def load_palette(root: str) -> tuple[dict[str, tuple[int, int, int]], dict[str, str]]:
    """Read config/versions.env, assert all 8 pins exist and match the brand.

    Returns (rgb_map, hex_map). This is the ADR-015 parity gate for ALL Phase 7
    raster producers: a palette edit in versions.env cannot be ignored here.
    """
    path = os.path.join(root, "config", "versions.env")
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    pattern = r'^AR0X_(%s)="(#[0-9A-Fa-f]{6})"' % "|".join(PALETTE_KEYS)
    pins = dict(re.findall(pattern, text, flags=re.M))
    missing = [k for k in PALETTE_KEYS if k not in pins]
    if missing:
        raise AssertionError("versions.env missing palette pins: %s" % ", ".join(missing))
    for key, value in pins.items():
        if value.upper() != _FALLBACK_HEX[key].upper():
            raise AssertionError(
                "ADR-015 palette drift: AR0X_%s=%s but brand module pins %s. "
                "Update BOTH config/versions.env and tools/lib/ar0x_logo.py, "
                "plus docs/BRANDING_GUIDE.md and all SVG masters."
                % (key, value, _FALLBACK_HEX[key])
            )
    return ({k: hex_to_rgb(v) for k, v in pins.items()}, pins)


# --- SVG geometry, in the 512 x 512 viewBox ----------------------------------
# These constants MUST stay in lockstep with assets/logo/ar0x-logo.svg.
# tools/configure-branding.sh --check parses the SVG and verifies the numbers.
OCTAGON = (
    (136, 24), (376, 24), (488, 136), (488, 376),
    (376, 488), (136, 488), (24, 376), (24, 136),
)
CHEVRON = ((150, 170), (238, 256), (150, 342))
UNDERSCORE = ((272, 342), (362, 342))
NODE_RECT = (322, 170, 48, 48)       # x, y, width, height
OCTAGON_STROKE = 28
GLYPH_STROKE = 40
VIEWBOX = "0 0 512 512"
WORDMARK_VIEWBOX = "0 0 1024 256"


def _dist_to_segment(px, py, ax, ay, bx, by) -> float:
    """Shortest distance from point (px,py) to segment AB."""
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq == 0:
        return ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
    t = ((px - ax) * dx + (py - ay) * dy) / length_sq
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    cx, cy = ax + t * dx, ay + t * dy
    return ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5


def mark_color(u: float, v: float, rgb: dict[str, tuple[int, int, int]]):
    """Brand colour of the logomark at 512-space (u,v), or None (transparent).

    Layer order matches the SVG source: frame -> chevron -> underscore -> node.
    """
    for i, a in enumerate(OCTAGON):
        b = OCTAGON[(i + 1) % len(OCTAGON)]
        if _dist_to_segment(u, v, a[0], a[1], b[0], b[1]) <= OCTAGON_STROKE / 2:
            return rgb["CYAN"]
    for a, b in zip(CHEVRON, CHEVRON[1:]):
        if _dist_to_segment(u, v, a[0], a[1], b[0], b[1]) <= GLYPH_STROKE / 2:
            return rgb["CYAN"]
    a, b = UNDERSCORE
    if _dist_to_segment(u, v, a[0], a[1], b[0], b[1]) <= GLYPH_STROKE / 2:
        return rgb["MAGENTA"]
    x, y, w, h = NODE_RECT
    if x <= u <= x + w and y <= v <= y + h:
        return rgb["LIME"]
    return None


def logo_overlay(box_x: int, box_y: int, box_w: int,
                 rgb: dict[str, tuple[int, int, int]]):
    """Return fn(x, y) -> RGB|None compositing the mark into a box_w x box_w box.

    Coordinates are ABSOLUTE canvas pixels. box_w is the rendered mark size in
    pixels; the 512-unit viewBox is scaled by box_w/512. Out-of-box hits are
    None so callers can composite over their own backdrop.
    """
    scale = box_w / 512.0

    def fn(x: int, y: int):
        u = (x - box_x + 0.5) / scale
        v = (y - box_y + 0.5) / scale
        if u < 0 or v < 0 or u > 512 or v > 512:
            return None
        return mark_color(u, v, rgb)

    return fn


# --- Small helpers shared by both generators ---------------------------------
def lerp(a, b, t: float):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def write_png(path: str, width: int, height: int, fn) -> int:
    """Write an 8-bit RGB PNG (filter 0, zlib level 9). fn(x,y) -> (r,g,b)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(fn(x, y))
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


# --- Tiny 5x7 bitmap font ----------------------------------------------------
# Used ONLY for short captions ("ar0x") in raster boot art. The SVG wordmark is
# authoritative and uses Inter; a bitmap font keeps the PNG generator free of
# font files (no ImageMagick, no freetype, no fc-cache) and byte-reproducible.
FONT = {
    "a": ["01110", "00001", "01111", "10001", "10001", "10011", "01101"],
    "r": ["00000", "00000", "10110", "11001", "10000", "10000", "10000"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
}


def glyph_masks(word: str, scale: int):
    """(set of (x,y) pixel blocks, total width, total height) for a caption."""
    pts = set()
    cursor = 0
    for ch in word:
        for ry, row in enumerate(FONT[ch]):
            for rx, bit in enumerate(row):
                if bit == "1":
                    pts.add((cursor + rx, ry))
        cursor += 6
    big = set()
    for gx, gy in pts:
        for dy in range(scale):
            for dx in range(scale):
                big.add((gx * scale + dx, gy * scale + dy))
    return big, cursor * scale, 7 * scale
