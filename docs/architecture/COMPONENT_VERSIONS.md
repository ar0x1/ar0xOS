# ar0x — Component & Version Matrix

> Phase 1 companion to [`PROJECT_PLAN.md`](../../PROJECT_PLAN.md).
> **Verified 2026-11-03** (Phase 8 + Phase 9 additions verified 2026-11-07). Authoritative version list for Phases 2–12.
> Machine-readable equivalent: [`/home/user/ar0xOS/config/versions.env`](../../config/versions.env).

---

## 1. Pin classes

| Class | Definition | How enforced |
|---|---|---|
| **SNAPSHOT** | Comes from the frozen Arch Linux mirror snapshot `2026/11/01` written into `config/pacman.conf.build` | Freeze the mirror; generate `/opt/ar0x-build/out/packages.lock` from `pacman -Q` inside the built airootfs at the end of Phase 3 |
| **HARD** | Built from an exact upstream tag/tarball with a recorded checksum, because Arch's packages may be older or the project is not in the official repos | `tools/validate-versions.sh` checks the tag string and SHA256 before `build-iso.sh` proceeds |
| **FLOATING** | Optional software offered by `ar0x-welcome`, not present in the ISO | Never counted against the 2.2 GB ISO gate; installed by the user after first boot |

### 1.1 Phase 2 corrections (verified 2026-11-03)

| Item | Phase 1 pin | Corrected | Evidence |
|---|---|---|---|
| `archiso` | `91` | **`92-1`** | <https://archlinux.org/packages/extra/any/archiso/> — built 2026-10-31, now in `[extra]` |
| Hyprland ISO source | assumed available at `0.57.1` | built from source into `[ar0x]` | `[extra]` has `0.57.0-3`; `0.57.1-1` is `[extra-testing]` only — <https://archlinux.org/packages/extra/x86_64/hyprland/> |
| Calamares ISO source | assumed installable | built from the Codeberg tarball | not in official Arch repos |

archiso 92 also changed `profiledef.sh`: it now requires `buildmodes=('iso')` and
`bootmodes=('bios.syslinux' 'uefi.grub')` (plus `pacman_conf`, `airootfs_image_type`,
`airootfs_image_tool_options`, `bootstrap_tarball_compression`). Phase 3 must use those keys.
Its hard depends are `arch-install-scripts bash dosfstools e2fsprogs erofs-utils libarchive
libisoburn mtools squashfs-tools`; `grub`, `syslinux`, `edk2-ovmf`, `gnupg`, `openssl` and
`qemu-desktop` are the ar0x-specific additions installed by Phase 2.

**Phase 3 profile facts (verified against archiso 92 source):**
`mkinitcpio` + `mkinitcpio-archiso` are mandatory in `packages.x86_64`; `syslinux` is mandatory
*in the image* for `bios.syslinux` (mkarchiso copies `isolinux.bin` / `*.c32` from the airootfs);
`grub` is needed in the image for Calamares' target-disk install; `install_dir` must match
`^[a-z0-9]+$` and be ≤ 30 chars; `buildmodes` = `bootstrap|iso|netboot`; `bootmodes` =
`bios.syslinux` / `uefi.grub` / `uefi.systemd-boot` (the two UEFI modes are mutually exclusive).
`customize_airootfs.sh` is deprecated → `etc/pacman.d/hooks/*.hook` instead. The frozen archive
path `https://archive.archlinux.org/repos/2026/11/01/$repo/os/$arch` was confirmed live and serves
`core.db` with **no `.sig`**, so `SigLevel = Required DatabaseOptional` is required.

**Phase 4 verified kernel facts (tag `6.18.59-1`, `config.x86_64`):**
`CONFIG_IKCONFIG=y`, `CONFIG_IKCONFIG_PROC=y`, `CONFIG_CGROUPS=y`, `CONFIG_CGROUP_BPF=y`,
`CONFIG_NAMESPACES=y`, `CONFIG_USER_NS=y`, `CONFIG_AUDIT=y`, `CONFIG_BPF_SYSCALL=y`,
`CONFIG_SYSCTL=y`, `CONFIG_MULTIUSER=y`, `CONFIG_PREEMPT_VOLUNTARY=y`, `CONFIG_NO_HZ_FULL=y`,
`CONFIG_BLK_DEV_INITRD=y`, `CONFIG_RD_ZSTD=y`, `CONFIG_KERNEL_ZSTD=y` — hence the Phase 4
zstd initramfs is bootable. The packaging tag header says `6.18.57` (stale config header);
ar0x pins the **package** version `6.18.59-1`. Arch ships 3 maintainer patches at that tag;
ar0x adds zero. GRUB gfxmenu `theme.txt` uses `desktop-image`, `+ boot_menu`,
`+ progress_bar{id="__timeout__"}`; archiso 92 runs `grub-mkstandalone --themes=""` (no font
embedded) so the ar0x theme is fontless. Plymouth `script` plugin uses
`Window.SetBackgroundTopColor/BottomColor` + `Plymouth.SetBootProgressFunction`, and the
mkinitcpio `plymouth` hook must follow `udev` and precede `modconf`.

