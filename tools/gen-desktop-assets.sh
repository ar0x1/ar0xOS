#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/gen-desktop-assets.sh
# -----------------------------------------------------------------------------
# PHASE 6 — deterministically generate the ar0x DESKTOP artwork (PNG only).
#
# Why a generator instead of checked-in AI art: PNGs produced here are
# byte-for-byte reproducible, have no licensing ambiguity, are small, and can
# be regenerated after a palette change without a design tool.
# PHASE 7 DECISION (ADR-022): these geometric PNGs ARE the v0.1 wallpapers.
# Phase 7 finalised the BOOT art (GRUB/Plymouth/syslinux) and shipped a real
# ar0x-cursors XCursor theme, but deliberately KEEPS these wallpapers. A v0.2
# art set may replace them at the SAME paths without any config churn.
#
# Outputs (all absolute paths):
#   /home/user/ar0xOS/assets/wallpapers/ar0x-neon-grid.png    3840x2160
#   /home/user/ar0xOS/assets/wallpapers/ar0x-void.png         3840x2160
#   /home/user/ar0xOS/assets/wallpapers/ar0x-circuit.png      3840x2160
#   /home/user/ar0xOS/assets/sddm/ar0x/background.png         1920x1080
#
# Paths are the exact ones declared in Phase 1's assets/wallpapers/PLACEHOLDERS.md,
# so hyprpaper.conf / hyprlock.conf / SDDM theme.conf need no edits when the
# final art lands. `background.png` lives INSIDE the theme directory because
# SDDM's Qt.resolvedUrl(config.background) resolves relative to the theme.
#
# Requires: python3 (already required by Phase 4's gen-theme-assets.sh).
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
WALL = os.path.join(ROOT, "assets", "wallpapers")
SDDM = os.path.join(ROOT, "assets", "sddm", "ar0x")

# --- Palette: single source of truth is config/versions.env (ADR-015) --------
VOID    = (0x07, 0x09, 0x0F)
SURFACE = (0x11, 0x15, 0x1F)
CYAN    = (0x00, 0xE5, 0xFF)
MAGENTA = (0xFF, 0x2E, 0x88)
LIME    = (0xA8, 0xFF, 0x60)
MUTED   = (0x6B, 0x78, 0x91)
GRID    = (0x1A, 0x23, 0x30)


def mix(a, b, t):
    """Linear blend of two RGB triples; t in [0, 1]."""
    t = max(0.0, min(1.0, t))
    return (int(round(a[0] + (b[0] - a[0]) * t)),
            int(round(a[1] + (b[1] - a[1]) * t)),
            int(round(a[2] + (b[2] - a[2]) * t)))


def scale(c, t):
    return mix((0, 0, 0), c, t)


