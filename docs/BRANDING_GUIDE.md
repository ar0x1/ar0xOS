# ar0x Branding Guide — Phase 7 (COMPLETE)

**Distribution:** ar0x `0.1.0` "Neon Root" · Developer Edition
**Base:** Arch Linux · systemd · glibc · Hyprland / Wayland · GRUB · linux-lts `6.18.59-1`
**Status:** ✅ COMPLETE — identity, ASCII/terminal logos, SVG masters, palette, icon,
XCursor theme, GRUB/Plymouth/syslinux final art, generated mirrors, validation.
**Licence:** CC BY-SA 4.0 for brand assets (`assets/logo/LICENSE`).

> ⚠️ **RISK-044 (HIGH):** this sandbox has **no root, no display, no Wayland
> compositor, no X server, no GRUB gfxmenu, no Plymouth daemon and no QEMU/KVM**.
> Everything below was validated **structurally** — every SVG is parsed as XML,
> every PNG signature/IHDR is checked, every Xcursor file is parsed back from
> disk, every JSONC is parsed, every shell snippet is `bash -n`'d. **No image was
> rendered on screen and no live login was tested.** §8 lists exactly what was
> and was not verified.

---

## 1. Deliverables (complete files, absolute installed paths)

### 1.1 `/etc` identity

| Canonical source | Installed path | Owner |
|---|---|---|
| `/home/user/ar0xOS/config/branding/os-release` | `/etc/os-release` **and** `/usr/lib/os-release` | `os-release(5)` |
| `/home/user/ar0xOS/config/branding/lsb-release` | `/etc/lsb-release` | `lsb_release -a` |
| `/home/user/ar0xOS/config/branding/issue` | `/etc/issue` | `agetty(8)` |
| `/home/user/ar0xOS/config/branding/issue.net` | `/etc/issue.net` | `sshd` `Banner` |
| `/home/user/ar0xOS/config/branding/motd` | `/etc/motd` | `pam_motd` |
| `/home/user/ar0xOS/config/branding/palette.conf` | `/usr/share/ar0x/palette.conf` | scripts / Phase 8 |

`os-release` is written to **two** places on purpose. Arch's `filesystem`
package installs `/etc/os-release` as a **symlink to `/usr/lib/os-release`**;
writing only `/etc/os-release` follows the symlink on some builds and is
silently reverted to "Arch Linux" on others. Both files are byte-identical and
`tools/configure-branding.sh --check` enforces it.

`/etc/issue` uses **only** documented `agetty(8)` escapes:
`\s` (OS name), `\m` (machine), `\r` (kernel release), `\n` (nodename),
`\l` (tty line), `\d` (date), `\t` (time). No ASCII backslash art is used there,
because an unknown `\X` is printed literally by some util-linux builds and
stripped by others. `/etc/issue.net` is **plain text** — sshd does **not** expand
agetty escapes. The full ASCII logo is in `/etc/motd`.

### 1.2 ASCII / terminal logos

| Canonical source | Installed path | Consumer |
|---|---|---|
| `config/branding/ascii/ar0x-ascii.txt` | `/usr/share/ar0x/branding/ar0x-ascii.txt` | neofetch `image_source`, `/etc/motd` |
| `config/branding/ascii/ar0x-fastfetch.txt` | `/usr/share/ar0x/branding/ar0x-fastfetch.txt` | fastfetch `logo.type = "file"` |
| `config/branding/ascii/ar0x-screenfetch.sh` | `/usr/share/ar0x/branding/ar0x-screenfetch.sh` | `screenfetch -a PATH` |

The plain logo is **8 lines, ≤48 columns, pure ASCII, no tabs**:

```
        .--------------------------------.
       /    /\        .--------------.    \
      /    /  \       |  >_  ar0x   |     \
     |    / /\ \      '--------------' []  |
     |    \ \/ /                          |
     |     \  /    N E O N   R O O T      |
      \     \/     0 . 1 . 0  /  x86_64  /
       '--------------------------------'
```