**Phase 5 verified facts:** WirePlumber **0.5+** reads config fragments from
`/etc/pipewire/wireplumber.conf.d/*.conf` (the 0.4 path `/etc/wireplumber/` is
legacy and silently ignored); the Phase 1 skeleton dir was removed. Arch's
`linux-lts 6.18.59-1` patch 0001 adds the `kernel.unprivileged_userns_clone`
sysctl (default `1`); ar0x pins it to `1` because setting `0` breaks Flatpak,
rootless Podman/Docker and Chromium's non-root sandbox. AppArmor is activated
with `apparmor=1 security=apparmor` and `apparmor.service`, with a systemd
drop-in forcing `aa-complain` (RISK-008). NetworkManager is enabled while
`systemd-networkd.service` and `dhcpcd.service` are explicitly disabled in
`/etc/systemd/system-preset/50-ar0x.preset`. `config/pacman.conf.installed` is
ROLLING with `[ar0x] SigLevel = Required`; the frozen archive mirror exists only
in `config/pacman.conf.build` (RISK-006).

**Phase 6 verified facts (retrieved 2026-11-07):** Hyprland **0.57** config is
`$XDG_CONFIG_HOME/hypr/hyprland.lua`; `require("lua.palette")` resolves to
`./lua/palette.lua` relative to the entry point, and each `require` is a
protected Lua scope. The typed API is `hl.config({...})`, `hl.bind(key,
hl.dsp.*(...))`, `hl.env(name, value)`, `hl.monitor({...})`,
`hl.window_rule({...})`, `hl.curve(name, {...})`, `hl.animation({...})`,
`hl.on("hyprland.start", fn)` and `hl.exec_cmd(cmd)`. Only keys present in
Hyprland's official `example/hyprland.lua` are used in ar0x, so
`Hyprland --verify-config` cannot fail on an invented option. Hyprland 0.57
also replaced legacy `hyprctl dispatch dpms off` with
`hl.dsp.dpms({ action = "disable"|"enable" })`; ar0x `hypridle.conf` uses it.
hyprpaper 0.8.5 uses `wallpaper { monitor = ; path = ; fit_mode = cover }`
blocks (NOT the old `preload =` / `wallpaper = ,path` syntax). hyprlock 0.9.7
uses `rgba(RRGGBBAA)` / `rgb(r,g,b)` colours and REQUIRES a config file.
Arch `sddm 0.21.0-7` (Qt6 greeter) hard-depends on `xorg-server`, so the
greeter is X11 while the user session is Wayland; SDDM 0.21 enables an OSK by
default, disabled with `InputMethod=`. SddmComponents 2.0 `TextBox`/`PasswordBox`
`color` is the FIELD background and `textColor` is the text — not the reverse.
`QT_QPA_PLATFORMTHEME=qt5ct:qt6ct` (colon list) themes Qt5 and Qt6 from one
variable; `QT_QPA_PLATFORM=wayland;xcb` (semicolon list) is the platform list.
GTK4/libadwaita ignores `gtk-theme-name` and only honours `GTK_THEME` plus
`@define-color` overrides loaded at process start. Papirus, Adwaita cursors,
`inter-font`, `ttf-jetbrains-mono-nerd` and `noto-fonts(-emoji)` are all in
Arch `[extra]`, so no AUR package is needed for the theme (RISK-010).

**ADR-017 consequence:** HARD-pinned packages are built with `makepkg -s` from exact upstream
tarballs into `[ar0x]`, and `config/pacman.conf.build` lists `[ar0x]` **first** via a local
`file://` server. Never enable `[extra-testing]` in the build config.

⚠️ **Arch is a rolling distribution.** Absolute reproducibility therefore requires pinning a
mirror date, not just package version strings. `config/pacman.conf.build` will contain:

```
[core]
SigLevel = PackageRequired
Server = https://archive.archlinux.org/repos/2026/11/01/$repo/os/$arch
```

This frozen file is used **only** by `mkarchiso`. The installed system gets
`config/pacman.conf.installed` with live mirrors + `[ar0x]`. Shipping the frozen file to users
is RISK-006.

---

## 2. Foundation / build host

