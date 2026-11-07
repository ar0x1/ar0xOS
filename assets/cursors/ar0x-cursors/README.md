# /home/user/ar0xOS/assets/cursors/ar0x-cursors/

Phase 7 closes RISK-040 by shipping a REAL, loadable XCursor theme instead of
the Phase 6 `Adwaita` placeholder.

## What is here (canonical, human-edited)

| File | Installed path |
|---|---|
| `index.theme` | `/usr/share/icons/ar0x-cursors/index.theme` |
| `cursor.theme` | `/usr/share/icons/ar0x-cursors/cursor.theme` |

## What is generated (do not edit by hand)

`cursors/*` is produced by `./tools/gen-branding-assets.sh` using the pure-stdlib
writer in `tools/lib/ar0x_xcursor.py`, and is written straight into the staged
archiso profile at `archiso/airootfs/usr/share/icons/ar0x-cursors/cursors/`.

Authored shapes (each at nominal sizes 24, 32 and 48 in ONE `.Xcur` file):

| File | Shape | Hotspot (24-unit grid) |
|---|---|---|
| `left_ptr` | pointer arrow, magenta tip | (1, 1) |
| `text` | I-beam | (12, 12) |
| `watch` | ring + magenta hand | (12, 12) |
| `pointer` | pointing hand | (10, 3) |
| `crosshair` | hollow cross | (12, 12) |

Symlink aliases: `default`, `top_left_arrow`, `arrow`, `xterm`, `ibeam`, `wait`,
`left_ptr_watch`, `progress`, `hand2`, `hand`, `cross`, `cross_reverse`.

Colours: cyan `#00E5FF` body, magenta `#FF2E88` accent, void `#07090F` 1-cell
outline, everything else fully transparent. `Inherits=Adwaita` supplies any
name we do not author.

## Why NOT hyprcursor

`hyprcursor-util` compiles SVG source into `manifest.hl` + `.hlc` binaries. It
is not available in this build sandbox, and a hand-authored `manifest.hl`
without compiled cursors is not loadable. Hyprland, XWayland, GTK3/GTK4 and Qt
all consume plain XCursor themes from `/usr/share/icons/<theme>/cursors/`, so
the standard format is the correct v0.1 target. A compiled hyprcursor variant
is a v0.2 roadmap item.

## Verification performed here

`tools/lib/ar0x_xcursor.py::verify_xcursor()` parses every generated file back
(magic `Xcur`, header=16, version=1, TOC offsets, chunk header=36, subtype=nominal
size, `width*height` ARGB pixels). NO compositor was run in this sandbox —
see RISK-044 in `docs/architecture/RISK_REGISTER.md`.