`ar0x-fastfetch.txt` is the same art with `$1` (cyan), `$2` (magenta), `$3`
(lime) placeholders. fastfetch's `file` logo type expands `$1`–`$9` from
`logo.color`; `file-raw` would print them literally. Verified against upstream
`fastfetch/src/logo/ascii/a/*.txt`, which use exactly this syntax.
**`--check` proves `re.sub(r'\$[1-9]', '', tagged) == plain` byte for byte.**

`ar0x-screenfetch.sh` is a file that screenFetch **sources** (it is not
standalone). Verified against screenFetch `3.9.9` `asciiText()`, which does
`source "$art"` for the `custom` case and prints
`printf "${fulloutput[i]}$c0\n" "${out_array[0]}"`. It therefore defines
`startline`, `logowidth`, `c1/c2/c3`, `labelcolor`, `textcolor`, and a
`fulloutput` array of **8 printf format strings, each with exactly one `%s`**.

> ⚠️ **Deliberate exception to the repo-wide strict-mode rule:** this sourced
> snippet must **not** contain `set -euo pipefail`. Strict mode would leak into
> screenFetch's own process and abort it on its many unset variables.
> `tools/validate-versions.sh` carries an explicit exemption for
> `*/config/branding/ascii/*.sh`.

### 1.3 Fetch-tool configs

| Canonical source | Installed path |
|---|---|
| `config/branding/fastfetch/config.jsonc` | `/etc/skel/.config/fastfetch/config.jsonc` |
| `config/branding/neofetch/config.conf` | `/etc/skel/.config/neofetch/config.conf` |
| `config/branding/screenfetch/ar0x-screenfetch.sh` | `/usr/local/bin/ar0x-screenfetch` (`0755`) |

Every `/etc/skel/.config/{fastfetch,neofetch}/` file is a **generated mirror**
of `config/branding/`; `config/desktop/skel/.config/{fastfetch,neofetch}/` holds
two more generated Phase 6-tree copies. Edit the canonical only.
`tools/configure-branding.sh --sync` writes all six (3 locations × 2 configs).

**RISK-010 decision:** `neofetch` was **removed from Arch `[extra]`** (upstream
`dylanaraps/neofetch` archived in 2021) and is **AUR-only**. ar0x does not ship
AUR packages in the ISO, so `neofetch` is **not** in `config/packages.x86_64`.
Its config **is** shipped so `yay -S neofetch` or Phase 8's `ar0x-welcome`
"extras" picks up the branded logo immediately. `screenfetch 3.9.9-1` **is** an
official `[extra]` package and **is** on the ISO; `fastfetch` remains the default.

### 1.4 SVG masters and the logo icon

| File | `viewBox` | Native size | Purpose |
|---|---|---|---|
| `assets/logo/ar0x-logo.svg` | `0 0 512 512` | 512×512 px | **MASTER logomark**, transparent background |
| `assets/logo/ar0x-logo-mono.svg` | `0 0 512 512` | 512×512 px | single-colour `currentColor` variant |
| `assets/logo/ar0x-wordmark.svg` | `0 0 1024 256` | 1024×256 px | horizontal lockup (mark + `ar0x` + `NEON ROOT / DEVELOPER EDITION`) |
| `assets/icons/ar0x-logo.svg` | `0 0 512 512` | scalable | icon-theme variant on a `#07090F` rounded-square plate |
| `assets/logo/ar0x-logo-256.png` | — | 256×256 px | raster fallback (generated) |
| `assets/logo/ar0x-logo-512.png` | — | 512×512 px | raster fallback (generated) |

`/etc/os-release` declares `LOGO=ar0x-logo` (os-release(5), systemd ≥ 252).
`tools/configure-branding.sh --sync` installs the icon at
`/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg`, which is exactly where
freedesktop icon-theme lookup resolves that name. The plate is required because
icon themes can be **light**; the transparent master would lose its cyan frame
on white.

> **Manual intervention (print only):** `ar0x-wordmark.svg` uses live `<text>`
> in **Inter** (`inter-font`, already on the ISO). For print, signage or any
> machine without Inter, open it in Inkscape and run *Path → Object to Path* on
> the two `<text>` nodes. The SVG stays the master either way.

### 1.5 Exact vector geometry (512×512 viewBox)

