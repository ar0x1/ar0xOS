#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/ar0x_xcursor.py
# -----------------------------------------------------------------------------
# PHASE 7 — pure-stdlib Xcursor (Xcur) writer + self-verifying parser.
#
# WHY: Phase 6 shipped `XCURSOR_THEME=Adwaita` as a placeholder (RISK-040).
# A branded cursor set normally requires `xcursorgen` + Inkscape + a compiled
# hyprcursor theme. Neither is available in this sandbox, and shipping an
# unbuildable "source-only" theme would leave the ISO with an Adwaita cursor.
# Instead we WRITE the documented Xcursor binary format directly. Hyprland,
# XWayland, GTK3/GTK4 and Qt all read standard XCursor themes from
# /usr/share/icons/<theme>/cursors/ — no compiled hyprcursor manifest needed.
#
# Format (Xcursor(3), libXcursor):
#   file header  : magic "Xcur" + header=16 + version=1 + ntoc
#   TOC          : ntoc x (type, subtype, absolute byte position)
#   image chunk  : headerSize=36, type=0xfffd0002, subtype=nominal size,
#                  version=1, width, height, xhot, yhot, delay,
#                  width*height CARD32 ARGB pixels (little-endian).
#
# `verify_xcursor()` reads the file back and asserts every offset, type,
# subtype and pixel count. That is the test: if the writer is wrong, the
# generator fails instead of shipping a cursor the compositor cannot load.
#
# Adwaita is kept as `Inherits=Adwaita` in index.theme so any cursor name we do
# not ship still resolves through the official Arch package. RISK-040 closes.
# -----------------------------------------------------------------------------

from __future__ import annotations

import os
import struct

IMAGE_TYPE = 0xFFFD0002
COMMENT_TYPE = 0xFFFE0001
FILE_HEADER_SIZE = 16
IMAGE_HEADER_SIZE = 36
VERSION = 1
SIZES = (24, 32, 48)
GRID = 24  # design grid; every shape is authored in 24x24 units

TRANSPARENT = 0x00000000


def _argb(rgb, alpha=0xFF):
    r, g, b = rgb
    return (alpha << 24) | (r << 16) | (g << 8) | b


def _point_in_poly(x, y, poly):
    """Ray-casting point-in-polygon on the 24-unit design grid."""
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def _mask_from_test(test):
    """Build a 24x24 boolean grid from a predicate(x, y)."""
    return [[test(x, y) for x in range(GRID)] for y in range(GRID)]


def _outline(mask):
    """One-cell dark outline around a filled mask (Chebyshev neighbourhood)."""
    out = [[False] * GRID for _ in range(GRID)]
    for y in range(GRID):
        for x in range(GRID):
            if mask[y][x]:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < GRID and 0 <= nx < GRID and mask[ny][nx]:
                        out[y][x] = True
                        break
                if out[y][x]:
                    break
    return out


def _shape_arrow():
    poly = [(1, 1), (1, 19), (5, 15), (9, 22), (12, 21), (8, 14), (14, 14)]
    return _mask_from_test(lambda x, y: _point_in_poly(x + 0.5, y + 0.5, poly))


def _shape_ibeam():
    def test(x, y):
        horizontal = (1 <= y <= 3 or 20 <= y <= 22) and 6 <= x <= 17
        vertical = 11 <= x <= 12 and 1 <= y <= 22
        return horizontal or vertical
    return _mask_from_test(test)


def _shape_wait():
    def test(x, y):
        d2 = (x - 11.5) ** 2 + (y - 11.5) ** 2
        ring = 7.5 ** 2 <= d2 <= 9.5 ** 2
        hand = 10 <= x <= 13 and 4 <= y <= 12
        return ring or hand
    return _mask_from_test(test)


def _shape_hand():
    poly = [(8, 2), (12, 2), (12, 9), (14, 8), (16, 10), (18, 12),
            (18, 18), (15, 22), (8, 22), (6, 18), (6, 11), (7, 7)]
    return _mask_from_test(lambda x, y: _point_in_poly(x + 0.5, y + 0.5, poly))


def _shape_cross():
    def test(x, y):
        cx = 10 <= x <= 13 and (1 <= y <= 9 or 14 <= y <= 22)
        cy = 10 <= y <= 13 and (1 <= x <= 9 or 14 <= x <= 22)
        return cx or cy
    return _mask_from_test(test)


# name -> (shape builder, hotspot on the 24-unit grid, accent colour role)
SHAPES = {
    "left_ptr":  (_shape_arrow,  (1, 1)),
    "text":      (_shape_ibeam,  (12, 12)),
    "watch":     (_shape_wait,   (12, 12)),
    "pointer":   (_shape_hand,   (10, 3)),
    "crosshair": (_shape_cross,  (12, 12)),
}

# Standard X11 cursor aliases. Symlinks are what real cursor themes ship.
ALIASES = {
    "default": "left_ptr",
    "top_left_arrow": "left_ptr",
    "arrow": "left_ptr",
    "xterm": "text",
    "ibeam": "text",
    "wait": "watch",
    "left_ptr_watch": "watch",
    "progress": "watch",
    "hand2": "pointer",
    "hand": "pointer",
    "cross": "crosshair",
    "cross_reverse": "crosshair",
}


