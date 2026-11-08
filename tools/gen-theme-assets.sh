#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/gen-theme-assets.sh
# -----------------------------------------------------------------------------
# PHASE 4 generator / PHASE 7 FINAL ART — deterministically generate ar0x boot
# artwork (PNG only).
#
# Why a generator instead of checked-in AI art: PNGs produced here are
# byte-for-byte reproducible, have no licensing ambiguity, are tiny (a few KB),
# and can be regenerated after a palette change without a design tool.
#
# PHASE 7 CHANGE: the Phase 4 bitmap-font "ar0x" placeholder wordmark is gone.
# All three backgrounds now draw the OFFICIAL 512x512 logomark from
# assets/logo/ar0x-logo.svg via the shared geometry in tools/lib/ar0x_logo.py.
# The same module is used by tools/gen-branding-assets.sh, so the boot splash,
# the standalone logo PNG and the SVG can never drift apart.
#
# Outputs (all relative to the source root):
#   assets/grub-theme/ar0x/background.png      1024x768
#   assets/plymouth/ar0x/logo.png              320x80  (horizontal lockup)
#   assets/plymouth/ar0x/progress-{0..20}.png  400x6
#   assets/syslinux/splash.png                 640x480
#
# Dimensions are CONTRACT with tools/build-kernel.sh::validate_assets() and the
# GRUB/syslinux/Plymouth configs. Do not change them without editing both.
#
# Requires: python3. No root, no network, no ImageMagick, no font files. Pure
# zlib PNG encoder. Byte-reproducible: zlib level 9, no timestamps, no RNG.
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

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "tools", "lib"))
from ar0x_logo import (load_palette, lerp, logo_overlay, write_png,           # noqa: E402
                       glyph_masks)

rgb, hex_pins = load_palette(ROOT)
void, surface = rgb["VOID"], rgb["SURFACE"]
cyan, magenta = rgb["CYAN"], rgb["MAGENTA"]
text, muted, lime = rgb["TEXT"], rgb["MUTED"], rgb["LIME"]
grid = (0x1A, 0x23, 0x30)
print("[ OK ] ADR-015 palette loaded from config/versions.env (8 pins)")

OUT = {
    "grub":     os.path.join(ROOT, "assets/grub-theme/ar0x"),
    "plymouth": os.path.join(ROOT, "assets/plymouth/ar0x"),
    "syslinux": os.path.join(ROOT, "assets/syslinux"),
}


def backdrop(width, height, logo_size, logo_y, caption_scale, accent_frac=0.90):
    """Dark gradient + engineering grid + OFFICIAL logomark + short caption.

    The GRUB theme.txt no longer draws a header label, so the PNG owns the
    brand lockup. See assets/grub-theme/ar0x/theme.txt for the new layout.
    """
    overlay = logo_overlay((width - logo_size) // 2, logo_y, logo_size, rgb)
    mask, mw, mh = glyph_masks("ar0x", caption_scale)
    cap_x = (width - mw) // 2
    cap_y = logo_y + logo_size + 12
    accent_y = int(height * accent_frac)
    accent_end = int(width * 0.34)

    def fn(x, y):
        base = lerp(void, surface, y / max(1, height - 1))
        # faint 64px engineering grid
        if x % 64 == 0 or y % 64 == 0:
            base = lerp(base, grid, 0.55)
        # horizontal cyan rule with a short magenta segment
        if accent_y <= y < accent_y + 3 and 0 < x < accent_end:
            return cyan if x < accent_end - 60 else magenta
        # official logomark (cyan frame + chevron, magenta underscore, lime node)
        hit = overlay(x, y)
        if hit is not None:
            return hit
        # small "ar0x" bitmap caption below the mark, in primary text colour
        if cap_y <= y < cap_y + mh and cap_x <= x < cap_x + mw:
            if (x - cap_x, y - cap_y) in mask:
                return text
        # lime status dot + muted version rule under the caption
        if cap_y + mh + 6 <= y < cap_y + mh + 9:
            if cap_x <= x < cap_x + 24:
                return lime
            if cap_x + 32 <= x < cap_x + mw:
                return lerp(void, muted, 0.7)
        return base

    return fn


# --- GRUB: 1024x768 ----------------------------------------------------------
# Mark 186px at y=20, caption at 218..260. theme.txt boot_menu starts at 34%
# (261px), so nothing overlaps. Progress bar 78%, footer 84%.
write_png(os.path.join(OUT["grub"], "background.png"), 1024, 768,
          backdrop(1024, 768, logo_size=186, logo_y=20, caption_scale=6,
                   accent_frac=0.90))

# --- syslinux/vesamenu: 640x480 ---------------------------------------------
write_png(os.path.join(OUT["syslinux"], "splash.png"), 640, 480,
          backdrop(640, 480, logo_size=140, logo_y=14, caption_scale=5,
                   accent_frac=0.90))

# --- Plymouth logo: 320x80 HORIZONTAL LOCKUP ---------------------------------
# Plymouth's script plugin places this sprite centred. Mark on the left,
# "ar0x" bitmap wordmark on the right, magenta underline. 320x80 is fixed by
# ar0x.script (it centres using Image.GetWidth/GetHeight).
mark = logo_overlay(12, 8, 64, rgb)
mask, mw, mh = glyph_masks("ar0x", 7)      # 168 x 49
word_x, word_y = 108, 16


def logo_fn(x, y):
    hit = mark(x, y)
    if hit is not None:
        return hit
    if word_y <= y < word_y + mh and word_x <= x < word_x + mw:
        if (x - word_x, y - word_y) in mask:
            return text
    if word_y + mh + 6 <= y < word_y + mh + 9 and word_x <= x < word_x + mw:
        return magenta if x < word_x + 56 else lerp(void, cyan, 0.35)
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

print("generated: 2 backgrounds + 1 logo lockup + 21 progress frames "
      "(official Phase 7 logomark)")
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
    expected["assets/plymouth/ar0x/progress-%d.png" % i] = (400, 6)
for rel, want in expected.items():
    p = os.path.join(root, rel)
    with open(p, "rb") as fh:
        head = fh.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"bad PNG signature: {rel}"
    w, h = struct.unpack(">II", head[16:24])
    assert (w, h) == want, f"{rel}: {w}x{h} != {want}"
print(f"verified {len(expected)} PNG files (signature + dimensions)")
PY

ok "Phase 7 final boot artwork generated (SVG-derived logomark, deterministic)"
printf '\nNext: ./tools/build-kernel.sh --sync  (propagates to the archiso profile)\n'