| Element | Coordinates / attributes | Colour |
|---|---|---|
| Octagonal frame `<polygon>` | `136,24 376,24 488,136 488,376 376,488 136,488 24,376 24,136`, `fill="none"`, `stroke-width="28"`, `stroke-linejoin="miter"` | `#00E5FF` |
| Root chevron `<polyline>` | `150,170 238,256 150,342`, `fill="none"`, `stroke-width="40"`, `stroke-linecap="butt"` | `#00E5FF` |
| Prompt underscore `<line>` | `x1=272 y1=342 x2=362 y2=342`, `stroke-width="40"` | `#FF2E88` |
| Status node `<rect>` | `x=322 y=170 width=48 height=48` | `#A8FF60` |

`tools/lib/ar0x_logo.py` holds these numbers as constants and implements the
same geometry as a deterministic raster function.
`tools/configure-branding.sh --check` **parses the SVG XML and asserts the
octagon, chevron, underscore, node rect and both stroke widths equal the
module constants**. A "creative tweak" to one file alone fails the build.

### 1.6 ar0x hex palette (ADR-015, single source of truth)

| Token | Hex | RGB | ANSI (24-bit) | Role / ratio |
|---|---|---|---|---|
| VOID | `#07090F` | `7, 9, 15` | `0;38;2;7;9;15` | background / negative space, ~60% |
| SURFACE | `#11151F` | `17, 21, 31` | `0;38;2;17;21;31` | panels, cards, elevated surfaces |
| CYAN | `#00E5FF` | `0, 229, 255` | `0;38;2;0;229;255` | **primary** accent, links, focus, logomark frame |
| MAGENTA | `#FF2E88` | `255, 46, 136` | `0;38;2;255;46;136` | secondary accent, prompt underscore |
| LIME | `#A8FF60` | `168, 255, 96` | `0;38;2;168;255;96` | success / active node, **<5%** of a layout |
| TEXT | `#D7E0EE` | `215, 224, 238` | `0;38;2;215;224;238` | primary text on VOID/SURFACE |
| MUTED | `#6B7891` | `107, 120, 145` | `0;38;2;107;120;145` | secondary text, labels, disabled |
| ALERT | `#FF5C57` | `255, 92, 87` | `0;38;2;255;92;87` | errors and destructive actions **only** |

`ANSI_COLOR="0;38;2;0;229;255"` in `/etc/os-release` is the truecolor cyan.

**Parity chain enforced automatically:**
`config/versions.env` (8 `AR0X_*` pins) → `config/branding/palette.conf`
(8 `AR0X_BRAND_*` pins) → `assets/logo/*.svg` → `tools/lib/ar0x_logo.py` →
boot art → `config/desktop/hypr/lua/palette.lua` → `assets/sddm/ar0x/Main.qml`
→ `assets/grub-theme/ar0x/theme.txt`. Both
`tools/configure-branding.sh --check` and `tools/validate-versions.sh` fail on
any drift.

Terminal fetch tools use the **nearest palette names** (`cyan`, `magenta`,
`green`) because fastfetch `logo.color` maps to terminal colours, not arbitrary
hex. The SVGs, PNGs, XCursor binaries and CSS/QML use the **exact 24-bit hex**.

### 1.7 Typography, clear space, minimum size

| Rule | Value |
|---|---|
| Display / wordmark | **Inter**, weight `700`, tracking `-4` |
| Terminal / mono | **JetBrains Mono Nerd** (`ttf-jetbrains-mono-nerd`) |
| Caption / label | Inter `600`, tracking `+9` |
| Clear space around mark | **1/8 of mark width** on every side (64 px at 512 px) |
| Minimum logomark | **24 px** (below that the lime node disappears) |
| Minimum wordmark | **120 px wide** |
| Background | VOID `#07090F` or SURFACE `#11151F`. Never white, never a photo. |

**Do:** place the mark on VOID/SURFACE; keep the 1/8 clear space; use CYAN for
the frame and chevron, MAGENTA for the underscore, LIME only for the node;
use `ar0x-logo-mono.svg` with `color:#07090F` on light media.
**Don't:** recolor, rotate, stretch, add gradients/glows/drop shadows, outline
the octagon differently, put text inside the frame, set the mark on a light
background, or use LIME/ALERT as primary accents.

