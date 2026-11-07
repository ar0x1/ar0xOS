#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/gen-branding-assets.sh
# -----------------------------------------------------------------------------
# PHASE 7 — deterministically generate every BINARY brand asset.
#
# Outputs (all relative to the source root):
#   assets/logo/ar0x-logo-256.png                        256x256 RGB on void
#   assets/logo/ar0x-logo-512.png                        512x512 RGB on void
#   archiso/airootfs/usr/share/icons/ar0x-cursors/
#       index.theme, cursor.theme                        text, from assets/
#       cursors/{left_ptr,text,watch,pointer,crosshair}  Xcursor binaries
#       cursors/{12 alias symlinks}                      standard X11 names
#
# The SVG files in assets/logo/ and assets/icons/ are the AUTHORITATIVE masters;
# this script renders the same geometry into the raster-only formats required by
# GRUB/Plymouth/Calamares and by the XCursor spec. tools/lib/ar0x_logo.py holds
# the shared geometry so tools/gen-theme-assets.sh (boot art) cannot drift.
#
# WHY NO xcursorgen / Inkscape / hyprcursor-util: none is available on the build
# host, and a "source-only" cursor theme would leave the ISO with Adwaita. We
# write the documented Xcursor binary format directly (tools/lib/ar0x_xcursor.py)
# and PARSE IT BACK in the same run. If the writer is wrong, this script fails.
#
# Requires: python3 only. No root, no network, no font files, no ImageMagick.
# Byte-reproducible: zlib level 9, no timestamps, no randomness.
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
import shutil
import struct
import sys

ROOT = sys.argv[1]
sys.path.insert(0, os.path.join(ROOT, "tools", "lib"))
from ar0x_logo import load_palette, logo_overlay, write_png          # noqa: E402
from ar0x_xcursor import build_theme, verify_xcursor, SIZES, SHAPES, ALIASES  # noqa: E402

rgb, hex_pins = load_palette(ROOT)
print("[ OK ] ADR-015 palette loaded from config/versions.env (8 pins)")

# --- Section 1: standalone logo PNGs -----------------------------------------
# 6% margin on every side => 88% mark, ~1/8 clear space. RGB on void because
# the boot loaders that consume raster art do not need an alpha channel.
LOGO_DIR = os.path.join(ROOT, "assets", "logo")
for size in (256, 512):
    margin = int(size * 0.06)
    box_w = size - 2 * margin
    overlay = logo_overlay(margin, margin, box_w, rgb)
    void = rgb["VOID"]

    def fn(x, y, overlay=overlay, void=void):
        hit = overlay(x, y)
        return hit if hit is not None else void

    path = os.path.join(LOGO_DIR, "ar0x-logo-%d.png" % size)
    nbytes = write_png(path, size, size, fn)
    print("[ OK ] wrote assets/logo/ar0x-logo-%d.png (%d bytes)" % (size, nbytes))

# --- Section 2: XCursor theme ------------------------------------------------
# Canonical text metadata lives in assets/cursors/ar0x-cursors/; the generated
# binaries land directly in the staged archiso profile, which bootstrap.sh
# copies into the ISO. --sync re-installs the text files (idempotent).
SRC_THEME = os.path.join(ROOT, "assets", "cursors", "ar0x-cursors")
DST_THEME = os.path.join(ROOT, "archiso", "airootfs", "usr", "share", "icons", "ar0x-cursors")
os.makedirs(DST_THEME, exist_ok=True)
for name in ("index.theme", "cursor.theme"):
    shutil.copyfile(os.path.join(SRC_THEME, name), os.path.join(DST_THEME, name))
    print("[ OK ] installed %s -> /usr/share/icons/ar0x-cursors/" % name)

written, aliases = build_theme(os.path.join(DST_THEME, "cursors"), rgb)
for path in written:
    ntoc = verify_xcursor(path, SIZES)
    print("[ OK ] Xcursor %-10s %d frames, %d bytes" %
          (os.path.basename(path), ntoc, os.path.getsize(path)))
for alias in aliases:
    link = os.path.join(DST_THEME, "cursors", alias)
    assert os.path.islink(link), "missing alias symlink: " + alias
print("[ OK ] %d alias symlinks -> %d authored shapes" % (len(aliases), len(SHAPES)))
PY

# --- Section 3: verify PNG signature + IHDR without external tools ------------
python3 - "$AR0X_SOURCE_ROOT" <<'PY'
import os
import struct
import sys

ROOT = sys.argv[1]
expected = {
    "assets/logo/ar0x-logo-256.png": (256, 256),
    "assets/logo/ar0x-logo-512.png": (512, 512),
}
for rel, want in expected.items():
    path = os.path.join(ROOT, rel)
    with open(path, "rb") as fh:
        head = fh.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", "bad PNG signature: " + rel
    w, h = struct.unpack(">II", head[16:24])
    assert (w, h) == want, "%s: %dx%d != %dx%d" % (rel, w, h, want[0], want[1])
print("[ OK ] verified %d logo PNGs (signature + IHDR)" % len(expected))
PY

ok "Phase 7 binary brand assets generated (2 logo PNGs + 5 Xcursor files + 12 aliases)"
printf '\nNext: ./tools/configure-branding.sh --sync && ./tools/build-kernel.sh --sync\n'