| Component | Version | Class | Verification |
|---|---|---|---|
| Arch Linux base snapshot | `2026.11.0` (Nov 2026 ISO), archive date `2026/11/01` | SNAPSHOT | <https://linuxiac.com/arch-linux-november-2026-iso-released-with-kernel-7-2-11/> |
| `archiso` | **`92-1`** | SNAPSHOT | <https://archlinux.org/packages/extra/any/archiso/> (built 2026-10-31; Phase 2 correction from `91`) |
| `glibc` | `2.44` | SNAPSHOT | <https://distrowatch.com/dwres.php?resource=compare-packages> |
| `bash` | `5.3.20` | SNAPSHOT | Oct 2026 ISO article above |
| `pacman` | resolved from snapshot (recorded in `packages.lock`) | SNAPSHOT | `pacman -Q pacman` in airootfs |
| `coreutils`, `util-linux` | `util-linux 2.42.4`, rest resolved from snapshot | SNAPSHOT | Oct 2026 ISO article |
| `openssl` | `3.6.5` | SNAPSHOT | Oct 2026 ISO article |
| `curl` | `8.23` | SNAPSHOT | Nov 2026 ISO article |
| `tzdata` | `2026c-1` | SNAPSHOT | DistroWatch package comparison |
| `mkinitcpio` | `42.2` | SNAPSHOT | Nov 2026 ISO article |
| `python` | `3.14.9` | SNAPSHOT | Nov 2026 ISO article |
| `qt6-base` (Qt) | `6.12` | SNAPSHOT | Nov 2026 ISO article |
| `gtk4` | `4.24.1` | SNAPSHOT | DistroWatch package comparison |

Host-side tools installed in Phase 2 (versions resolved by `pacman -S` on the host, not pinned
into the ISO): `archiso`, `base-devel`, `git`, `qemu-full`, `edk2-ovmf`, `xorriso`,
`squashfs-tools`, `dosfstools`, `mtools`, `libisoburn`, `gptfdisk`, `parted`, `e2fsprogs`,
`btrfs-progs`, `efitools`, `sbsigntools`, `gnupg`, `shellcheck`, `jq`, `rsync`, `docker`
(optional), `vagrant` (optional).

---

## 3. Kernel, initramfs, boot

| Component | Version | Class | Notes / verification |
|---|---|---|---|
| `linux-lts` | `6.18.59-1` | SNAPSHOT | <https://archlinux.org/packages/core/x86_64/linux-lts/> (`6.18.60` in testing on 2026-10-30 — **pin the `[core]` version, not core-testing**) |
| `linux-lts-headers` | `6.18.59-1` | SNAPSHOT | Must match kernel exactly for DKMS |
| LTS upstream support | until **Dec 2027** | — | <https://9to5linux.com/its-official-linux-kernel-6-18-will-be-lts-supported-until-december-2027> |
| `linux-firmware` | snapshot version | SNAPSHOT | ⚠️ ~400 MB; size-lever #1 in the §7 budget of PROJECT_PLAN.md |
| `grub` | `2.16` | SNAPSHOT | Oct 2026 ISO article + DistroWatch |
| `plymouth` | `26.134.222-2` | SNAPSHOT | DistroWatch package comparison |
| `shim-signed` / `sbsigntools` | snapshot version | SNAPSHOT | Optional Secure Boot path; MOK enrollment manual |
| `memtest86+` | snapshot version | SNAPSHOT | Optional boot entry |

**Kernel decision:** the *stock* Arch `linux-lts` package is used unmodified in v0.1.
Phase 4 supplies `config/kernel/ar0x-lts.config` as the **documented reference `.config`** for
review/diff purposes and for the v0.2 custom-compiled option — it is NOT applied to the v0.1
kernel package. ⚠️ Applying a hand-edited `.config` or out-of-tree patches is RISK-001 and
requires a known-good fallback kernel to remain in the ISO.

---

## 4. Core system services

| Component | Version | Class | Notes |
|---|---|---|---|
| `systemd` | `262.1` (released 2026-10-16) | SNAPSHOT | Confirmed against GitHub API `systemd/systemd` tag `v262.1` and Nov 2026 ISO article |
| `NetworkManager` | resolved from snapshot | SNAPSHOT | Phase 5 DNS/connectivity config |
| `pipewire` | `1.6.10` | SNAPSHOT | Nov 2026 ISO article |
| `wireplumber` | resolved from snapshot | SNAPSHOT | Must be ABI-compatible with the PipeWire above |
| `bluez` | resolved from snapshot | SNAPSHOT | Bluetooth for the Phase 11 checklist |
| `nftables` | resolved from snapshot | SNAPSHOT | Phase 5 default-drop ruleset |
| `apparmor` | resolved from snapshot | SNAPSHOT | `complain` mode in v0.1 |
| `polkit` | resolved from snapshot | SNAPSHOT | `hyprpolkitagent` bridges GUI elevation |
| `sudo` | resolved from snapshot | SNAPSHOT | wheel group, no NOPASSWD on installed systems |
| `btrfs-progs` | `7.3` | SNAPSHOT | Nov 2026 ISO article (btrfs install option) |
| `xfsprogs` | `7.2.1` | SNAPSHOT | Nov 2026 ISO article |
| `cryptsetup` | `2.8.8` | SNAPSHOT | Oct 2026 ISO article (LUKS option in Calamares) |