### 1.8 Cursor theme (RISK-040 closed)

`config/desktop/hypr/lua/env.lua`, `config/desktop/etc/environment.d/20-ar0x-desktop.conf`
and `/etc/skel/.icons/default/index.theme` now all point at **`ar0x-cursors`**.
`/usr/share/icons/ar0x-cursors/` contains:

- `index.theme`, `cursor.theme` — canonical, `Inherits=Adwaita` (safety net)
- `cursors/left_ptr`, `text`, `watch`, `pointer`, `crosshair` — real **Xcursor
  binary** files, each with **3 frames at nominal sizes 24 / 32 / 48**
- 12 standard X11 alias symlinks (`default`, `top_left_arrow`, `arrow`,
  `xterm`, `ibeam`, `wait`, `left_ptr_watch`, `progress`, `hand2`, `hand`,
  `cross`, `cross_reverse`)

⚠️ **Single binary copy:** `tools/gen-branding-assets.sh` writes the Xcursor
binaries AND alias symlinks DIRECTLY into the tracked profile at
`archiso/airootfs/usr/share/icons/ar0x-cursors/cursors/` (they are never
duplicated under `assets/`). Only `index.theme`, `cursor.theme` and `README.md`
are canonical text sources in `assets/cursors/ar0x-cursors/`. Re-run the
generator after any cursor change; `./tools/configure-branding.sh --check`
parses all 5 binaries back and asserts all 12 aliases exist.

Colours: CYAN body, MAGENTA tip/hand, VOID 1-cell outline, fully transparent
elsewhere. Generated by `tools/lib/ar0x_xcursor.py`, which writes the documented
`Xcur` format (magic `Xcur`, `header=16`, `version=1`, TOC, `headerSize=36`
image chunks, packed ARGB) and **parses every file back** in the same run.

> **Tradeoff (ADR-022):** a compiled `hyprcursor` theme needs `hyprcursor-util`
> plus SVG sources; it is not available on this build host, and a hand-authored
> `manifest.hl` without compiled cursors is not loadable. Hyprland, XWayland,
> GTK3/GTK4 and Qt all consume ordinary XCursor themes from
> `/usr/share/icons/<theme>/cursors/`, so the standard format is correct for
> v0.1. A compiled hyprcursor variant is a **v0.2** roadmap item.

### 1.9 Boot art (Phase 4 assets finalised in place)

The Phase 4 placeholder bitmap wordmark is **gone**. `tools/gen-theme-assets.sh`
now draws the official 512×512 logomark from `tools/lib/ar0x_logo.py` into all
three boot surfaces, at the **same paths and dimensions** so
`tools/build-kernel.sh --check` contracts still hold:

| File | Size | Content |
|---|---|---|
| `/usr/share/grub/themes/ar0x/background.png` (+ ISO `/boot/grub/themes/ar0x/`) | 1024×768 | logomark 186 px at y=20, `ar0x` caption at y=218, grid, accent rule |
| `/usr/share/plymouth/themes/ar0x/logo.png` | 320×80 | horizontal lockup: 64 px mark + `ar0x` wordmark + magenta rule |
| `/usr/share/plymouth/themes/ar0x/progress-{0..20}.png` | 400×6 | 20-segment cyan/text boot bar |
| `/boot/syslinux/splash.png` | 640×480 | logomark 140 px + caption + grid |

`assets/grub-theme/ar0x/theme.txt` was **re-laid out** so the menu never
overlaps the logo: the two Phase 4 header labels were removed, `boot_menu`
moved to `top = 34%`, `height = 36%`, `progress_bar` stays at `78%`, footer at
`84%`. The theme is still deliberately **fontless** — archiso 92 runs
`grub-mkstandalone --themes=""`; `archiso/grub/grub.cfg` has a guarded
`loadfont ar0x-16.pf2` that activates only if a font is ever shipped.

---

## 2. Exact commands (copy-pasteable)

