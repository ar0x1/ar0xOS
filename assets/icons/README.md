# /home/user/ar0xOS/assets/icons/

| Canonical source | Installed path | Consumer |
|---|---|---|
| `assets/icons/ar0x-logo.svg` | `/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg` | `LOGO=ar0x-logo` in `/etc/os-release` (os-release(5), systemd >= 252) |
| `assets/cursors/ar0x-cursors/` | `/usr/share/icons/ar0x-cursors/` | `XCURSOR_THEME=ar0x-cursors` (Hyprland / XWayland / GTK / Qt) |

`ar0x-logo.svg` is the **icon-theme** variant of `assets/logo/ar0x-logo.svg`: same
512x512 geometry at 0.75 scale on a `#07090F` rounded-square plate. The plate is
required because freedesktop icon themes can be light; the transparent master
would lose the cyan frame on a white background.

Raster icon sizes are intentionally NOT checked in. `hicolor/scalable` is enough
for `LOGO`, and the 256/512 PNGs in `assets/logo/` cover every Calamares /
welcome-app / Plymouth need in Phase 8/10. If a PNG icon is required later,
render the SVG with `rsvg-convert -w 256 -h 256 assets/icons/ar0x-logo.svg`.