---

## 5. Graphics & display

| Component | Version | Class | Verification |
|---|---|---|---|
| `mesa` | `26.2.6` | SNAPSHOT | Nov 2026 ISO article |
| `nvidia` driver | `615.78.08` | SNAPSHOT | Nov 2026 ISO coverage; FLOATING install via welcome app |
| Wayland protocols | `wayland`, `wayland-protocols` from snapshot | SNAPSHOT | |
| `xwayland` | snapshot version | SNAPSHOT | Fallback for X11-only apps |
| `sddm` | `0.21.0-7` | SNAPSHOT | GitHub upstream tag `v0.21.0` (2024-02-26); Arch rebuild `-7`. ⚠️ X11 greeter — see ADR-008 |

---

## 6. Desktop environment — Hyprland ecosystem (HARD pins)

> ⚠️ **BREAKING CHANGE VERIFIED:** Hyprland **0.57.0 (2026-10-28)** removed support for the
> legacy `hyprland.conf` (hyprlang) format. Lua configuration (`hyprland.lua`) has been
> available since 0.55 and is now mandatory; **there is no automatic converter**.
> Sources: <https://www.linuxcompatible.org/story/hyprland-0570-released-legacy-conf-dropped-window-wobble-arrives/>,
> <https://linuxiac.com/hyprland-0-57-released-with-new-blur-effects-workspace-sharing/>,
> <https://github.com/Wiecek-K/arch-hyprland-ajmag/pull/12>.
> Phase 6 ships `/etc/skel/.config/hypr/hyprland.lua` + `lua/*.lua` modules loaded via
> `require`, with keybinds loaded first so a broken module cannot remove keyboard control.

| Component | Version | Released | Class | Verification |
|---|---|---|---|---|
| `Hyprland` | **`0.57.1`** | 2026-11-03 | HARD | GitHub API `hyprwm/Hyprland/releases/latest` → `v0.57.1`; release notes fix keybinds, NVIDIA black screens, Lua config validator |
| `hyprpaper` | `0.8.5` | 2026-11-01 | HARD | GitHub API `hyprwm/hyprpaper` |
| `hyprlock` | `0.9.7` | 2026-11-01 | HARD | GitHub API `hyprwm/hyprlock` |
| `hypridle` | `0.1.8` | 2026-07-26 | HARD | GitHub API `hyprwm/hypridle` |
| `xdg-desktop-portal-hyprland` | `1.5.0` | 2026-10-28 | HARD | GitHub API `hyprwm/xdg-desktop-portal-hyprland` |
| `hyprpicker` | `0.4.8` | 2026-11-01 | HARD | GitHub API `hyprwm/hyprpicker` |
| `hyprcursor` | `0.1.13` | 2025-07-31 | HARD | GitHub API `hyprwm/hyprcursor` |
| `waybar` | `0.15.0` | 2026-02-06 | HARD | GitHub API `Alexays/Waybar` |
| `hyprpolkitagent` | snapshot version | — | SNAPSHOT | Required for GUI polkit prompts under Wayland |

**Compatibility gate for Phase 6:** the Hyprland 0.57.x series must be installed as a matched
set with the ecosystem releases above. Mixing a 0.56-era `hyprlock`/`hypridle` with 0.57 can
break the session-lock protocol. `tools/validate-versions.sh` asserts the exact set.

---

## 7. Installer (HARD pin, non-GitHub upstream)

> ⚠️ **UPSTREAM MIGRATION VERIFIED:** Calamares moved from GitHub to **Codeberg** in 2025.
> `github.com/calamares/calamares` is an archived mirror whose latest tag is `v3.3.14`
> (2025-02-20). Building from it would ship an installer without the Wayland keyboard-input fix.
> Source: <https://codeberg.org/Calamares/calamares/releases>,
> <https://en.wikipedia.org/wiki/Calamares_(software)>.

| Component | Version | Released | Class | Verification |
|---|---|---|---|---|
| `calamares` | **`3.4.3`** | 2026-09-10 | HARD | <https://codeberg.org/Calamares/calamares/releases/tag/v3.4.3> |
| Tarball | `calamares-3.4.3.tar.gz` | — | HARD | `https://codeberg.org/Calamares/calamares/releases/download/v3.4.3/calamares-3.4.3.tar.gz` |
| SHA256 | `144cbbf6bdcebfb21685950db4f0777218519df095f62f4aa392f28348110d18` | — | HARD | Published in the release notes |
| Detached sig | `calamares-3.4.3.tar.gz.asc` | — | HARD | Same URL + `.asc` |
| Signing key | `6D08 3784 1C06 8A23 3F24 127B 14B6 CC38 1BC2 56D6` | — | HARD | Verify with `gpg --verify` before compiling |
| `kpmcore` | snapshot version | — | SNAPSHOT | 3.4.3 adds support for the latest KPMcore; partitioning backend |