```bash
cd /home/user/ar0xOS

# 1. Generate all BINARY brand assets (2 logo PNGs + 5 Xcursor files + aliases)
./tools/gen-branding-assets.sh

# 2. Regenerate GRUB / Plymouth / syslinux boot art with the official logomark
./tools/gen-theme-assets.sh

# 3. Validate (read-only, no root, no writes)
./tools/configure-branding.sh --check

# 4. Install canonical -> generated mirrors in archiso/ and config/desktop/skel/
./tools/configure-branding.sh --sync
./tools/build-kernel.sh --sync          # boot art -> archiso profile
./tools/configure-desktop.sh --sync     # skel + env + SDDM -> archiso profile
./tools/bootstrap.sh --sync             # packages.x86_64 -> archiso profile
./tools/bootstrap.sh --check

# 5. Full validator sweep
bash -n tools/*.sh tools/lib/*.sh
./tools/validate-versions.sh
./tools/setup-build-env.sh --check
./tools/configure-system.sh --check
./tools/build-kernel.sh --check
./tools/configure-desktop.sh --check
./tools/configure-branding.sh --check

# 6. On a REAL Arch host (root, ~40 GiB, loop devices): build + stage
sudo ./tools/bootstrap.sh --iso-only

# 7. ⚠️ MANUAL, ROOT, FINISHED AIROOTFS ONLY (see §5)
sudo ./tools/configure-branding.sh --apply
```

Useful live checks inside the booted system:

```bash
. /etc/os-release; echo "$PRETTY_NAME  |  $ID  |  $LOGO"
cat /etc/issue
fastfetch
ar0x-screenfetch                       # wrapper == screenfetch -a <art>
screenfetch -a /usr/share/ar0x/branding/ar0x-screenfetch.sh
lsb_release -a                          # optional: pacman -S lsb-release
```

---

## 3. Canonical → installed mapping (single-owner rule)

```
config/branding/os-release ───────────────► /etc/os-release
                          └──────────────► /usr/lib/os-release
config/branding/lsb-release ─────────────► /etc/lsb-release
config/branding/issue ───────────────────► /etc/issue
config/branding/issue.net ───────────────► /etc/issue.net
config/branding/motd ────────────────────► /etc/motd
config/branding/palette.conf ────────────► /usr/share/ar0x/palette.conf
config/branding/ascii/* ─────────────────► /usr/share/ar0x/branding/*
config/branding/fastfetch/config.jsonc ──► /etc/skel/.config/fastfetch/config.jsonc
config/branding/neofetch/config.conf ────► /etc/skel/.config/neofetch/config.conf
config/branding/screenfetch/*.sh ────────► /usr/local/bin/ar0x-screenfetch
assets/logo/*.svg + LICENSE ─────────────► /usr/share/ar0x/logo/*
assets/icons/ar0x-logo.svg ──────────────► /usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg
assets/cursors/ar0x-cursors/*.theme ─────► /usr/share/icons/ar0x-cursors/*.theme
tools/gen-branding-assets.sh ────────────► /usr/share/icons/ar0x-cursors/cursors/*
assets/{grub-theme,plymouth,syslinux}/ ──► /usr/share/{grub,plymouth}/themes/ar0x/ + ISO /boot/
```

`tools/bootstrap.sh` **also** overlays `config/branding/**` into its disposable
`STAGE` at `/opt/ar0x-build/profile/`, so `mkarchiso` never writes back into the
Git checkout. `tools/configure-branding.sh --sync` writes the same bytes into
the checked-in `archiso/airootfs/**` mirrors. `--check` `cmp -s` every pair.

> ⚠️ GRUB theme art must **NOT** be staged under `<airootfs>/boot`:
> `mkarchiso::_cleanup_pacstrap_dir` deletes everything there. It lives in
> `/usr/share/grub/themes/ar0x/` in the airootfs and in `<profile>/grub/` on
> the ISO. This Phase 3 rule is unchanged.

---

## 4. Identity file decisions and tradeoffs

