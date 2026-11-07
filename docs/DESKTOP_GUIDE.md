# ar0x — Phase 6: Desktop & Theming

> **Status:** ✅ COMPLETE (2026-11-07). Phase 7 (Branding & Identity) is next and
> requires your confirmation.
> Canonical sources: `/home/user/ar0xOS/config/desktop/**`,
> `/home/user/ar0xOS/assets/sddm/ar0x/**`, `/home/user/ar0xOS/assets/wallpapers/**`.
> Driver: `/home/user/ar0xOS/tools/configure-desktop.sh`.
> Companion docs: `BUILD_LAYOUT.md` §2/§4, `DECISIONS.md` ADR-021, `RISK_REGISTER.md`.

---

## ⚠️ Warnings repeated at the start of Phase 6

1. **RISK-002 — Hyprland 0.57 has NO `hyprland.conf`.** Lua (`hyprland.lua`) is
   mandatory, there is **no converter**, and `hyprctl keyword` is disabled. A
   single stray `hyprland.conf` in the tree fails `configure-desktop.sh --check`
   and `validate-versions.sh`. Do not "translate" old hyprlang files.
2. **RISK-040 — the artwork and cursor are PLACEHOLDERS.** Three 3840×2160
   wallpapers and the SDDM background are generated deterministically by
   `tools/gen-desktop-assets.sh`. The cursor is Arch's `Adwaita`. Phase 7 ships
   the official ar0x SVG logo, hyprcursor theme and final wallpapers **at the
   same paths**, so no config changes will be needed.
3. **RISK-043 — no live desktop was rendered in this sandbox.** There is no
   Hyprland, no SDDM greeter, no `fc-cache`, no QEMU/KVM, no display and no root.
   `Hyprland --verify-config`, `sddm-greeter --test-mode` and a QEMU Wayland
   session are **manual steps on a real Arch host** (§7).
4. **RISK-038 — SDDM's greeter is X11, the user session is Wayland.** Arch's
   `sddm 0.21.0-7` hard-depends on `xorg-server`; `DisplayServer=wayland` is
   still experimental. The QML theme must therefore be **Qt6-compatible**
   (no `QtGraphicalEffects`, no `Qt5Compat`, no versioned Qt5 imports).
5. **RISK-039 — never set `GDK_BACKEND` globally.** Forcing `wayland` breaks GTK
   apps that must run under XWayland. Phase 5 made this decision; Phase 6's
   Lua `env.lua` and `/etc/environment.d/` drop-in both honour it and are
   asserted by `--check`.

---

## 1. What Phase 6 delivers

| Area | Delivered |
|---|---|
| Compositor | Hyprland **0.57.1** Lua config: 1 entry point + 10 `lua/*.lua` modules |
| Session helpers | `hyprpaper.conf`, `hyprlock.conf`, `hypridle.conf` (0.57 Lua dispatcher for DPMS) |
| Bar | Waybar 0.15.0 `config.jsonc` + full `style.css` |
| Display manager | SDDM 0.21 Qt6 theme: `Main.qml`, `metadata.desktop`, `theme.conf`, `background.png`, `/etc/sddm.conf.d/10-ar0x.conf` |
| GTK3 | `settings.ini` (Adwaita-dark base) + `gtk.css` override layer |
| GTK4 / libadwaita | `settings.ini` + `gtk.css` with the full `@define-color` set |
| Qt5 / Qt6 | `qt5ct.conf` / `qt6ct.conf`, one `QT_QPA_PLATFORMTHEME=qt5ct:qt6ct` |
| Icons / cursors | `Papirus-Dark` + `/etc/skel/.icons/default/index.theme` (Adwaita placeholder) |
| Fonts | `fontconfig/conf.d/99-ar0x-fonts.conf` — Inter / JetBrains Mono Nerd / Noto |
| Wallpapers | 3 × 3840×2160 PNG at the exact Phase 1 paths + `PLACEHOLDERS.md` sources |
| `/etc/skel` | 11 dotfiles + 10 generated `.config/**` trees (zsh, bash, starship, git, fastfetch, portals, user-dirs, MIME) |
| Extras | kitty, wofi, mako configs — all branded with the ar0x palette |
| Driver | `tools/configure-desktop.sh` (`--check` / `--sync` / `--apply`), `tools/gen-desktop-assets.sh` |
| Docs | this guide; `PROJECT_PLAN.md`, `BUILD_LAYOUT.md`, `COMPONENT_VERSIONS.md`, `DECISIONS.md`, `RISK_REGISTER.md`, `DEPENDENCY_GRAPH.md` reconciled |