**Why 3.4.3 over 3.4.2:** besides newer KPMcore support and a fix that stops `/boot` being
accidentally marked as the EFI partition, 3.4.3 fixes **QML keyboard input under Wayland** —
essential when the Calamares GUI itself runs on a Wayland-first live session.
Sources: <https://9to5linux.com/calamares-3-4-3-linux-graphical-installer-improves-disk-partitioning-locale>,
<https://news.tuxmachines.org/n/2026/09/10/Calamares_3_4_3_Linux_Graphical_Installer_Improves_Disk_Partiti.shtml>.

**Phase 10 configuration (ADR-026):** `config/calamares/settings.conf` targets
exactly 3.4.3 (the 3-phase `show/exec/show` and `packagechooser` instance
syntax are 3.4-only), asserts `AR0X_CALAMARES_VERSION=3.4.3`,
`AR0X_CALAMARES_SOURCE=codeberg` and the 64-hex SHA256, and FAILS if the
archived `github.com/calamares/calamares` mirror appears in any Phase 10
config. `docs/INSTALLER_FLOW.md §7` still requires a human to verify the
detached `.asc` with key `6D08 3784 … 56D6` before publishing to `[ar0x]`.

**CI implication:** `.github/workflows/build-packages.yml` (Phase 9) must fetch from
`codeberg.org`, which is reachable from GitHub Actions but is NOT one of this sandbox's
allowlisted hosts — so the tarball is vendored into `assets/` or fetched on the user's own
build host, with its SHA256 recorded here.

---

## 8. Developer toolchain (audience-driven, FLOATING / optional)

Offered by `ar0x-welcome` as "Install developer extras"; not baked into the ISO:

| Component | Version reference | Notes |
|---|---|---|
| LLVM / Clang | `23.1.4` | Nov 2026 Arch repos |
| Go | `1.27.3` | Nov 2026 Arch repos |
| Rust | `1.99.1` | Nov 2026 Arch repos |
| Node.js | `26.13` | Nov 2026 Arch repos |
| OpenJDK | `27.0.1` | Nov 2026 Arch repos |
| Docker / Podman | snapshot | container tooling option |

`git`, `neovim`, `base-devel` subset, `python`, and `zsh` + `starship` **are** in the ISO.

---

## 9. ar0x-authored components (versioned with the distro)

| Component | Version | Phase |
|---|---|---|
| `ar0x-welcome` | `0.1.0` | 8 |
| `ar0x-update` | `0.1.0` | 8 |
| `ar0x-info` | `0.1.0` | 8 |
| `ar0x-theme` | `0.1.0` | 8 |
| `ar0x-wallpapers` | `0.1.0` | 8 |
| `ar0x-hypr-config` | `0.1.0` | 8 |
| `ar0x-keyring` | `0.1.0` | 9 |
| `ar0x-meta` | `0.1.0` | 8 |

All ar0x packages follow `pkgver=0.1.0`, `pkgrel=1`, and are rebuilt (bump `pkgrel`) whenever
their content changes, so `pacman -Syu` sees a newer package.

---

## 9b. Phase 7 brand/identity facts (verified 2026-11-07)

Full detail, installed paths and the exact style rules: `docs/BRANDING_GUIDE.md`.

| Component | Verified fact | Source |
|---|---|---|
| `os-release(5)` | `LOGO=` is a freedesktop icon-theme name, **added in systemd 252**; `VERSION_CODENAME` must be lower-case without spaces; no shell variable expansion is permitted | freedesktop.org `os-release(5)`, Debian manpages |
| `agetty(8)` | `/etc/issue` expands only `\s \m \r \n \l \d \t \v \b \o \u \U`; `issue.net` is **not** expanded | util-linux man page, screenFetch 3.9.9 README |
| fastfetch | `logo.type = "file"` expands `$1`–`$9` from `logo.color`; `"file-raw"` does not. Builtin logos in `src/logo/ascii/a/*.txt` use the same `$N` syntax | fastfetch `dev` branch source |
| neofetch | `image_backend="ascii"` + `image_source="/path/to/ascii"` (flag `--source`) loads custom ASCII. **Removed from Arch `[extra]`** and archived upstream → AUR-only → NOT on the ISO (RISK-010) | `dylanaraps/neofetch` source; `archlinux.org/packages/extra/any/neofetch/` returns 404 |
| screenfetch | Arch `[extra]` **3.9.9-1** (official). `-a PATH` sources a Bash snippet defining `startline`, `logowidth`, `fulloutput[]` (one `%s` per line) | Arch package search; `KittyKatt/screenFetch` `asciiText()` |
| Xcursor(3) | magic `Xcur`, file header 16 bytes, TOC `(type, subtype, position)`, image chunk `headerSize=36`, type `0xfffd0002`, subtype = nominal size, `width*height` packed ARGB CARD32 | X.org / Arch `Xcursor(3)` |
| GRUB 2 gfxmenu | percent-based `top`/`height` in `theme.txt`; `boot_menu` and `progress_bar` (`id="__timeout__"`) | GRUB manual theme-file format |