| Decision | Choice | Why / tradeoff |
|---|---|---|
| `ID` | `ar0x`, `ID_LIKE=arch` | Real distro identity, but keeps Arch tool compatibility (e.g. `pacman`, AUR helpers, `arch-install-scripts`). |
| `VERSION_CODENAME` | `neon-root` | os-release(5) requires a lower-case, space-free identifier. Human form `"Neon Root"` lives in `PRETTY_NAME` and `AR0X_CODENAME`. |
| `LOGO` | `ar0x-logo` | systemd ≥ 252 field naming a freedesktop icon; we ship the matching scalable icon. Older systemd simply ignores it. |
| `ANSI_COLOR` | `0;38;2;0;229;255` | 24-bit truecolor cyan; the 8-colour fallback `6` would lose the brand hue. |
| `/usr/lib/os-release` duplicate | written | `filesystem` package owns `/etc/os-release` as a symlink; one copy alone is fragile. |
| `/etc/issue` escapes | whitelist only | Unknown `\X` is inconsistent across util-linux builds; the full ASCII art goes to `/etc/motd`. |
| `issue.net` | plain text | sshd does not expand agetty escapes. |
| `lsb-release` | shipped | Legacy scripts still parse `DISTRIB_*`. The `lsb-release` binary is **optional** and not on the ISO; the file costs nothing. |
| `neofetch` | config only, no package | AUR-only, archived upstream (RISK-010). `screenfetch` covers the second fetch tool on the ISO. |
| Fontless GRUB | kept | archiso 92 embeds no font in the EFI binary; adding `*-font` keys makes gfxmenu fall back unpredictably. |
| PNG raster | approximation of SVG | Distance-to-segment yields round joins where the SVG polygon has mitre joins. SVG remains authoritative for vector/print. |
| XCursor not hyprcursor | standard format | All consumers read it; no compiler needed. Compiled hyprcursor is v0.2. |
| Raster generators | 2 scripts, 1 shared geometry module | Prevents boot art and standalone logos drifting apart. |

---

## 5. Manual interventions (do these by hand on a real machine)

1. **⚠️ `--apply` rebuilds the initramfs and rewrites `/boot/grub/grub.cfg`.**
   `plymouth-set-default-theme -R ar0x` runs `mkinitcpio -P`, and
   `grub-mkconfig -o /boot/grub/grub.cfg` regenerates the boot config. Both need
   a finished airootfs with `linux-lts 6.18.59-1` installed and `/boot` mounted.
   **There is no automatic rollback.** Snapshot the airootfs first.
2. **Regenerate the icon cache** so `LOGO=ar0x-logo` resolves in GTK/Qt tools:
   `./tools/configure-branding.sh --apply` runs
   `gtk-update-icon-cache -f -t /usr/share/icons/hicolor` in the chroot.
3. **Boot the ISO and look at the art.** GRUB gfxmenu, Plymouth script plugin,
   syslinux vesamenu and the Hyprland cursor can only be judged visually
   (RISK-044). QEMU UEFI + BIOS commands arrive in Phase 11.
4. **`lsb_release -a`** needs the optional `lsb-release` package; it is not on
   the ISO by default. `cat /etc/os-release` needs nothing.
5. **Outlining the wordmark for print** (§1.4) requires Inkscape on a
   workstation; it is not part of the automated build.
6. **LUKS users:** the Plymouth script has no message renderer (Phase 4
   limitation, unchanged). Use `plymouth-set-default-theme -R details` or boot
   the "failsafe" GRUB entry to see a passphrase prompt.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| fastfetch shows the Arch logo | stale generated copy | `./tools/configure-branding.sh --sync && ./tools/configure-desktop.sh --sync` |
| fastfetch prints literal `$1` | `logo.type` was changed to `file-raw` | keep `"type": "file"` |
| fastfetch: "logo not found" | `/usr/share/ar0x/branding/` missing | `./tools/configure-branding.sh --sync`; check bootstrap staging |
| `screenfetch` shows no logo / errors | wrapper not executable or art missing | `chmod 0755 /usr/local/bin/ar0x-screenfetch`; verify art path |
| screenFetch aborts with "unbound variable" | someone added `set -euo pipefail` to the sourced art | remove it — it is a deliberate exemption |
| `echo "$PRETTY_NAME"` says "Arch Linux" | `/usr/lib/os-release` reverted by `filesystem` | re-run `--sync`; both files must be ar0x |
| `LOGO` icon missing in a GUI app | hicolor cache stale | `gtk-update-icon-cache -f -t /usr/share/icons/hicolor` |
| cursors still Adwaita | `XCURSOR_THEME` stale in env.lua/environment.d | `./tools/configure-desktop.sh --sync`; re-login |
| GRUB menu overlaps the logo | `theme.txt` boot_menu `top` changed | restore `top = 34%`, `height = 36%` |
| boot art still shows the bitmap wordmark | stale PNGs | `./tools/gen-theme-assets.sh && ./tools/build-kernel.sh --sync` |
| `--check` fails "palette drift" | one of the 8 hex pins edited alone | update ALL of `versions.env`, `palette.conf`, SVGs, `ar0x_logo.py`, `palette.lua`, `Main.qml`, `theme.txt` |

