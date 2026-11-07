#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/gen-theme-assets.sh
# -----------------------------------------------------------------------------
# PHASE 4 — deterministically generate the ar0x boot artwork (PNG only).
#
# Why a generator instead of checked-in AI art: PNGs produced here are
# byte-for-byte reproducible, have no licensing ambiguity, are tiny (a few KB),
# and can be regenerated after a palette change without a design tool.
# Phase 7 replaces these PLACEHOLDER images with the final SVG-derived logo.
#
# Outputs (all absolute paths):
#   /home/user/ar0xOS/assets/grub-theme/ar0x/background.png   1024x768
#   /home/user/ar0xOS/assets/plymouth/ar0x/logo.png            320x80
#   /home/user/ar0xOS/assets/plymouth/ar0x/progress-{0..20}.png 400x6
#   /home/user/ar0xOS/assets/syslinux/splash.png               640x480
#
# Requires: python3 (pulled in by meson/namcap from Phase 2's host toolchain).
# No root, no network, no ImageMagick, no font files. Pure zlib PNG encoder.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_command python3

python3 - "$AR0X_SOURCE_ROOT" <<'PY'
import os
import sys
import zlib
import struct

ROOT = sys.argv[1]

# --- Palette: single source of truth is config/versions.env (ADR-015) --------
void    = (0x07, 0x09, 0x0F)
surface = (0x11, 0x15, 0x1F)
cyan    = (0x00, 0xE5, 0xFF)
magenta = (0xFF, 0x2E, 0x88)
text    = (0xD7, 0xE0, 0xEE)
muted   = (0x6B, 0x78, 0x91)
grid    = (0x1A, 0x23, 0x30)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def write_png(path, width, height, fn):
    """Write an RGB PNG. fn(x, y) -> (r, g, b)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    for y in range(height):
        raw.append(0)                      # filter type 0 (None) for this row
        for x in range(width):
            raw.extend(fn(x, y))
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


# --- Tiny 5x7 bitmap font: just the glyphs we need (ar0x) -------------------
FONT = {
    "a": ["01110", "00001", "01111", "10001", "10001", "10011", "01101"],
    "r": ["00000", "00000", "10110", "11001", "10000", "10000", "10000"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
}


def glyph_masks(word, scale):
    """Return a set of (x, y) pixel blocks for a word, scaled up."""
    pts = set()
    cursor = 0
    for ch in word:
        rows = FONT[ch]
        for ry, row in enumerate(rows):
            for rx, bit in enumerate(row):
                if bit == "1":
                    pts.add((cursor + rx, ry))
        cursor += 6                      # 5 columns + 1 space
    w = cursor * scale
    h = 7 * scale
    big = set()
    for gx, gy in pts:
        for dy in range(scale):
            for dx in range(scale):
                big.add((gx * scale + dx, gy * scale + dy))
    return big, w, h


def backdrop(width, height, scale_word, word_y, show_word=True):
    """Cyberpunk dark gradient + grid + accent rule + 'ar0x' wordmark."""
    mask, mw, mh = glyph_masks(scale_word[0], scale_word[1])
    ox = (width - mw) // 2
    oy = word_y
    accent_y = int(height * 0.78)
    accent_end = int(width * 0.34)

    def fn(x, y):
        base = lerp(void, surface, y / max(1, height - 1))
        # faint 64px engineering grid
        if x % 64 == 0 or y % 64 == 0:
            base = lerp(base, grid, 0.55)
        # horizontal cyan rule with a short magenta segment
        if accent_y <= y < accent_y + 3 and 0 < x < accent_end:
            return cyan if x < accent_end - 60 else magenta
        # wordmark: cyan with a 2px dark drop shadow
        if show_word and oy <= y < oy + mh and ox <= x < ox + mw:
            if (x - ox, y - oy) in mask:
                return cyan
            if (x - ox - 2, y - oy - 2) in mask:
                return lerp(void, cyan, 0.28)
        return base

    return fn


OUT = {
    "grub":     os.path.join(ROOT, "assets/grub-theme/ar0x"),
    "plymouth": os.path.join(ROOT, "assets/plymouth/ar0x"),
    "syslinux": os.path.join(ROOT, "assets/syslinux"),
}

# --- GRUB: 1024x768 ----------------------------------------------------------
write_png(os.path.join(OUT["grub"], "background.png"), 1024, 768,
          backdrop(1024, 768, ("ar0x", 14), 210))

# --- syslinux/vesamenu: 640x480 ---------------------------------------------
write_png(os.path.join(OUT["syslinux"], "splash.png"), 640, 480,
          backdrop(640, 480, ("ar0x", 9), 120))

# --- Plymouth logo: 320x80 ---------------------------------------------------
mask, mw, mh = glyph_masks("ar0x", 8)
ox, oy = (320 - mw) // 2, 12


def logo_fn(x, y):
    if oy <= y < oy + mh and ox <= x < ox + mw and (x - ox, y - oy) in mask:
        return cyan
    if oy + mh + 8 <= y < oy + mh + 11 and ox <= x < ox + mw:
        return magenta if x < ox + mw // 3 else lerp(void, cyan, 0.35)
    return void


write_png(os.path.join(OUT["plymouth"], "logo.png"), 320, 80, logo_fn)

# --- Plymouth progress frames: 400x6, 20 segments ---------------------------
SEGMENTS = 20
SEG_W = 18
GAP = 2
BAR_W = SEGMENTS * SEG_W + (SEGMENTS - 1) * GAP   # 398 -> fits 400
BAR_X = (400 - BAR_W) // 2
for n in range(SEGMENTS + 1):
    def progress_fn(x, y, n=n):
        j = x - BAR_X
        if j < 0 or j >= BAR_W:
            return void
        k = j // (SEG_W + GAP)
        in_gap = (j % (SEG_W + GAP)) >= SEG_W
        if in_gap:
            return void
        if k < n:
            return cyan if k < n - 1 else text
        return lerp(void, muted, 0.55)
    write_png(os.path.join(OUT["plymouth"], f"progress-{n}.png"),
              400, 6, progress_fn)

print("generated: 2 backgrounds + 1 logo + 21 progress frames")
PY

# --- Verify dimensions without external tools --------------------------------
python3 - "$AR0X_SOURCE_ROOT" <<'PY'
import os, struct, sys
root = sys.argv[1]
expected = {
    "assets/grub-theme/ar0x/background.png": (1024, 768),
    "assets/syslinux/splash.png": (640, 480),
    "assets/plymouth/ar0x/logo.png": (320, 80),
}
for i in range(21):
    expected[f"assets/plymouth/ar0x/progress-{i}.png"] = (400, 6)
for rel, want in expected.items():
    p = os.path.join(root, rel)
    with open(p, "rb") as fh:
        head = fh.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"bad PNG signature: {rel}"
    w, h = struct.unpack(">II", head[16:24])
    assert (w, h) == want, f"{rel}: {w}x{h} != {want}"
print(f"verified {len(expected)} PNG files (signature + dimensions)")
PY