**Phase 8 tool matrix (no upstream binary versions — these are OUR sources):**

| Component | Version / pin | Source | Verification |
|---|---|---|---|
| `ar0x-welcome` | `0.1.0-1`, `dev.ar0x.Welcome` | `packages/ar0x-welcome/PKGBUILD` + `ar0x-welcome.py` | `ar0x_pkgbuild.py`: AST, GTK4 `require_version`, lazy `gi`, 8 CSS pins, 5 https links |
| `ar0x-update` | `0.1.0-1`, `[ar0x] SigLevel=Required` | `packages/ar0x-update/PKGBUILD` + `ar0x-update` | `--self-test`: root refusal, insecure SigLevel rejection, isolated `db.sig` check, 2 pending updates, rollback parser |
| `ar0x-info` | `0.1.0-1`, 17 `--json` keys | `packages/ar0x-info/PKGBUILD` + `ar0x-info` | `--self-test` + `--json` parsed by Python + `--plain` ASCII |
| GTK4 / PyGObject | `gtk4`, `python-gobject` (official `[extra]`, floating) | `config/packages.x86_64` | HARD pins policy: NOT pinned for tools (they are runtime bindings, not built artefacts) |
| `fakeroot` | via `base-devel`, declared explicitly | `config/packages.x86_64` | required by the temporary-dbpath `--check` algorithm |
| `python` | official `[core]`, floating | `config/packages.x86_64` | `#!/usr/bin/env python3`, stdlib-only for `--self-test` |
| `AR0X_TOOLS_VERSION` | `0.1.0` == `AR0X_VERSION` | `config/versions.env` | both validators assert equality |
| `AR0X_URL_*` | 5 RESERVED https endpoints (RISK-050) | `config/versions.env` + `config/tools/links.conf` | `--check` asserts byte-parity |
| PKGBUILD checksums | 18 real SHA-256 (5 + 3 + 10) | 3 `PKGBUILD` files | `configure-tools.sh --sync` regenerates; `--check` verifies |

⚠️ All 8 packages are `arch=('any')` with LOCAL `source=()` arrays;
no upstream tarball, no VCS source, no network and no AUR. They are therefore
immune to the frozen `2026/11/01` snapshot drift (RISK-010). ⚠️ They were
NEVER built with `makepkg` here (RISK-049) and are NOT on the ISO (RISK-048).

**Phase 9 repository matrix (all POLICY, no secrets):**

| Component | Pin / value | Canonical source | Verification |
|---|---|---|---|
| `AR0X_REPO_NAME` / `_ARCH` | `ar0x` / `x86_64` | `config/repo/repo-options.conf` + `versions.env` | `ar0x_repo.validate_repo_options()` parity |
| `AR0X_REPO_DB` / `_FILES_DB` | `ar0x.db.tar.zst` / `ar0x.files.tar.zst` | both above | `repo-add` creates BOTH + detached `.sig` |
| `AR0X_REPO_SIGLEVEL` | `Required` (packages AND db, inherits `TrustedOnly`) | `repo-options.conf` | `UNSAFE_SIGLEVELS` gate; never `Optional`/`Never`/`TrustAll` |
| `AR0X_REPO_SIGN_PACKAGES` / `_INCLUDE_SIGS` / `_VERIFY_EXISTING` | `yes` / `yes` / `yes` | `repo-options.conf` | `gpg --detach-sign` ×8, `repo-add --include-sigs -v` |
| `AR0X_REPO_REMOVE_OLD` / `_KEEP_OLD` | `0` / `3` | `repo-options.conf` + `versions.env` | `0` preserves `ar0x-update --rollback` |
| `AR0X_REPO_SERVER` | `https://repo.ar0x.dev/$arch` (RESERVED) | `repo-options.conf`, `versions.env`, 2 pacman configs | literal `\$arch` in sourced files (`set -u` safe); Python parsers normalise back |
| `AR0X_REPO_KEY_{UID,ALGO,EXPIRE,FINGERPRINT_FILE,PUBLIC_KEY}` | `ar0x 0.1.0 Release Signing Key …` / `ed25519` / `2y` / `config/repo/RELEASE_KEY_FINGERPRINT` / `ar0x-public-key.asc` | `config/versions.env` | `RELEASE_KEY_FINGERPRINT = PENDING-KEYGEN`; `ar0x-trusted` EMPTY (RISK-051) |
| `AR0X_REPO_CI_{IMAGE,BUILDER}` | `archlinux:base-devel` / `builder` | `versions.env` + both CI workflows | `makepkg` refuses root → non-root `builder` |
| 8 packages / checksums | `0.1.0-1` ×8; **57 `source` / 57 `sha256sums`** (56 real + 1 MANUAL `SKIP`) | `packages/*/PKGBUILD` | `setup-repo.sh --sync` regenerates; `ar0x_pkgbuild.py` verifies |
| 31 mirrors | `config/desktop/**`, `assets/**`, `config/repo/pacman.conf.ar0x-entry` → `packages/ar0x-*/**` | `ar0x_repo.MIRRORS` | `validate_mirrors()` byte-parity |
| `BUILD_ORDER` | `info, update, keyring, welcome, theme, wallpapers, hypr-config, meta` (meta LAST) | `ar0x_repo.BUILD_ORDER` | `validate_build_order()` checks intra-repo depends |