def render_pixels(name, size, rgb):
    """Return (width, height, xhot, yhot, [CARD32 ARGB ...]) for one frame."""
    builder, (hx, hy) = SHAPES[name]
    mask = builder()
    outline = _outline(mask)
    pixels = []
    for y in range(size):
        gy = y * GRID // size
        for x in range(size):
            gx = x * GRID // size
            if mask[gy][gx]:
                # Magenta tip on the arrow / accent node on the other shapes;
                # cyan is the body, exactly the ar0x brand pair.
                if name == "left_ptr" and gy <= 2 and gx <= 2:
                    pixels.append(_argb(rgb["MAGENTA"]))
                elif name == "wait" and 6 <= gy <= 11 and 10 <= gx <= 13:
                    pixels.append(_argb(rgb["MAGENTA"]))
                else:
                    pixels.append(_argb(rgb["CYAN"]))
            elif outline[gy][gx]:
                pixels.append(_argb(rgb["VOID"]))
            else:
                pixels.append(TRANSPARENT)
    xhot = max(0, min(size - 1, round(hx * size / GRID)))
    yhot = max(0, min(size - 1, round(hy * size / GRID)))
    return (size, size, xhot, yhot, pixels)


def write_xcursor(path, name, rgb, sizes=SIZES):
    """Write one Xcursor file containing one image per nominal size."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = []
    for nominal in sizes:
        w, h, xhot, yhot, px = render_pixels(name, nominal, rgb)
        frames.append((nominal, w, h, xhot, yhot, px))

    header_size = FILE_HEADER_SIZE + 12 * len(frames)
    chunks = []
    for nominal, w, h, xhot, yhot, px in frames:
        assert w * h == len(px), "pixel count mismatch"
        head = struct.pack("<9I", IMAGE_HEADER_SIZE, IMAGE_TYPE, nominal, VERSION,
                           w, h, xhot, yhot, 0)
        chunks.append(head + struct.pack("<%dI" % len(px), *px))

    toc = []
    pos = header_size
    for i, frame in enumerate(frames):
        toc.append((IMAGE_TYPE, frame[0], pos))
        pos += len(chunks[i])

    out = bytearray(b"Xcur")
    out += struct.pack("<3I", FILE_HEADER_SIZE, VERSION, len(toc))
    for typ, subtype, position in toc:
        out += struct.pack("<3I", typ, subtype, position)
    for chunk in chunks:
        out += chunk
    with open(path, "wb") as fh:
        fh.write(bytes(out))
    return len(out)


def verify_xcursor(path, sizes=SIZES):
    """Parse an Xcur file back and assert the whole structure. Returns ntoc."""
    with open(path, "rb") as fh:
        data = fh.read()
    assert len(data) >= FILE_HEADER_SIZE, "%s: truncated" % path
    assert data[:4] == b"Xcur", "%s: bad magic" % path
    header, version, ntoc = struct.unpack("<3I", data[4:16])
    assert header == FILE_HEADER_SIZE, "%s: header=%d" % (path, header)
    assert version == VERSION, "%s: version=%d" % (path, version)
    assert ntoc == len(sizes), "%s: ntoc=%d" % (path, ntoc)

    toc = [struct.unpack("<3I", data[16 + 12 * i: 28 + 12 * i])
           for i in range(ntoc)]
    assert toc[0][2] == FILE_HEADER_SIZE + 12 * ntoc, "%s: bad first offset" % path
    for i, (typ, subtype, position) in enumerate(toc):
        assert typ == IMAGE_TYPE, "%s: TOC type" % path
        assert subtype == sizes[i], "%s: TOC subtype %d" % (path, subtype)
        assert 0 < position < len(data), "%s: TOC offset out of range" % path
        head = struct.unpack("<9I", data[position: position + IMAGE_HEADER_SIZE])
        hsize, ctype, csub, cver, w, h, xhot, yhot, delay = head
        assert hsize == IMAGE_HEADER_SIZE, "%s: chunk header size" % path
        assert ctype == typ and csub == subtype and cver == VERSION, "%s: chunk/TOC mismatch" % path
        assert w == sizes[i] and h == sizes[i], "%s: dimensions" % path
        assert xhot <= w and yhot <= h and delay == 0, "%s: hotspot/delay" % path
        assert len(data) >= position + IMAGE_HEADER_SIZE + 4 * w * h, "%s: pixels truncated" % path
    return ntoc


def build_theme(dest_dir, rgb):
    """Write every cursor file + alias symlinks. Returns (files, aliases)."""
    os.makedirs(dest_dir, exist_ok=True)
    written = []
    for name in sorted(SHAPES):
        path = os.path.join(dest_dir, name)
        write_xcursor(path, name, rgb)
        verify_xcursor(path)
        written.append(path)
    for alias, target in sorted(ALIASES.items()):
        path = os.path.join(dest_dir, alias)
        if os.path.lexists(path):
            os.remove(path)
        os.symlink(target, path)
        assert os.readlink(path) == target
    return written, sorted(ALIASES)