---

## 2. Exact commands

```bash
# --- 1. Generate the placeholder artwork (NO root, NO network) ---------------
cd /home/user/ar0xOS
./tools/gen-desktop-assets.sh
#   writes 3 × 3840x2160 wallpapers + assets/sddm/ar0x/background.png
#   byte-for-byte reproducible; verified signature + dimensions on every run

# --- 2. Read-only validation (NO root, NO writes) ----------------------------
./tools/configure-desktop.sh --check
./tools/configure-desktop.sh --help

# --- 3. Materialise canonical configs into the archiso profile ---------------
./tools/configure-desktop.sh --sync
#   config/desktop/<tool>/**      -> config/desktop/skel/.config/<tool>/**  (generated)
#   config/desktop/skel/**        -> archiso/airootfs/etc/skel/**
#   config/desktop/etc/**         -> archiso/airootfs/etc/**
#   assets/sddm/ar0x/*            -> archiso/airootfs/usr/share/sddm/themes/ar0x/
#   assets/wallpapers/*.png       -> archiso/airootfs/usr/share/backgrounds/ar0x/

# --- 4. Keep the other phases' generated copies in sync ----------------------
./tools/bootstrap.sh --sync
./tools/build-kernel.sh --sync
./tools/configure-system.sh --sync

# --- 5. Full validator sweep (NO root) ---------------------------------------
bash -n tools/*.sh tools/lib/*.sh
./tools/validate-versions.sh
./tools/bootstrap.sh --check
./tools/build-kernel.sh --check
./tools/build-kernel.sh --self-test
./tools/setup-build-env.sh --check
./tools/configure-system.sh --check
./tools/configure-desktop.sh --check

# --- 6. Build the ISO (⚠️ MANUAL, ROOT, ARCH HOST ONLY) ---------------------
sudo ./tools/bootstrap.sh --iso-only

# --- 7. Apply caches / presets / verify Lua INSIDE the airootfs --------------
#        (⚠️ MANUAL, ROOT; does NOT start SDDM or Hyprland)
sudo ./tools/configure-desktop.sh --apply
#   fc-cache -f
#   update-desktop-database /usr/share/applications
#   systemctl preset-all                 # enables sddm.service
#   Hyprland --verify-config -c /etc/skel/.config/hypr/hyprland.lua

# --- 8. Desktop smoke test on a real host / VM (⚠️ MANUAL) ------------------
sddm-greeter --test-mode --theme /usr/share/sddm/themes/ar0x
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
hyprctl configerrors            # must be empty inside a running session
```