**Phase 9 upstream facts used (verified 2026-11-07):**

| API / behaviour | Verified fact | Source |
|---|---|---|
| `repo-add -s` | `gpg --detach-sign` on the db; `-k`/`GPGKEY` selects the key; `-v` verifies an EXISTING db sig before rewrite; `--include-sigs` embeds package `.sig`s; creates BOTH `*.db.tar.*` and `*.files.tar.*`. It does **NOT** create package signatures | `man.archlinux.org/man/repo-add.8.en` (pacman 7.1.0) |
| `pacman-key --populate` | imports `<keyring>.gpg` from `/usr/share/pacman/keyrings`, reads `<keyring>-trusted` as 40-hex FPRs, lsigned + `--import-ownertrust`, then disables `<keyring>-revoked` keys; requires root + `--init` master key | `man.archlinux.org/man/pacman-key.8.en` + GitLab `pacman-key.sh.in` |
| `SigLevel = Required` | signatures required on packages AND databases (unless `DatabaseOptional` overrides); untrusted/expired/revoked are fatal; `TrustedOnly` is the default | `pacman.conf(5)`, Arch Wiki |
| `makepkg` in CI | refuses root; `archlinux:base-devel` needs `pacman -Sy base-devel git sudo`, `useradd builder`, `chown`, `sudo -u builder makepkg` | Arch CI guides / `dt-arch-repo` |

**Phase 8 API facts used (verified 2026-11-07):**

| API / behaviour | Verified fact | Source |
|---|---|---|
| GTK4 CSS | `CssProvider.load_from_path()` + `Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, STYLE_PROVIDER_PRIORITY_APPLICATION)`; `load_from_data` deprecated | PyGObject Gtk-4.0 `CssProvider` docs |
| GTK4 links | `Gtk.LinkButton.new_with_label(uri, label)` exists; uses `gtk_show_uri` | docs.gtk.org/gtk4 `LinkButton` |
| GIO subprocess | `Gio.Subprocess.new(argv, STDOUT_PIPE\|STDERR_PIPE)` + `communicate_utf8_async()/finish()` avoids blocking the UI loop | gjs.guide GIO subprocess guide |
| `checkupdates` | `fakeroot` + temp `CHECKUPDATES_DB` + symlink `${DBPath}/local` + `pacman -Sy --dbpath` + `pacman -Qu`; never a bare `pacman -Sy` | `kyrias/pacman-contrib` `checkupdates.sh.in` |
| `pacman.conf(5)` | default `SigLevel = Required TrustedOnly`; `Optional`/`TrustAll`/`Never` are unsafe for `[ar0x]` | pacman.conf man page |
| `python-gobject` | official Arch `[extra]` package, Python 3 GLib/GObject/GIO/GTK bindings | archlinux.org/packages/extra/x86_64/python-gobject |
| `fakeroot` | expected via `base-devel`; NOT an explicit dependency of `pacman`/`pacman-contrib` | Arch BBS + StackOverflow |

**Phase 7 multipliers:** master SVG `viewBox="0 0 512 512"`, wordmark
`viewBox="0 0 1024 256"`, 8 hex pins shared with `config/versions.env`,
5 authored XCursor shapes × 3 nominal sizes (24/32/48) + 12 aliases,
21 Plymouth progress frames, 3 ASCII logo variants, 4 SVG masters,
2 logo PNG rasters. All formats are parsed back by
`tools/configure-branding.sh --check`.

---

## 10. Version validation procedure

`tools/validate-versions.sh` (Phase 1 helper, runnable in this sandbox) performs:

1. `source config/versions.env` and assert every required variable is non-empty.
2. Assert `AR0X_HYPR_CONFIG_FORMAT=lua` and fail if any `hyprland.conf` exists under
   `config/`, `archiso/`, or `packages/`.
