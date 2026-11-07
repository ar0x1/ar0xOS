# /home/user/ar0xOS/assets/wallpapers/PLACEHOLDERS.md

## Phase 1 — canonical wallpaper paths (art delivered in Phases 6/7)

No large binary artwork is committed in Phase 1. These are the **exact paths** every config,
PKGBUILD and theme will reference, so later assets can be dropped in without editing configs.

| Path in this repo | Installed path | Spec |
|---|---|---|
| `assets/wallpapers/ar0x-neon-grid.png` | `/usr/share/backgrounds/ar0x/ar0x-neon-grid.png` | 3840x2160, `#07090F` base + `#00E5FF` perspective grid, default wallpaper |
| `assets/wallpapers/ar0x-void.png` | `/usr/share/backgrounds/ar0x/ar0x-void.png` | 3840x2160, near-black `#07090F` with subtle noise, low-distraction |
| `assets/wallpapers/ar0x-circuit.png` | `/usr/share/backgrounds/ar0x/ar0x-circuit.png` | 3840x2160, `#FF2E88` circuit traces, SDDM/lock screen |
| `assets/wallpapers/ar0x-grub-bg.png` | `/boot/grub/themes/ar0x/background.png` | 1920x1080, GRUB background (must be a GRUB-supported PNG) |

### Palette (from `config/versions.env`, single source of truth)
`#07090F` void · `#11151F` surface · `#00E5FF` cyan · `#FF2E88` magenta ·
`#A8FF60` lime · `#D7E0EE` text · `#6B7891` muted · `#FF5C57` alert.

### Recommended sources for the final art (Phase 7)
- Generate in-house with Inkscape / Blender using `assets/logo/ar0x-logo.svg` as the base.
- CC0/CC BY geometry textures from ambientCG or Poly Haven for the noise/circuit layers.
- Unsplash / Pexels CC0 neon city photography only as a **layer**, never as the whole wallpaper.
- Keep each final PNG under 4 MB; the ISO has a 2.2 GB hard gate (PROJECT_PLAN.md §7).
- Ship a `LICENSE` per asset. ar0x-authored artwork = CC BY-SA 4.0.

### Do not
- Do not use a 4K PNG for the GRUB background (GRUB's PNG parser is memory-limited).
- Do not reference `~/wallpapers` or any user-home path from `/etc/skel` configs.