def write_png(path, width, height, row_fn):
    """Write an 8-bit RGB PNG. row_fn(y) -> bytes/bytearray of width*3 bytes."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    for y in range(height):
        raw.append(0)                      # PNG filter type 0 (None)
        row = row_fn(y)
        assert len(row) == width * 3, f"row {y} length {len(row)} != {width*3}"
        raw.extend(row)
    comp = zlib.compress(bytes(raw), 6)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


def base_row(width, colour):
    return bytearray(bytes(colour) * width)


def put(row, width, x, colour, thickness=1):
    """Paint `thickness` pixels at x, clipping to the row."""
    if x < 0 or x >= width:
        return
    blob = bytes(colour) * min(thickness, width - x)
    row[x * 3:(x + len(blob) // 3) * 3] = blob


def span(row, width, x0, x1, colour):
    """Paint a horizontal [x0, x1) span in one slice assignment."""
    x0 = max(0, min(width, x0))
    x1 = max(0, min(width, x1))
    if x1 <= x0:
        return
    row[x0 * 3:x1 * 3] = bytes(colour) * (x1 - x0)


# --- 1. ar0x-neon-grid.png — cyan perspective grid + magenta horizon --------
def neon_grid(width, height):
    horizon = int(height * 0.58)
    vp = width // 2
    # Perspective-spaced horizontal grid lines (fixed set, computed once).
    hlines = {horizon + int((height - horizon) * ((j / 16.0) ** 1.75))
              for j in range(1, 17)}
    vlines = list(range(-24, 25))

    def row_fn(y):
        t = y / float(height)
        col = mix(VOID, SURFACE, t * 0.55)
        row = base_row(width, col)
        # Horizon glow: a few rows above and below, fading out.
        d = abs(y - horizon)
        if d < 90:
            glow = scale(MAGENTA, (1.0 - d / 90.0) * 0.42)
            span(row, width, 0, width, mix(col, glow, 1.0))
        if y in hlines or y == horizon:
            span(row, width, 0, width, mix(col, CYAN if y != horizon else MAGENTA, 0.55))
        if y >= horizon:
            f = (y - horizon) / float(height - horizon)
            line_col = mix(GRID, CYAN, 0.18 + 0.55 * f)
            for k in vlines:
                xb = vp + k * (width // 16)
                x = int(vp + (xb - vp) * f)
                put(row, width, x, line_col, 2)
        return row
    return row_fn


# --- 2. ar0x-void.png — near-black with a soft cyan core --------------------
def void_field(width, height):
    cx, cy = width // 2, int(height * 0.46)
    rx, ry = int(width * 0.44), int(height * 0.46)

    def row_fn(y):
        dy = (y - cy) / float(ry)
        if abs(dy) >= 1.0:
            row = base_row(width, mix(VOID, SURFACE, 0.12))
        else:
            half = int(rx * (1.0 - dy * dy) ** 0.5)
            # Ellipse is drawn as one span with a horizontally graded colour.
            centre = mix(VOID, CYAN, 0.085 * (1.0 - abs(dy)))
            row = base_row(width, mix(VOID, SURFACE, 0.12))
            span(row, width, cx - half, cx + half,
                 mix(mix(VOID, SURFACE, 0.12), centre, 0.72))
        # A single thin cyan scanline keeps the "terminal" character.
        if y % 240 == 0:
            span(row, width, 0, width, mix(VOID, CYAN, 0.10))
        return row
    return row_fn


# --- 3. ar0x-circuit.png — magenta traces on a surface base ----------------
def circuit(width, height):
    step_x, step_y = 160, 96

    def row_fn(y):
        row = base_row(width, SURFACE)
        # Horizontal bus every step_y rows.
        if y % step_y < 2:
            span(row, width, 0, width, mix(SURFACE, MAGENTA, 0.34))
        # Vertical traces: only in alternating bands so the pattern bends.
        band = y // step_y
        for n in range(0, width // step_x + 1):
            x = n * step_x + (band % 3) * (step_x // 4)
            if (n + band) % 4 != 0:
                put(row, width, x, mix(SURFACE, MAGENTA, 0.30), 2)
            if y % step_y in range(step_y // 2 - 4, step_y // 2 + 5):
                # Junction pad (cyan for variety, deterministic).
                if (n + band) % 3 == 0:
                    span(row, width, x - 5, x + 6, mix(SURFACE, LIME, 0.42))
        # Sparse cyan vias.
        if y % (step_y * 4) == 7:
            for n in range(0, width // (step_x * 2) + 1):
                x = n * step_x * 2 + 37
                span(row, width, x - 3, x + 4, mix(SURFACE, CYAN, 0.5))
        return row
    return row_fn


# --- 4. SDDM background.png — dark, with a reserved centre panel zone ------
def sddm_bg(width, height):
    horizon = int(height * 0.62)

    def row_fn(y):
        row = base_row(width, mix(VOID, SURFACE, 0.35 * y / height))
        # Diagonal cyan streaks (slope 2 px right per 1 px down).
        for k in range(-8, 20):
            x = (k * 137 + y * 2) % width
            put(row, width, x, scale(CYAN, 0.10), 2)
        if y == horizon:
            span(row, width, 0, width, mix(VOID, MAGENTA, 0.30))
        # Dim the centre so the login panel text stays readable.
        pw, ph = 520, 380
        if abs(y - height // 2) < ph // 2:
            span(row, width, width // 2 - pw // 2, width // 2 + pw // 2,
                 mix(VOID, SURFACE, 0.20))
        return row
    return row_fn


sizes = []
sizes.append((os.path.join(WALL, "ar0x-neon-grid.png"), 3840, 2160, neon_grid))
sizes.append((os.path.join(WALL, "ar0x-void.png"),      3840, 2160, void_field))
sizes.append((os.path.join(WALL, "ar0x-circuit.png"),   3840, 2160, circuit))
sizes.append((os.path.join(SDDM, "background.png"),     1920, 1080, sddm_bg))

for path, w, h, factory in sizes:
    nbytes = write_png(path, w, h, factory(w, h))
    print(f"wrote {os.path.relpath(path, ROOT)} ({w}x{h}, {nbytes} bytes)")
PY

# --- Verification pass: signature + IHDR dimensions -------------------------
python3 - "$AR0X_SOURCE_ROOT" <<'PY'
import os
import sys
import struct

ROOT = sys.argv[1]
expected = {
    "assets/wallpapers/ar0x-neon-grid.png": (3840, 2160),
    "assets/wallpapers/ar0x-void.png":      (3840, 2160),
    "assets/wallpapers/ar0x-circuit.png":   (3840, 2160),
    "assets/sddm/ar0x/background.png":      (1920, 1080),
}
for rel, (w, h) in expected.items():
    path = os.path.join(ROOT, rel)
    with open(path, "rb") as fh:
        head = fh.read(33)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"bad PNG signature: {rel}"
    assert head[12:16] == b"IHDR", f"bad IHDR: {rel}"
    got = struct.unpack(">II", head[16:24])
    assert got == (w, h), f"bad dimensions {rel}: {got} != {(w, h)}"
print(f"verified {len(expected)} PNG files (signature + dimensions)")
PY

ok "Phase 6 desktop artwork generated and verified"