3. Assert `AR0X_CALAMARES_VERSION=3.4.3` and `AR0X_CALAMARES_SOURCE=codeberg`.
4. Assert the `archiso 92-1` profile contract (`buildmodes=iso`, `bootmodes` containing both
   `bios.syslinux` and `uefi.grub`) and `AR0X_HARD_PIN_REPO_PRIORITY=first` (ADR-017).
5. Assert the snapshot date in `config/pacman.conf.build` matches `AR0X_SNAPSHOT_DATE`
   (once Phase 3 has created that file), and that the frozen mirror never leaks into
   `config/pacman.conf.installed` (RISK-006).
6. Sweep **every** `*.sh` in the repo (`tools/`, `docker/`, `vagrant/`) for the required
   `#!/bin/bash` shebang and `set -euo pipefail`, and assert all 8 Phase 2 deliverable files
   exist. SOURCED snippets are explicitly exempt: `archiso/profiledef.sh`,
   `config/system/profile.d/*.sh`, `archiso/airootfs/etc/profile.d/*.sh` and
   `config/branding/ascii/ar0x-screenfetch.sh`.
7. (Phase 7) Assert all 28 Phase 7 deliverables, 8/8 palette pins across
   `versions.env` ↔ `palette.conf` ↔ SVG ↔ GRUB theme, SVG geometry ↔
   `tools/lib/ar0x_logo.py`, ASCII `$N` parity, 5 XCursor files parsed back with
   12 aliases, `/etc` identity mirrors, `XCURSOR_THEME=ar0x-cursors`, and
   `screenfetch` present / `neofetch` absent in `packages.x86_64`.
8. (Phase 8) Assert all 31 Phase 8 deliverables; `AR0X_TOOLS_VERSION ==
   AR0X_VERSION`; `[ar0x] SigLevel = Required`; `ConditionFirstBoot=yes`;
   then delegate to `tools/lib/ar0x_pkgbuild.py` for 57/57 SHA-256 sums,
   8 `package()` bodies, 3 `.desktop` files, 2 systemd units, 5 URL pins,
   8 CSS hex pins, 4 groups / 23 official packages with zero AUR, lazy `gi`,
   zero `shell=True`, `ADR-024: 0/8 overlay-owned paths`, and zero `ar0x-*`
   packages in `config/packages.x86_64` (Phase 11 gate).
9. (Phase 9) Assert all 14 `AR0X_REPO_*` version keys, all 30 Phase 9
   deliverables, `repo-options.conf` ↔ `versions.env` parity (12 options),
   `[ar0x]` entry ↔ `pacman.conf.installed` parity, `PENDING-KEYGEN` +
   empty `ar0x-trusted`/`ar0x-revoked`, `ar0x-keyring.install` `--populate`,
   the 8-package `BUILD_ORDER`, 31 byte-identical mirrors, 3 CI workflows
   (PR-safe / non-root build / signing-only release), and no private-key
   material or `SigLevel = Never` in any source file. Delegated to
   `tools/lib/ar0x_repo.py`.
10. (Phase 10) Assert all 5 `AR0X_INSTALLER_*` / `AR0X_CALAMARES_*` keys,
    all 30 Phase 10 deliverables, `initialPartitioningChoice: none`,
    `prompt-install: true`, the `lsblk -o NAME,SIZE,MODEL,TRAN` manual gate,
    zero archived-GitHub references, `0755` helper/driver modes and the
    ADR-024 no-duplicate-`/etc/calamares` rule; then delegate the full
    show/exec/show + 21 module configs + 8 palette pins + 3 official-only
    package groups + RISK-013 finish wiring to `tools/lib/ar0x_installer.py`.

`tools/setup-repo.sh --check` adds `bash -n` on all 8 PKGBUILDs, 2 `.install`
scriptlets, 8 extensionless bash executables (including the 3 `ar0x-apply-*`
helpers), Python AST checks, and a `git check-ignore` gate proving derived
key/db artifacts cannot be committed. `--self-test` RUNS the 3 appliers into a
temp HOME (verifying all 24 copied files + timestamped backups), exercises a
mock signed repo with 3 negative cases, and re-runs the Phase 8 self-test chain.
`--verify DIR` inspects a real repo tree via `ar0x_repo.repo_problems()`.
⚠️ `makepkg`, `gpg`, `repo-add`, `pacman`, `namcap`, `shellcheck`,
`desktop-file-validate` and `systemd-analyze verify` remain MANUAL gates on a
real Arch host (RISK-048/049/051).

On the real build host, Phase 3 additionally generates `packages.lock` from `pacman -Q` inside
`$AR0X_WORK_DIR/x86_64/airootfs`. That lockfile, plus the frozen mirror date, is what makes
the build reproducible.