`configure-desktop.sh --apply` deliberately **does not** run `sysctl --system`
or `nft -f` (Phase 5's host-kernel safety rule), and **does not** start SDDM —
starting a display manager inside a chroot would be a no-op at best and a
broken build at worst.

---

## 3. Full path mapping (canonical → installed)

`config/desktop/<tool>/**` is the **human-edited** source.
`config/desktop/skel/.config/<tool>/**` and everything under `archiso/airootfs/`
are **generated copies** — never edit them by hand; run `--sync`.

| Canonical source (absolute) | Installed target (absolute) |
|---|---|
| `/home/user/ar0xOS/config/desktop/hypr/hyprland.lua` | `/etc/skel/.config/hypr/hyprland.lua` |
| `/home/user/ar0xOS/config/desktop/hypr/lua/*.lua` (10) | `/etc/skel/.config/hypr/lua/*.lua` |
| `/home/user/ar0xOS/config/desktop/hypr/hyprpaper.conf` | `/etc/skel/.config/hypr/hyprpaper.conf` |
| `/home/user/ar0xOS/config/desktop/hypr/hyprlock.conf` | `/etc/skel/.config/hypr/hyprlock.conf` |
| `/home/user/ar0xOS/config/desktop/hypr/hypridle.conf` | `/etc/skel/.config/hypr/hypridle.conf` |
| `/home/user/ar0xOS/config/desktop/waybar/config.jsonc` | `/etc/skel/.config/waybar/config.jsonc` |
| `/home/user/ar0xOS/config/desktop/waybar/style.css` | `/etc/skel/.config/waybar/style.css` |
| `/home/user/ar0xOS/config/desktop/gtk-3.0/settings.ini` | `/etc/skel/.config/gtk-3.0/settings.ini` |
| `/home/user/ar0xOS/config/desktop/gtk-3.0/gtk.css` | `/etc/skel/.config/gtk-3.0/gtk.css` |
| `/home/user/ar0xOS/config/desktop/gtk-4.0/settings.ini` | `/etc/skel/.config/gtk-4.0/settings.ini` |
| `/home/user/ar0xOS/config/desktop/gtk-4.0/gtk.css` | `/etc/skel/.config/gtk-4.0/gtk.css` |
| `/home/user/ar0xOS/config/desktop/qt5ct/qt5ct.conf` | `/etc/skel/.config/qt5ct/qt5ct.conf` |
| `/home/user/ar0xOS/config/desktop/qt6ct/qt6ct.conf` | `/etc/skel/.config/qt6ct/qt6ct.conf` |
| `/home/user/ar0xOS/config/desktop/fontconfig/conf.d/99-ar0x-fonts.conf` | `/etc/skel/.config/fontconfig/conf.d/99-ar0x-fonts.conf` |
| `/home/user/ar0xOS/config/desktop/kitty/kitty.conf` | `/etc/skel/.config/kitty/kitty.conf` |
| `/home/user/ar0xOS/config/desktop/wofi/{config,style.css}` | `/etc/skel/.config/wofi/{config,style.css}` |
| `/home/user/ar0xOS/config/desktop/mako/config` | `/etc/skel/.config/mako/config` |
| `/home/user/ar0xOS/config/desktop/xdg/mimeapps.list` | `/etc/skel/.config/mimeapps.list` |
| `/home/user/ar0xOS/config/desktop/etc/sddm.conf.d/10-ar0x.conf` | `/etc/sddm.conf.d/10-ar0x.conf` |
| `/home/user/ar0xOS/config/desktop/etc/environment.d/20-ar0x-desktop.conf` | `/etc/environment.d/20-ar0x-desktop.conf` |
| `/home/user/ar0xOS/config/desktop/etc/xdg/user-dirs.defaults` | `/etc/xdg/user-dirs.defaults` |
| `/home/user/ar0xOS/config/desktop/skel/.zshrc` | `/etc/skel/.zshrc` |
| `/home/user/ar0xOS/config/desktop/skel/.zshenv` | `/etc/skel/.zshenv` |
| `/home/user/ar0xOS/config/desktop/skel/.zprofile` | `/etc/skel/.zprofile` |
| `/home/user/ar0xOS/config/desktop/skel/.profile` | `/etc/skel/.profile` |
| `/home/user/ar0xOS/config/desktop/skel/.bashrc` | `/etc/skel/.bashrc` |
| `/home/user/ar0xOS/config/desktop/skel/.config/starship.toml` | `/etc/skel/.config/starship.toml` |
| `/home/user/ar0xOS/config/desktop/skel/.config/git/config` | `/etc/skel/.config/git/config` |
| `/home/user/ar0xOS/config/desktop/skel/.config/fastfetch/config.jsonc` | `/etc/skel/.config/fastfetch/config.jsonc` |
| `/home/user/ar0xOS/config/desktop/skel/.config/user-dirs.dirs` | `/etc/skel/.config/user-dirs.dirs` |
| `/home/user/ar0xOS/config/desktop/skel/.config/xdg-desktop-portal/hyprland-portals.conf` | `/etc/skel/.config/xdg-desktop-portal/hyprland-portals.conf` |
| `/home/user/ar0xOS/config/desktop/skel/.icons/default/index.theme` | `/etc/skel/.icons/default/index.theme` |
| `/home/user/ar0xOS/assets/sddm/ar0x/{Main.qml,metadata.desktop,theme.conf,background.png}` | `/usr/share/sddm/themes/ar0x/` |
| `/home/user/ar0xOS/assets/wallpapers/ar0x-{neon-grid,void,circuit}.png` | `/usr/share/backgrounds/ar0x/` |

**Also changed in Phase 6:** `config/packages.x86_64` (+37 packages) and
`config/system/systemd/system-preset/50-ar0x.preset` (+`enable sddm.service`,
the single owner of unit state). `tools/bootstrap.sh` now overlays
`config/desktop/etc/**` into the disposable staged profile's `/etc/**`.

---

## 4. Key configs reproduced (with the reasoning)

### 4.1 `/etc/skel/.config/hypr/hyprland.lua`

```lua
require("lua.palette")
require("lua.programs")
require("lua.env")
require("lua.monitors")
require("lua.looknfeel")
require("lua.animations")
require("lua.input")
require("lua.keybinds")
require("lua.rules")
require("lua.autostart")
```

Module resolution in 0.57 is `~/.config/hypr/?.lua`, so `require("lua.palette")`
loads `~/.config/hypr/lua/palette.lua`. Each `require` is its own protected Lua
scope: an error in one module does not kill the others. Shared values are
returned as tables (`local c = require("lua.palette")`) rather than relying on
globals. **Only `hl.*` API calls present in Hyprland 0.57's official
`example/hyprland.lua` are used** — no invented options, so
`Hyprland --verify-config` cannot fail on a made-up key.

### 4.2 `/etc/skel/.config/hypr/lua/env.lua` (the important variables)

```lua
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct")  -- COLON list covers Qt5 AND Qt6
hl.env("QT_QPA_PLATFORM", "wayland;xcb")       -- SEMICOLON list of platform plugins
hl.env("XCURSOR_THEME", "Adwaita")             -- Phase 7 placeholder, RISK-040
hl.env("GTK_THEME", "Adwaita-dark")            -- + gtk-4.0/gtk.css @define-color
-- GDK_BACKEND is deliberately ABSENT (RISK-039)
```

### 4.3 `/etc/skel/.config/gtk-4.0/gtk.css`

GTK4 ignores `gtk-theme-name`. libadwaita hard-codes Adwaita and reads
`@define-color` variables **only at process startup**. ar0x therefore defines
all 20 libadwaita variables (`window_bg_color`, `accent_bg_color`,
`destructive_bg_color`, …) from the palette. Restart D-Bus-activated apps
after a palette change; closing the window is not enough. **Tradeoff:** ar0x is
dark-only by design — there is no light/dark switch in v0.1 (RISK-042).

### 4.4 Hyprland 0.57 DPMS in `/etc/skel/.config/hypr/hypridle.conf`

```ini
on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
on-resume  = hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
```

The legacy `hyprctl dispatch dpms off` was removed in 0.57; using it would
silently leave the screen on. The 30-minute `systemctl suspend` listener is
**omitted on the LIVE ISO** — a suspended VM is a support nightmare.

### 4.5 `/etc/sddm.conf.d/10-ar0x.conf`

```ini
[General]
InputMethod=
[Theme]
Current=ar0x
```

SDDM 0.21 enables a Qt on-screen keyboard by default; `InputMethod=` disables
it so it does not draw over the login form. The greeter runs on Xorg (Arch's
`sddm` hard-depends on `xorg-server`) while the session is Wayland.

---

## 5. Decisions & tradeoffs

| # | Decision | Chosen | Rejected / why |
|---|---|---|---|
| 1 | Config language | **Lua** (`hyprland.lua` + 10 modules) | `hyprland.conf` removed in 0.57; no converter exists (RISK-002) |
| 2 | Lua module layout | `require("lua.*")`, shared tables returned | Globals across protected scopes are fragile; a single 600-line file is unreviewable |
| 3 | Monitors | one wildcard `mode="preferred"`, `scale="auto"` | Per-machine monitor files break the live ISO on laptops/VMs/QEMU |
| 4 | Blur | `size=4, passes=2, vibrancy=0.18` | 4 passes halves FPS under QEMU/llvmpipe (RISK-041); 0 kills the vibe |
| 5 | Animation speed | modest (global 8, windows 4) | Aggressive springs feel broken on software rendering |
| 6 | Display manager | **SDDM 0.21 Qt6** | GDM pulls GNOME/libadwaita (rejected in Phase 1); LightDM greeters are GTK/X11-centric |
| 7 | SDDM QML | only `QtQuick` + `SddmComponents 2.0` | `QtGraphicalEffects`/`Qt5Compat` break the Qt6 greeter; no custom QML modules |
| 8 | GTK3 | `Adwaita-dark` + `gtk.css` overrides | A full ar0x GTK3 theme engine is Phase 8's `ar0x-theme` package; a hand-rolled theme risks unstyled widgets |
| 9 | GTK4 | `@define-color` overrides + `GTK_THEME` | libadwaita has no theming API by design (RISK-042) |
| 10 | Qt | `qt5ct:qt6ct`, `style=Fusion`, packaged `darker.conf` | Kvantum + AUR themes break reproducibility (RISK-004) |
| 11 | Icons | `papirus-icon-theme` (`[extra]`, 111 MB installed) | AUR-only icon packs cannot be pinned to the frozen snapshot |
| 12 | Cursor | `Adwaita` placeholder | Bibata/Capitaine are AUR-only; ar0x hyprcursor theme is Phase 7 (RISK-040) |
| 13 | Fonts | Inter + JetBrains Mono Nerd + Noto | Nerd glyphs are required by the Waybar icons and starship prompt |
| 14 | Wallpapers | generated 4K PNG placeholders at Phase 1 paths | Committing large AI art has licensing + ISO-size risk (2.2 GB gate) |
| 15 | `GDK_BACKEND` | **NOT set globally** | Breaks XWayland GTK apps (Phase 5 / RISK-039) |
| 16 | Portal | XDPH `default = hyprland;gtk`, FileChooser = gtk | XDPH implements no file picker of its own |
| 17 | Shell | zsh interactive, **bash for all scripts** | Phase 1 preference; `tools/*.sh` all start `#!/bin/bash` |
| 18 | Idle/suspend | lock at 5 min, DPMS off at 5.5 min, **no suspend** | Live ISO / VM safety |
| 19 | Polkit agent | `polkit-gnome` (official `[extra]`) | `hyprpolkitagent` is AUR-only |
| 20 | Session state | `enable sddm.service` in the ONE Phase 5 preset | Two owners of unit state drift apart |

---

## 6. Wallpaper placeholder paths & sources

| Path in repo | Installed path | Size | Used by |
|---|---|---|---|
| `assets/wallpapers/ar0x-neon-grid.png` | `/usr/share/backgrounds/ar0x/ar0x-neon-grid.png` | 3840×2160 | `hyprpaper.conf` (default desktop) |
| `assets/wallpapers/ar0x-void.png` | `/usr/share/backgrounds/ar0x/ar0x-void.png` | 3840×2160 | optional low-distraction wallpaper |
| `assets/wallpapers/ar0x-circuit.png` | `/usr/share/backgrounds/ar0x/ar0x-circuit.png` | 3840×2160 | `hyprlock.conf` (lock screen) |
| `assets/sddm/ar0x/background.png` | `/usr/share/sddm/themes/ar0x/background.png` | 1920×1080 | SDDM `theme.conf` |
| `assets/grub-theme/ar0x/background.png` | `/boot/grub/themes/ar0x/background.png` | 1024×768 | Phase 4 GRUB theme (unchanged) |

**Sources:** generated in-house by `tools/gen-desktop-assets.sh` from the
`config/versions.env` palette — cyan perspective grid, magenta horizon glow,
circuit traces, no third-party assets, no fonts, no network. Provenance is the
generator source; ar0x-authored artwork is CC BY-SA 4.0. Final Phase 7 art
sources (Inkscape/Blender from `assets/logo/ar0x-logo.svg`, CC0 geometry
textures from ambientCG / Poly Haven, CC0 neon photography only as a layer)
are recorded in `assets/wallpapers/PLACEHOLDERS.md`. Every final PNG must stay
under 4 MB and ship a `LICENSE`.

---

## 7. Manual-intervention register

| # | What | Why it cannot run here | Exact command on an Arch host |
|---|---|---|---|
| 1 | `Hyprland --verify-config` | binary not installed | `sudo ./tools/configure-desktop.sh --apply` (runs it in the chroot) |
| 2 | `sddm-greeter --test-mode` | needs a display + Qt6 greeter | `sddm-greeter --test-mode --theme /usr/share/sddm/themes/ar0x` |
| 3 | QEMU UEFI + BIOS Wayland session | no KVM / no root / no ISO yet | Phase 11 QEMU commands (`docs/TESTING_CHECKLIST.md`) |
| 4 | `fc-cache -f`, `update-desktop-database`, `systemctl preset-all` | root + real airootfs | `sudo ./tools/configure-desktop.sh --apply` |
| 5 | `hyprctl configerrors` / WiFi / audio / GPU checks | needs a live session | Phase 11 boot/install checklist |
| 6 | Final artwork + ar0x hyprcursor theme | Phase 7 scope | replace PNGs at the same paths, then `--sync` |
| 7 | `[ar0x]` repo publishing for HARD pins | Phase 9/12 | `repo-add` + GPG signing (RISK-036) |
| 8 | `pacman -Si` mirror verification | no live Arch mirror in sandbox | verify `0.57.1` pins on the build host before Phase 9 |

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Hyprland refuses to start; popup about config error | Stray `hyprland.conf`, or a `require()` target missing | `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`; `hyprctl configerrors`; run `./tools/configure-desktop.sh --sync` |
| Emergency binds `SUPER+Q/R/M` appear | A Lua error occurred **before** binds were registered | Check `~/.config/hypr/lua/*.lua`; each module is isolated, so bisect with `--verify-config` |
| Qt apps are light / unstyled | `QT_QPA_PLATFORMTHEME` not imported into the user manager | `systemctl --user import-environment QT_QPA_PLATFORMTHEME`; `autostart.lua` already does this |
| GTK4/libadwaita app stays Adwaita | libadwaita reads CSS only at process start | Restart the D-Bus-activated daemon; `GTK_THEME=Adwaita-dark` must be set |
| Black desktop, no wallpaper | `hyprpaper` not started or PNG missing | `pgrep -x hyprpaper`; check `/usr/share/backgrounds/ar0x/`; regenerate art |
| SDDM shows the embedded theme | `[Theme] Current=ar0x` not applied | Check `/etc/sddm.conf.d/10-ar0x.conf`; `sddm --test-mode` |
| SDDM QML errors on Qt6 | Qt5-only imports | `--check` fails on `QtGraphicalEffects`/`Qt5Compat` imports |
| Screen never blanks; keys stuck | Legacy `hyprctl dispatch dpms off` | Use `hl.dsp.dpms({ action = "disable" })` (0.57) |
| Two DHCP clients | `systemd-networkd` also enabled | `50-ar0x.preset` disables it (Phase 5 / RISK-035) |
| `hyprlock` exits immediately | Missing `hyprlock.conf` | Ship `/etc/skel/.config/hypr/hyprlock.conf`; it is mandatory |
| `--check` reports stale copies | Canonical edited but `--sync` not run | `./tools/configure-desktop.sh --sync` |

---

## 9. Phase 6 risks

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| RISK-002 | HIGH | Hyprland 0.57 Lua-only, no converter | Zero `hyprland.conf` files; two independent validators fail on one |
| RISK-038 | MEDIUM | SDDM greeter is X11 (xorg-server dep) while session is Wayland | Documented; QML restricted to Qt6-safe imports; no `DisplayServer=wayland` |
| RISK-039 | MEDIUM | Global `GDK_BACKEND` breaks XWayland GTK apps | Absent from `env.lua` and `environment.d`; `--check` fails if reintroduced |
| RISK-040 | LOW | Placeholder cursor + generated wallpapers | Same paths used by Phase 7; no config churn |
| RISK-041 | MEDIUM | Blur/animations look broken under llvmpipe/QEMU | Conservative blur (2 passes) and animation speeds; QEMU QA is manual |
| RISK-042 | MEDIUM | libadwaita hard-codes Adwaita; GTK4 theming incomplete | `GTK_THEME` + 20 `@define-color` overrides; documented as upstream design |
| RISK-043 | **HIGH** | QML theme + Wayland session never rendered here | `--check` does structural validation only; §7 manual test matrix is mandatory |

Existing RISK-001…037 remain active. Phase 6 adds 37 packages to
`config/packages.x86_64`; the 2.2 GiB ISO gate is re-checked in Phase 11.

---

## 10. Verification actually performed in the sandbox

```
bash -n tools/*.sh tools/lib/*.sh                 ✅ all scripts
tools/gen-desktop-assets.sh                      ✅ 4 PNGs, signature + dimensions
tools/configure-desktop.sh --sync                ✅ byte-idempotent (3 passes)
tools/configure-desktop.sh --check               ✅ read-only, no root
tools/validate-versions.sh                      ✅ 0 warnings, Phase 6 gates
tools/bootstrap.sh --check                      ✅
tools/build-kernel.sh --check / --self-test     ✅
tools/setup-build-env.sh --check                ✅
tools/configure-system.sh --check               ✅
```

`--check` additionally validates: 42 canonical config files, 8 theme/art files, 3 driver/doc files,
**zero** `hyprland.conf`, balanced Lua delimiters in all 11 modules, every
`require()` target resolving, both JSONC files parsing as strict JSON after
comment stripping, well-formed fontconfig XML, balanced QML delimiters, the
SDDM Qt6 metadata contract, all 8 palette pins equal across `versions.env` /
`lua/palette.lua` / `Main.qml`, no global `GDK_BACKEND`, the Qt5+Qt6 platform
theme, `enable sddm.service`, wallpaper references resolving to real PNGs, 37
required packages, and every generated copy byte-identical to its source.

**NOT performed here (no root / no display / no binaries):** `mkarchiso`,
`pacstrap`, `arch-chroot`, `fc-cache`, `update-desktop-database`,
`systemctl preset-all`, `Hyprland --verify-config`, `sddm-greeter --test-mode`,
`sddm --test-mode`, QEMU UEFI/BIOS boot, WiFi/audio/GPU QA, `pacman -Si`,
`shellcheck`, and any live Wayland session. Do not read the ✅ list above as a
claim that a desktop was rendered.