---

## 7. Risks

| ID | Level | Note |
|---|---|---|
| **RISK-010** | LOW | `neofetch` is AUR-only and archived; config shipped, package deliberately absent. |
| **RISK-040** | **CLOSED** | Replaced the Adwaita cursor placeholder with a real, generated XCursor theme. |
| **RISK-044** | **HIGH** | No live Wayland/GRUB/Plymouth/QEMU render in this sandbox; structural validation only. |
| **RISK-045** | LOW | `ar0x-wordmark.svg` uses live Inter text; outline it for print. |
| **RISK-046** | LOW | PNG raster uses round joins where the SVG uses mitre joins; SVG is authoritative. |

---

## 8. What `--check` actually verifies

- All 36 canonical Phase 7 files exist, plus every generated mirror is
  **byte-identical** (`cmp -s`) in `archiso/airootfs/**` and
  `config/desktop/skel/.config/**`.
- `os-release` has 11 required keys, `ID=ar0x`, `ID_LIKE=arch`, a space-free
  lowercase `VERSION_CODENAME`, `LOGO=ar0x-logo`, `VERSION_ID == AR0X_VERSION`,
  and **no shell variable expansion**.
- `lsb-release` `DISTRIB_ID`/`DISTRIB_RELEASE` agree with `versions.env`.
- `/etc/issue` uses only whitelisted agetty escapes; `/etc/issue.net` contains
  **no** backslashes; `/etc/motd` carries the ASCII logo.
- `palette.conf` 8/8 hex pins == `versions.env` 8/8 pins == SVG colours.
- ASCII: 8 lines, ≤48 columns, no tabs, `$[1-9]` strip parity, placeholders
  ⊆ `{1,2,3}`, all covered by `logo.color`.
- `fastfetch/config.jsonc` parses (comment-stripped), `type=file`, absolute
  source, no `builtin`/`arch` leftovers, includes the `os` module.
- `neofetch/config.conf` uses `image_backend="ascii"` + the official art.
- `ar0x-screenfetch.sh`: `bash -n`, no strict mode, 8 `fulloutput` lines with
  exactly one `%s` each, 3 non-empty brand colours.
- All 4 SVGs parse as XML; exact `viewBox`es; master SVG octagon/chevron/
  underscore/rect/stroke widths == `tools/lib/ar0x_logo.py`.
- 2 logo PNGs: signature + IHDR 256×256 / 512×512.
- All 5 XCursor binaries parse back (magic, header, TOC offsets, 3 chunk
  headers each, `w*h` pixels); all 12 aliases are correct symlinks.
- `XCURSOR_THEME=ar0x-cursors` in Hyprland Lua, `environment.d` and
  `/etc/skel/.icons/default/index.theme`.
- `screenfetch` present and `neofetch` absent in `config/packages.x86_64`.
- GRUB theme finalised (`PHASE 7`, `top = 34%`, `desktop-image`), Plymouth
  script finalised, wrapper is strict-mode compliant and executable.

**Not verified here:** `mkarchiso`, `pacstrap`, `arch-chroot`,
`gtk-update-icon-cache`, `plymouth-set-default-theme -R`, `mkinitcpio -P`,
`grub-mkconfig`, `fastfetch`, `screenfetch`, `lsb_release`, `fc-cache`,
`Hyprland --verify-config`, `sddm-greeter --test-mode`, QEMU UEFI/BIOS boot,
WiFi/audio/GPU QA, `shellcheck`, or any live Wayland session.
