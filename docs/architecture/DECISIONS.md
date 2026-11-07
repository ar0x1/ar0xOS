# ar0x — Architecture Decision Records (ADRs) & Tradeoffs

> Phase 1 companion to [`PROJECT_PLAN.md`](../../PROJECT_PLAN.md).
> Each ADR records the decision, the alternatives, the tradeoff accepted, and the reversal cost.
> Status: **ACCEPTED** unless noted. Date: 2026-11-03 (updated 2026-11-07 with ADR-022 and ADR-023).

---

## ADR-001 — Base distribution: Arch Linux

**Decision:** Arch, using the official `archiso` toolchain.

**Alternatives considered**

| Option | Pros | Cons |
|---|---|---|
| **Arch** ✅ | `archiso` produces a bootable hybrid ISO with minimal glue; pacman + `repo-add` make a custom repo trivial; newest Hyprland/Wayland/Mesa; PKGBUILD is the simplest packaging format | Rolling release → reproducibility requires a frozen archive mirror; less stable than Debian |
| Debian | Frozen stable archive, `live-build` is mature, `reprepro` for repos | Wayland/Hyprland/NVIDIA stacks lag by 1–2 years; Hyprland 0.57 not packaged; Calamares config differs |
| Alpine/musl | Tiny ~1 GB images, fast boot, apk | ⚠️ musl breaks binary NVIDIA drivers, Steam, some GTK/Qt apps; Hyprland support is patch-heavy |
| LFS | Total control; every line understood | ⚠️ Weeks of build time; no binary package manager; Phases 3/4/9 balloon; no security update pipeline |
| Fedora | Modern toolchain, SELinux-first, lorax | RPM packaging more complex than PKGBUILD; Calamares/Hyprland less integrated |

**Tradeoff accepted:** rolling freshness and the best Wayland stack, at the cost of having to
implement reproducibility ourselves via `archive.archlinux.org` snapshot pinning + `packages.lock`.
**Reversal cost:** HIGH (changes all 12 phases).

---

## ADR-002 — C library: glibc (not musl)

**Decision:** `glibc 2.44` (implied by Arch).

**Tradeoffs:** glibc gives binary compatibility with proprietary GPU drivers, Steam, Discord,
Zoom, and prebuilt developer toolchains — important for a developer/gamer-adjacent audience.
musl would save ~100 MB and reduce attack surface but requires rebuilding/patching most
third-party binaries. Rejected because it conflicts with the "GPU + WiFi must work" Phase 11
acceptance criteria.

---

## ADR-003 — Init system: systemd 262.1

**Decision:** systemd.

| Option | Pros | Cons |
|---|---|---|
| **systemd** ✅ | NetworkManager, PipeWire, journald, logind, timedated, homed, `ConditionFirstBoot`, Calamares integration all work with zero glue | Larger footprint; controversial in some communities |
| OpenRC | Simple, independent | Needs `elogind` + `eudev`; WirePlumber and seat management need manual wiring; Calamares expects systemd-ish targets |
| runit / s6 | Tiny, fast, reliable supervision | Hand-written run scripts for every service; no `ConditionFirstBoot`; highest maintenance burden |

**Tradeoff accepted:** integration and a working first-boot flow over minimalism.
`ar0x-firstboot.service` with `ConditionFirstBoot=yes` is a concrete systemd-only feature used
in Phase 8; on OpenRC it would need a custom marker-file script.

---

## ADR-004 — Bootloader: GRUB 2.16

**Decision:** GRUB, for both UEFI and BIOS.

| Option | UEFI | BIOS | Themeable | Secure Boot |
|---|---|---|---|---|
| **GRUB 2.16** ✅ | ✅ | ✅ | ✅ (full theme) | ✅ (shim) |
| systemd-boot | ✅ | ❌ | ❌ (text only) | ✅ |
| rEFInd | ✅ | ❌ | ✅ (graphical) | ✅ (with shim) |

**Tradeoff accepted:** GRUB is heavier and its config is more complex, but the Phase 11 spec
explicitly requires **both** UEFI and BIOS QEMU tests, and Phase 7 requires a branded boot
menu. GRUB is the only option satisfying both. `efiboot/` entries are kept in the profile only
as archiso compatibility scaffolding, not used as an active boot path.

---

## ADR-005 — Desktop: Hyprland 0.57.1 with **Lua** configuration ⚠️

**Decision:** Hyprland `0.57.1`, configured via `hyprland.lua` + `require`-loaded Lua modules.

**The critical technical fact:** Hyprland 0.55 (May 2026) introduced Lua configuration;
**0.57.0 (2026-10-28) removed legacy `hyprland.conf` (hyprlang) support entirely**, with no
automatic converter. Verified against multiple independent sources and the `v0.57.1` GitHub
release notes (2026-11-03), which mention Lua config-validator fixes.

**Consequences for Phase 6:**
- `/etc/skel/.config/hypr/hyprland.lua` is the entry point — **never** `hyprland.conf`.
- Modules load in order: `env → keybinds → monitors → looknfeel → animations → input → rules → autostart`.
  Keybinds load first so a syntax error in a later module cannot remove keyboard control.
- `hyprctl keyword` is disabled under Lua, so gamemode/monitor toggles become Lua functions.
- `hyprctl dispatch` uses the Lua dispatch syntax.
- `tools/validate-versions.sh` fails the build if a stray `hyprland.conf` appears anywhere.

**Alternatives:** Sway (i3-compatible, stable, less eye candy), KDE Plasma (~3–4 GB, full DE),
GNOME (⚠️ libadwaita actively resists third-party theming — worst fit for a branded distro),
XFCE/i3 (X11, legacy), none (headless).

**Tradeoff accepted:** the strongest visual identity and best fit for the cyberpunk vibe, at the
cost of writing all configs as Lua and tracking a fast-moving upstream (0.57.1 was released on
the day this plan was written). **Risk:** upstream churn — mitigated by HARD-pinning the whole
Hyprland ecosystem as a matched set (see `COMPONENT_VERSIONS.md` §6).

---

## ADR-006 — Kernel: stock `linux-lts 6.18.59-1`, no custom patches in v0.1

**Decision:** use the unmodified Arch `linux-lts` package. Phase 4 delivers the reference
`.config` for review, `mkinitcpio.conf`, GRUB configs and the Plymouth theme — not a rebuilt kernel.

| Option | Pros | Cons |
|---|---|---|
| **Stock LTS** ✅ | Signed, tested, DKMS-friendly, LTS until Dec 2027, lowest risk | Older than mainline for bleeding-edge hardware |
| Zen / XanMod | Lower latency, gaming/perf tweaks | External repo dependency, more rebuild churn |
| Latest mainline | Newest hardware | Frequent regressions, out-of-tree drivers break |
| Linux-libre | No blobs | ⚠️ Many WiFi/GPU devices simply will not work — conflicts with Phase 11 checklist |
| Custom-compiled + patches | Full control | ⚠️⚠️ RISK-001: unbootable ISO, no signed updates, needs a fallback kernel |

**Tradeoff accepted:** stability for v0.1. ⚠️ **Warning:** any move to a custom kernel in v0.2
is a risky, manual, host-side operation. Phase 4 will restate this warning before touching
`menuconfig`.

---

## ADR-007 — Installer: Calamares **3.4.3 from Codeberg** ⚠️

**Decision:** build Calamares `3.4.3` from the official Codeberg tarball
(SHA256 `144cbbf6bdcebfb21685950db4f0777218519df095f62f4aa392f28348110d18`), not the
archived GitHub mirror.

**Verified migration:** Calamares moved to Codeberg in 2025; `github.com/calamares/calamares`
is an archived mirror whose latest tag is `v3.3.14` (2025-02-20). 3.4.3 (2026-09-10) fixes
QML keyboard input under Wayland — **required** for a GUI installer running on a Wayland-first
live session — and fixes `/boot` being mistakenly marked as the EFI partition.

**Tradeoffs:**
- Source is not on GitHub → CI must fetch `codeberg.org` (reachable from GitHub Actions), and
  the tarball + detached signature are vendored/verified by SHA256.
- 3.4.x module config schema differs from the widely documented 3.3.x. Phase 10 configs are
  written against 3.4.3 and must not be copied from 3.2/3.3-era distro configs.
- Alternative: CLI-only installer (no Qt6/KPMcore, saves ~240 MB) — rejected because a GUI
  installer is a locked preference.

---

## ADR-008 — Display manager: SDDM 0.21.0

**Decision:** SDDM with an ar0x QML theme; the greeter runs on X11, the user session is Wayland.

**Tradeoffs:** SDDM is the best-themed, best-documented DM and integrates with Calamares' user
creation. But 0.21.0's greeter is X11-based in a Wayland-first stack, which can be awkward on
NVIDIA. Alternatives:
- `greetd` + `gtkgreet` — Wayland-native, tiny, but theming is minimal and first-boot UX is spartan.
- GDM — GNOME-coupled, heavy.
- No DM (`tty` + `Hyprland` autostart) — smallest, but conflicts with the "branded login screen"
  requirement in Phase 6.

**Mitigation:** SDDM X11 greeter is explicitly listed in the Phase 11 GPU test matrix (RISK-009);
if it fails on NVIDIA, `greetd` is the documented fallback for v0.2.

---

## ADR-009 — Mandatory access control: AppArmor in `complain` mode

**Decision:** AppArmor enabled but not enforcing in v0.1; `aa-enforce` offered in `ar0x-welcome`.

**Tradeoffs:** SELinux gives stronger, label-based confinement but requires a policy-bearing
filesystem and far more integration work on Arch (ADR-001 alternative Fedora would have made
SELinux natural). ⚠️ Enforcing AppArmor on a Wayland/Hyprland stack can silently break
xdg-desktop-portal screen sharing, screenshot tools, and GPU helpers. `complain` mode logs
violations without breaking the session, which is the correct posture for a first release.

---

## ADR-010 — Default filesystem: ext4 (btrfs optional)

**Decision:** ext4 for the default Calamares "erase disk" path; btrfs with
`@`, `@home`, `@log`, `@pkg` subvolumes offered as an advanced option.

**Tradeoffs:** ext4 is predictable, universally recoverable, and needs no snapshot-aware GRUB
config. btrfs enables snapshots/compression but adds GRUB subvolume handling, `grub-btrfs`
integration, and more installer failure modes. Given RISK-004 (destructive partitioning), the
simpler default is correct for v0.1.

---

## ADR-011 — Shell: zsh interactive, bash 5.3.20 for every script

**Decision:** `zsh` + `starship` in `/etc/skel`; **all** `tools/*.sh` use `#!/bin/bash` and
`set -euo pipefail`.

**Tradeoffs:** zsh gives a better interactive developer experience, but its arrays, word
splitting, and `set -e` semantics differ from bash. Using bash for automation keeps scripts
portable to any Arch host and satisfies the output rules. `fish` was rejected for scripts
outright (non-POSIX syntax).

---

## ADR-012 — Reproducibility: frozen archive mirror, not version strings alone

**Decision:** `config/pacman.conf.build` points at
`https://archive.archlinux.org/repos/2026/11/01/$repo/os/$arch`; `packages.lock` is generated
from the built airootfs.

**Tradeoffs:** frozen mirrors mean security fixes after 2026-11-01 are NOT in the ISO — the
installed system immediately gets rolling mirrors + `[ar0x]` so `ar0x-update` fixes that at
first boot. Two `pacman.conf` files must be maintained, which is RISK-006. The benefit is a
build that can be reproduced months later, which is essential for debugging a bad ISO.

---

## ADR-013 — ISO compression: zstd level 15, 1 MiB blocks

**Decision:** squashfs with `-comp zstd -Xcompression-level 15 -b 1M`.

| Level | Ratio | Build CPU | Live boot |
|---|---|---|---|
| 9 | baseline | fast | fastest |
| **15** ✅ | ≈ 8–12% better than 9 | moderate | good |
| 19 | ≈ 3–6% better than 15 | ~40% slower | slightly slower decompression |

**Tradeoff:** level 15 hits the ~2 GB target without making rebuilds painful. Level 19 is the
third size-reduction lever in PROJECT_PLAN.md §7 if the gate fails.

---

## ADR-014 — Secure Boot: supported but not enforced

**Decision:** ship shim + signed GRUB/kernel; MOK enrollment is an explicit manual user action.

**Tradeoffs:** enforcing Secure Boot by default would require Microsoft-signed shim, a managed
key, and a documented recovery path for users who lose the MOK — plus ⚠️ RISK-007, where a
botched enrollment can soft-brick a machine. v0.1 provides the pieces and documents the step
in Phase 11; default enforcement is a v0.2 decision.

---

## ADR-015 — Color palette and identity (locked)

**Decision (Phase 7 refined):** the eight `AR0X_*` hex pins in `config/versions.env` are
the authoritative palette. `config/branding/palette.conf` is the human-readable brand
specification and MUST mirror them byte-for-byte. Every theme (GRUB, Plymouth, SDDM,
GTK, Qt, Waybar, Hyprland borders, fastfetch, SVG masters, raster generators, XCursor
binaries) derives its colours from that chain. `tools/configure-branding.sh --check` and
`tools/validate-versions.sh` both fail on any drift.

| Token | Hex | Role |
|---|---|---|
| `AR0X_VOID` | `#07090F` | Background |
| `AR0X_SURFACE` | `#11151F` | Panels / inactive borders |
| `AR0X_CYAN` | `#00E5FF` | Primary accent |
| `AR0X_MAGENTA` | `#FF2E88` | Secondary accent |
| `AR0X_LIME` | `#A8FF60` | Success / prompts |
| `AR0X_TEXT` | `#D7E0EE` | Foreground |
| `AR0X_MUTED` | `#6B7891` | Dimmed |
| `AR0X_ALERT` | `#FF5C57` | Errors |

**Tradeoff:** a dark, high-contrast neon palette is striking but can reduce readability in bright
environments and is not accessibility-neutral. Contrast ratio `AR0X_CYAN` on `AR0X_VOID` is
≈ 12.8:1 (passes WCAG AA). ⚠️ **Phase 7 correction:** the earlier promise of an
`AR0X_HIGH_CONTRAST` variant was NOT implemented in Phase 7 — it depends on the
`ar0x-theme` package (Phase 8) and a live GTK/Qt QA loop. It is now a **v0.2** item;
the mono SVG (`currentColor`) is the only light-media variant shipped in v0.1.

---

## ADR-016 — Package repository: `[ar0x]` with signed `repo-add`

**Decision:** a signed custom repo appended **after** `[core]`/`[extra]` in the installed
`pacman.conf`; built in GitHub Actions with `makepkg` in a clean `archlinux:base-devel` container.

**Tradeoffs:** `reprepro` (Debian) is irrelevant on Arch. `repo-add -s` is simple but has no
staging/promotion workflow — the `testing` vs `stable` channel split is implemented with two
repo directories and a CI job that copies packages between them, not with reprepro-style suites.
`SigLevel = Required` on `[ar0x]` means a lost signing key blocks all updates — mitigated by
shipping `ar0x-keyring` and keeping an offline backup (§14 manual intervention).

---

## ADR-017 — Two-tier package sourcing: frozen snapshot + signed `[ar0x]` repo

**Status:** ACCEPTED (Phase 2 refinement of ADR-012). **Date:** 2026-11-03.

**Problem discovered in Phase 2:** the frozen `2026/11/01` Arch snapshot cannot supply two HARD pins.
`hyprland 0.57.1` was released 2026-11-03 (today) and is in `[extra-testing]` only — `[extra]`
has `0.57.0-3`. `calamares 3.4.3` is not in the official repos at all. A naive fix (enable
`[extra-testing]`) silently promotes dozens of unrelated testing packages and destroys the
package-level reproducibility promised by ADR-012.

**Decision:** two tiers, with strict ordering in `config/pacman.conf.build`:

```
[ar0x]        <- FIRST, Server = file:///opt/ar0x-build/repo/x86_64   (HARD pins)
[core]        <- frozen archive.archlinux.org/repos/2026/11/01/...
[extra]       <- frozen archive.archlinux.org/repos/2026/11/01/...
```

- Tier 1 (`SNAPSHOT`): everything else, resolved from the frozen mirror.
- Tier 2 (`HARD`): `hyprland 0.57.1`, `calamares 3.4.3`, and the 8 ar0x-authored packages are
  compiled from exact upstream tarballs with `makepkg` in a clean chroot (Phases 8/9), signed with
  `repo-add -s`, then consumed by `mkarchiso` from the local `file://` repo.
- pacman resolves a package from the **first** repo that provides it, so `hyprland 0.57.1` wins.
- `AR0X_HARD_PIN_REPO_PRIORITY="first"` in `config/versions.env` records this invariant.

**Alternatives rejected:**

| Option | Why rejected |
|---|---|
| Enable `[extra-testing]` | Dozens of unpinned testing packages; reproducibility lost |
| Move the snapshot to `2026/11/03` | Same-day archive snapshot may not exist; still fails to supply Calamares |
| Downgrade the ISO to `hyprland 0.57.0-3` | Silently contradicts the locked HARD pin; 0.57.1 fixes NVIDIA black screens and keybinds |
| Install `hyprland` by copying a `.pkg.tar.zst` into `airootfs/` | Bypasses pacman dependency resolution and signature checks |

**Tradeoff accepted:** the build host (and CI) needs a real source-build toolchain and must build
Calamares + Hyprland before the ISO can be assembled. That adds ~15–30 min to a cold build and
makes Phase 9 a hard prerequisite of `build-iso.sh` (already reflected in `DEPENDENCY_GRAPH.md`:
`T5 → R2 → S1`). In exchange, every package in the ISO is either frozen or checksum-pinned.

**Reversal cost:** LOW — change one repo ordering line and one PKGBUILD source.

## ADR-018 — archiso 92 customization via pacman hooks; two-tier SigLevel

**Status:** ACCEPTED (Phase 3). **Date:** 2026-11-03.

**Decision 1 — no `customize_airootfs.sh`.** archiso 92's `_make_customize_airootfs` still
executes `airootfs/root/customize_airootfs.sh` but emits
*"customize_airootfs.sh is deprecated! Support for it will be removed in a future archiso
version"*. ar0x uses `archiso/airootfs/etc/pacman.d/hooks/*.hook` instead: mkarchiso forces
`HookDir = <airootfs>/etc/pacman.d/hooks/`, so hooks are the supported, non-deprecated path.
`tools/bootstrap.sh --check` fails if a `customize_airootfs.sh` appears.

| Option | Pros | Cons |
|---|---|---|
| **pacman hooks ✅** | supported, idempotent, run at the right point in `pacstrap` | must be expressed as `[Trigger]`/`[Action]` units |
| `customize_airootfs.sh` | simple imperative chroot script | ⚠️ deprecated, removed in a future archiso |
| systemd units/presets in `airootfs/etc/systemd/` | good for runtime enablement | do not run at build time |

**Decision 2 — build-time `[ar0x]` uses `SigLevel = Optional TrustAll`; installed system uses
`SigLevel = Required`.** A local `file://` repo of packages built and SHA256-verified on the same
machine does not need a remote trust chain, and requiring a trusted key *before* the first
`ar0x-keyring` install is a chicken-and-egg problem. The installed
`config/pacman.conf.installed` (Phase 9) is the security boundary and will use `Required` with the
key shipped by `ar0x-keyring`.

**Decision 3 — disposable staged profile.** `bootstrap.sh` copies `archiso/` →
`$AR0X_BUILD_ROOT/profile/` and renders `pacman.conf` there, so `mkarchiso` never writes generated
files into the Git checkout. Cost: one small copy. Benefit: `git status` stays clean and
`--check` can verify `config/` ↔ `archiso/` sync.

**Sequencing:** the `[ar0x]` block is **dropped** in Phase 3 (no db yet, otherwise `pacman -Sy`
fails) and **kept** in Phase 11 after Phases 8/9 build the HARD-pinned packages.
**Reversal cost:** LOW (one hook file + two config lines).

## ADR-019 — Stock LTS kernel contract, zstd initramfs, fontless GRUB theme

**Status:** ACCEPTED (Phase 4). **Date:** 2026-11-03.

**Decision 1 — zero kernel patches, zero compilation.** The user chose Stock LTS. ar0x ships
the binary `[core] linux-lts 6.18.59-1` package. `config/kernel/ar0x-lts.config` is an **audit
fragment**, not a build input: 59 exact `CONFIG_*` requirements with `make menuconfig` paths.
`build-kernel.sh --audit-config` checks them against `/proc/config.gz` or
`/boot/config-linux-lts`; `--lock-config` stores the complete frozen `config.x86_64` in
`out/kernel-config.lock`. `=m` in the fragment accepts `=y` too (Arch moves symbols between
built-in and module across point releases).

| Option | Pros | Cons |
|---|---|---|
| **Stock LTS ✅** | Arch-tested module set, signed, reproducible, zero maintenance | Cannot enable a config option Arch left off |
| Custom `.config` + compile | full control | 15–40 min/build, forked kernel, RISK-001 |
| Out-of-tree patches | quick hardware fix | DKMS failure can brick the ISO |

**Decision 2 — `COMPRESSION="zstd"` and `PRESETS=('default')` only.** `CONFIG_RD_ZSTD=y` is
verified in the pinned kernel. zstd boots far faster than upstream's `xz -9e`. Dropping the
`-fallback` initramfs halves the initramfs payload on a ~2 GB ISO; the FAILSAFE GRUB/syslinux
entries are the recovery path instead.

**Decision 3 — fontless GRUB gfxmenu theme.** archiso 92 builds the EFI binary with
`grub-mkstandalone --themes=""` and embeds no font. Named `*-font` keys in `theme.txt` would
cause unpredictable fallback, so the theme omits them and `grub.cfg` has a guarded `loadfont`.
**Phase 7 confirmed** the fontless design and ships NO `ar0x-16.pf2`; the guard simply
stays dormant.

**Decision 4 — deterministic generated PNG artwork.** `tools/gen-theme-assets.sh` embeds a
pure-zlib PNG encoder (no ImageMagick/font/network). 24 images are byte-reproducible and licence-clean; **Phase 7 replaced** the
bitmap-font placeholder wordmark with the official SVG-derived logomark at the
same paths and dimensions (shared geometry in `tools/lib/ar0x_logo.py`).

**Reversal cost:** LOW for the theme/initramfs; **HIGH** for the kernel (see RISK-001).

## ADR-020 — NetworkManager, balanced hardening, and the pacman.conf split

**Status:** ACCEPTED (Phase 5). **Date:** 2026-11-07.

**Decision 1 — NetworkManager, not systemd-networkd.** Best WiFi/roaming, GUI
integration and Calamares support. `systemd-networkd.service`,
`systemd-networkd-wait-online.service`, `dhcpcd.service`, `iptables.service` are
explicitly `disable`d in `/etc/systemd/system-preset/50-ar0x.preset` so two DHCP
clients never fight over one link. Connectivity probing is OFF for privacy.

| Option | Pros | Cons |
|---|---|---|
| **NetworkManager ✅** | WiFi, VPN, GUI, Calamares | Heavier than networkd |
| systemd-networkd | tiny, declarative | No roaming/WiFi GUI |
| dhcpcd | simple | No managed WiFi |

**Decision 2 — balanced sysctl, NOT paranoid hardening.** Audience = developers.
`kernel.perf_event_paranoid=2` (not 3), `kernel.yama.ptrace_scope=1` (not 2),
`kernel.unprivileged_userns_clone=1` (not 0), `io_uring` left enabled. Setting
the paranoid values would break `perf`/`bpftrace`, `gdb`/`strace`, Flatpak and
rootless containers. The rejected values are recorded as comments in
`config/system/sysctl.d/50-ar0x-security.conf`.

**Decision 3 — AppArmor stays in COMPLAIN mode (RISK-008).** A systemd drop-in
runs `aa-complain /etc/apparmor.d/*` after `apparmor.service` loads profiles.
Enforcing untested profiles breaks xdg-desktop-portal, PipeWire and GPU drivers.
Graduation to enforce is a v0.2 ADR.

**Decision 4 — two pacman.conf files, strictly separated (RISK-006).**
`config/pacman.conf.build` is FROZEN (`archive.archlinux.org/repos/2026/11/01/`)
and is rendered into `archiso/pacman.conf` for `mkarchiso` only.
`config/pacman.conf.installed` is ROLLING (`Include = /etc/pacman.d/mirrorlist`)
with `[ar0x] SigLevel = Required` and becomes `/etc/pacman.conf` on the target.
Two independent validators assert the installed file contains no archive URL.

**Decision 5 — passwordless LIVE user only (RISK-033).** `config/system/shadow`
has empty password fields for `root` and `ar0x`, matching archiso releng, so the
installer runs without auth. Calamares (Phase 10) creates real hashed passwords
on the target. This file is never installed on a disk.

**Reversal cost:** LOW (edit a drop-in / preset / sysctl and rebuild).

## ADR-021 — Lua-only desktop, Qt6 SDDM theme, balanced toolkit theming

**Status:** ACCEPTED (Phase 6). **Date:** 2026-11-07.

**Decision 1 — Lua config, modular, official-API-only.** `hyprland.lua` requires
10 `lua/*.lua` modules in a fixed order (shared data → env → monitors → look →
binds/rules → autostart LAST). Only `hl.*` calls and config keys appearing in
Hyprland 0.57's official `example/hyprland.lua` are used. Shared state is
returned as tables instead of relying on globals crossing protected scopes.
Two independent validators fail on any `hyprland.conf` anywhere in the tree
(RISK-002).

| Option | Pros | Cons |
|---|---|---|
| **Modular Lua ✅** | isolated errors, reviewable, 0.57-native | needs `require()` path discipline |
| One 600-line Lua file | no module resolution | one syntax error kills everything |
| hyprlang `.conf` | familiar | REMOVED in 0.57, no converter |

**Decision 2 — SDDM 0.21 Qt6 greeter, X11 display server.** GDM pulls
GNOME/libadwaita (rejected in Phase 1); LightDM greeters are X11/GTK-centric.
SDDM's QML uses only `QtQuick` + `SddmComponents 2.0`, no `QtGraphicalEffects`
or `Qt5Compat`. `metadata.desktop` declares `QtVersion=6` and `Theme-API=2.0`.
`InputMethod=` disables SDDM 0.21's on-screen keyboard, which otherwise draws
over the login form (RISK-038).

**Decision 3 — GTK3/GTK4/Qt5/Qt6 theming without AUR dependencies.**
GTK3 = `Adwaita-dark` (shipped by `gtk3`) + `~/.config/gtk-3.0/gtk.css`
overrides. GTK4/libadwaita = `GTK_THEME=Adwaita-dark` + 20 `@define-color`
variables in `~/.config/gtk-4.0/gtk.css`. Qt5/Qt6 = `qt5ct`/`qt6ct` with
`style=Fusion` and each package's own `darker.conf`. Icons = `Papirus-Dark`
(`[extra]`), cursor = `Adwaita` placeholder in Phase 6, **REPLACED in Phase 7** by the
generated `ar0x-cursors` XCursor theme (RISK-040 CLOSED), fonts = Inter +
JetBrains Mono Nerd + Noto. **Rejected:** Kvantum + AUR GTK themes (breaks
reproducibility), `libadwaita-without-adwaita-git` (patched system library),
and Bibata/Capitaine cursors (AUR-only). A fully standalone ar0x GTK theme
engine is deferred to the `ar0x-theme` package in Phase 8 (RISK-042).

**Decision 4 — deterministic generated art at the FINAL paths (KEPT in v0.1).**
`gen-desktop-assets.sh` writes three 3840×2160 PNGs and a 1920×1080 SDDM
background with a pure-zlib encoder (no ImageMagick, no fonts, no network,
~250 KB total, byte-reproducible). `hyprpaper.conf`, `hyprlock.conf` and
`theme.conf` reference the installed paths from Phase 1's
`assets/wallpapers/PLACEHOLDERS.md`. Phase 7 finalised the **BOOT** art (GRUB,
Plymouth, syslinux) at the same paths from the official SVG geometry, and kept the
generated geometric wallpapers as the deliberate v0.1 art (licence-clean,
reproducible, ~250 KB). Committing large AI art would risk the 2.2 GiB ISO gate
and licensing. A photographic/vector wallpaper set remains a v0.2 item.

**Decision 5 — no global `GDK_BACKEND` (RISK-039).** Phase 5's choice is
inherited: forcing Wayland globally breaks GTK apps under XWayland. Both
`lua/env.lua` and `/etc/environment.d/20-ar0x-desktop.conf` are asserted free
of it by `--check` and `validate-versions.sh`.

**Decision 6 — one systemd preset owner.** `enable sddm.service` was ADDED to
Phase 5's `config/system/systemd/system-preset/50-ar0x.preset` rather than
creating a Phase 6 preset. Two files owning unit state drift apart.

**Reversal cost:** LOW for configs, MEDIUM for the SDDM QML theme (needs a Qt6
greeter to re-test).

## ADR-022 — SVG-authoritative brand identity, standard XCursor, no AUR fetch tool

**Status:** ACCEPTED (Phase 7). **Date:** 2026-11-07.

**Decision 1 — one authoritative geometry.** `assets/logo/ar0x-logo.svg`
(`viewBox="0 0 512 512"`) is the master. `tools/lib/ar0x_logo.py` mirrors its
octagon, chevron, underscore, node rect and stroke widths, and is imported by
BOTH `tools/gen-theme-assets.sh` (boot art) and `tools/gen-branding-assets.sh`
(logo PNGs). `--check` parses the SVG XML and asserts equality with the module,
so the boot splash and the standalone logo cannot drift apart.

| Option | Pros | Cons |
|---|---|---|
| **SVG + shared Python geometry ✅** | no renderer needed, byte-reproducible, one source | raster is a round-join approximation (RISK-046) |
| Render SVG with Inkscape/rsvg at build time | pixel-exact | extra host dependency, non-deterministic across versions |
| Two independent generators | simple | boot art and logo silently diverge |

**Decision 2 — real XCursor theme, not a compiled hyprcursor theme.**
`tools/lib/ar0x_xcursor.py` writes the documented `Xcur` binary format directly
(5 shapes × 3 nominal sizes + 12 aliases) and parses every file back. Hyprland,
XWayland, GTK3/GTK4 and Qt all read standard XCursor themes from
`/usr/share/icons/<theme>/cursors/`. `Inherits=Adwaita` covers any unauthored
name. RISK-040 is CLOSED. Rejected: a hand-authored `manifest.hl` without
compiled cursors (not loadable) and `hyprcursor-util` (unavailable on the build
host). A compiled hyprcursor variant is a v0.2 item.

**Decision 3 — `screenfetch` yes, `neofetch` no.** `screenfetch 3.9.9-1` is an
official `[extra]` package and gets a branded `-a` art script + the
`/usr/local/bin/ar0x-screenfetch` wrapper. `neofetch` was removed from Arch
`[extra]` and is AUR-only (RISK-010); its config is **shipped** for post-install
use but the package is **not** on the ISO. fastfetch remains the default and
uses `logo.type = "file"` with `$1`–`$9` colour placeholders.

**Decision 4 — identity written twice.** `/etc/os-release` AND
`/usr/lib/os-release` both carry the ar0x identity because Arch's `filesystem`
package makes the former a symlink to the latter. `/etc/issue` uses only the
whitelisted agetty escapes; `/etc/issue.net` is plain text.

**Tradeoffs accepted:** no live art render (RISK-044 HIGH); live Inter text in
the wordmark SVG (RISK-045); round-join raster approximation (RISK-046); no
compiled hyprcursor theme and no neofetch package in v0.1; no
`AR0X_HIGH_CONTRAST` variant yet (v0.2).

**Reversal cost:** LOW for identity/ASCII/SVG; MEDIUM for the XCursor set
(replace `/usr/share/icons/ar0x-cursors/` and re-run `--sync`).

---

## ADR-023 — Plain-GTK4 tools, non-root signed updates, five packages deferred to Phase 9

**Status:** ACCEPTED (Phase 8). **Date:** 2026-11-07.

**Decision 1 — plain `Gtk.Application`, NOT libadwaita.**
`/usr/bin/ar0x-welcome` is a GTK4 + PyGObject application styled with
`Gtk.CssProvider` loaded from `/usr/share/ar0x/welcome/ar0x-welcome.css`.
libadwaita hard-codes Adwaita and ignores custom GTK4 CSS (RISK-042), which
would erase the ADR-015 cyberpunk palette.

| Option | Pros | Cons |
|---|---|---|
| **Plain GTK4 + CssProvider ✅** | custom CSS works; only `gtk4` + `python-gobject` (both official `[extra]`) | no `Adw.PreferencesWindow` polish |
| libadwaita | modern widgets, less code | overrides our CSS → palette lost |
| Qt6 / Slint | consistent with SDDM QML | another toolkit + another runtime on a Developer Edition ISO |
| TUI (dialog/bubbletea) | headless-testable here | violates the "GUI welcome app" Phase 8 requirement |

`gi` is imported **lazily** inside `run_gui()`. This is deliberate: the sandbox
has no GTK4, no PyGObject, no display, so a module-level `import gi` would make
`--self-test` impossible. On a real machine with `python-gobject` missing the
app prints `sudo pacman -S gtk4 python-gobject` and exits 3 instead of crashing.
Test hooks (`AR0X_WELCOME_DATADIR`, `AR0X_WELCOME_MARKER`, `AR0X_INFO_BIN`,
`AR0X_UPDATE_BIN`) are read at **call time** so a disposable prefix under
`build/tools-prefix/` can stand in for `/usr`.

**Decision 2 — `ar0x-update` refuses bare root and verifies the `[ar0x]` db signature.**
`--check` is the default and runs unprivileged: it asserts the per-repo
`SigLevel = Required` (rejecting `Never`/`Optional`/`TrustAll`), runs an
isolated `pacman -Sy` against a temporary `--dbpath` to verify `ar0x.db.sig`,
then uses the `checkupdates` algorithm (temp dbpath + symlink to the real
`local` db + `fakeroot`) for `pacman -Qu`. It never touches
`/var/lib/pacman/sync`, so it cannot cause a partial upgrade. `--noconfirm`,
`-Sy` alone, `--overwrite`, `-d`, `--nodeps` and `--force` are hard-rejected.
`--upgrade` goes through `pkexec` with an explicit argv list (never
`shell=True`) and still requires an interactive `yes`.

| Option | Pros | Cons |
|---|---|---|
| **Signed, isolated, non-root wrapper ✅** | matches §9; polkit GUI on Wayland; no partial upgrade | ~25 lines of Bash we own; needs `fakeroot` |
| `pacman -Sy && pacman -Qu` | trivial | ⚠️ desynchronises the db; Arch forbids partial upgrades |
| `checkupdates` from `pacman-contrib` | upstream-maintained | still needs `fakeroot`; harder to assert a per-repo SigLevel |
| GUI software centre (Discover/GNOME Software) | polished | huge dependency tree, pulls a second DE |

**Decision 3 — two first-boot units, not one.**
A system unit cannot open a Wayland window; a user unit has no
`ConditionFirstBoot`. `ar0x-firstboot.service` (root, oneshot,
`ConditionFirstBoot=yes`) runs `/usr/lib/ar0x/ar0x-firstboot`, which refuses to
proceed if any `NOPASSWD` sudoers rule survived the install (RISK-013), enables
`ar0x-welcome.service` globally via a plain symlink (no D-Bus needed in a
Calamares chroot), and stamps `/var/lib/ar0x/firstboot-done`. The user unit uses
`ExecCondition` on `~/.config/ar0x/welcome-done`. Neither unit is in
`50-ar0x.preset`: that preset is the single owner of LIVE-ISO system service
state, and the package is not installed on the ISO until Phase 9/10.

**Decision 4 — five of eight packages are deferred to Phase 9.**
`ar0x-theme`, `ar0x-wallpapers`, `ar0x-hypr-config`, `ar0x-keyring` and
`ar0x-meta` get a documented `README.md` skeleton but NO PKGBUILD. Their
sources already live in `config/desktop/**`, `config/branding/**` and
`assets/**` and are installed into the live ISO by the Phase 6/7 `--sync`
chains. A second package owning the same `/etc/skel/**` paths would produce
`error: failed to commit transaction (conflicting files)` during a Calamares
install. Phase 9 must record ONE owner per path before writing those PKGBUILDs;
`ar0x-keyring` additionally needs the offline GPG key. Consequently no
`ar0x-*` package is in `config/packages.x86_64` in Phase 8 — only the three
runtime dependencies `python`, `python-gobject`, `fakeroot` (RISK-048).

| Option | Pros | Cons |
|---|---|---|
| **3 real packages + 5 skeletons ✅** | buildable today, zero ownership conflicts, honest status | `ar0x-meta` not installable until P9 |
| All 8 PKGBUILDs now | matches §10 table literally | duplicate `/etc/skel/**` → pacman conflict; `ar0x-keyring` would need a fake key |
| Ship tools only in the airootfs overlay, no PKGBUILDs | simplest | no post-install updates, no `pacman -S ar0x-meta` acceptance criterion |

**Decision 5 — canonical configs with byte-identical mirrors and real checksums.**
`config/tools/{links.conf,extra-groups.conf,update.conf}` are CANONICAL;
`configure-tools.sh --sync` mirrors them into `packages/ar0x-*/` and refreshes
18 real SHA-256 sums. `--check` enforces 5 byte-identical pairs, one
derivation-only difference (`fastfetch.jsonc`), 5 https URLs vs `AR0X_URL_*`,
8 CSS hex pins vs `versions.env`, 4 groups / 23 packages with zero
AUR/`-git`/`-bin`, and zero premature `ar0x-*` ISO packages. Extras install via
`pkexec /usr/bin/pacman -S --needed` — never `--noconfirm`, never AUR (RISK-010).

**Tradeoffs accepted:** no live GTK4 render (RISK-047 HIGH); no signed repo or
`ar0x-meta` until Phase 9 (RISK-048 HIGH); PKGBUILDs not built with
`makepkg`/`namcap` here (RISK-049); five reserved link endpoints (RISK-050);
no libadwaita polish; `--upgrade` has no automatic rollback.

**Reversal cost:** LOW for the two CLI tools (rewrite a Bash script + refresh
sums); MEDIUM for the welcome app (replace GTK4 with libadwaita/Qt6 and re-do
the two units); MEDIUM for the 5 deferred packages (one-owner-per-path audit
then 5 new PKGBUILDs).

## ADR-024 — ONE OWNER PER PATH + PR-safe signed repository (Phase 9)

**Status:** ACCEPTED (2026-11-07). **Resolves** ADR-023's five deferred packages.
**Supersedes** the "5 skeletons, NO PKGBUILD until the ownership audit" decision;
it does NOT change ADR-017/018/020/021/022/023.

**Context.** Phase 6/7 `--sync` chains install **92 files** into the live ISO
under `archiso/airootfs/etc/skel/**` (`/.config/{gtk-3.0,gtk-4.0,hypr,kitty,...}`)
and `archiso/airootfs/usr/share/**` (backgrounds, GRUB/Plymouth/SDDM themes,
icons/cursors, `ar0x/branding`, `ar0x/logo`). ADR-023 correctly refused to write
five PKGBUILDs that would install into those same paths: `pacman` would abort a
Calamares install with `error: failed to commit transaction (conflicting files)`.

**Decision 1 — ONE OWNER PER PATH.** The overlay remains the SOLE owner of those
92 paths. The five packages install **package-private reference trees** instead:

| Owner | Exclusive paths |
|---|---|
| airootfs overlay (ISO only) | `/etc/skel/**`, `/usr/share/{backgrounds/ar0x,grub/themes/ar0x,plymouth/themes/ar0x,sddm/themes/ar0x,icons/ar0x-cursors,ar0x/branding,ar0x/logo}/**` |
| `ar0x-theme` | `/usr/share/ar0x/theme/**`, `/usr/bin/ar0x-apply-theme` |
| `ar0x-wallpapers` | `/usr/share/ar0x/wallpapers/**`, `/usr/bin/ar0x-apply-wallpapers` |
| `ar0x-hypr-config` | `/usr/share/ar0x/hypr-config/**`, `/usr/bin/ar0x-apply-hypr-config` |
| `ar0x-keyring` | `/usr/share/pacman/keyrings/ar0x{gpg,-trusted,-revoked}` |
| `ar0x-meta` | `/usr/share/doc/ar0x-meta/**` |

`ar0x-apply-{theme,hypr-config,wallpapers}` bridge stock-Arch installs
(`pacman -S ar0x-meta`) by copying 7 / 14 / 3 files into ONE user's
`$XDG_CONFIG_HOME` / `$XDG_PICTURES_DIR` with timestamped backups under
`<DEST>/ar0x-backups/`. No root, no network, no `/etc/skel` writes. Hyprland
config stays **Lua-only** (RISK-002). 31 canonical → package mirrors are
byte-identical, verified by `ar0x_repo.validate_mirrors()`.

`tools/lib/ar0x_pkgbuild.py::OVERLAY_OWNED` enumerates forbidden `$pkgdir/...`
prefixes; `validate_ownership()` proves `0/8` PKGBUILDs touch them. All 8
PKGBUILDs now exist with **57 / 57 SHA-256 sums** (56 real + 1 MANUAL `SKIP`).

**Decision 2 — NO PRIVATE KEY ON A PR WORKFLOW.** `validate-packages.yml` and
`build-packages.yml` run on `pull_request` (forks included) with **ZERO
secrets**. Only `release.yml` signs: `workflow_dispatch` on a protected ref or
a `v*` tag, a protected `release` Environment, and an explicit fork guard in
the job `if:`. `ar0x_repo.validate_workflows()` asserts this structurally. The
offline master key stays in `${AR0X_KEYS_DIR}/gnupg` (`0700`); CI uses a
dedicated signing subkey. RISK-051 is CRITICAL.

**Decision 3 — `SigLevel = Required`, never relaxed.** Installed `[ar0x]`
requires valid signatures on packages AND the database and inherits
`TrustedOnly`. `repo-add -s` alone does NOT create package signatures, so the
release workflow explicitly `gpg --detach-sign`s every tarball first, then
`repo-add -s -v --include-sigs`, then `SHA256SUMS.sig`. `ar0x-keyring` ships
`ar0x.gpg` + `ar0x-trusted` (`40-HEX-FPR:6:`) + `ar0x-revoked`, and its sourced
`.install` calls `pacman-key --populate ar0x` in `post_install()` /
`post_upgrade()`. `AR0X_REPO_REMOVE_OLD=0` preserves rollback (ADR-023).
The build-only `Optional TrustAll` config is NEVER installed (RISK-006).

| Option | Pros | Cons |
|---|---|---|
| **Package-private trees + appliers ✅** | all 8 PKGBUILDs buildable; zero pacman conflicts; stock-Arch users get the same look | theme data exists twice on disk; one extra `ar0x-apply-*` step on stock Arch |
| Put the 5 packages in the overlay too | no duplicate data | `pacman: conflicting files` during Calamares; breaks acceptance criterion 3 |
| Delete the overlay and ship only packages | single owner | live ISO loses its look before `pacman -S`; Phase 11 would have to install packages at build time |
| Sign in `build-packages.yml` (PRs) | simpler CI | **private key exposed to forked PR code** — unacceptable (RISK-051) |

**Tradeoffs accepted:** duplicate reference data (~small text/SVG/PNG trees);
`ar0x-keyring` cannot be built until the MANUAL air-gapped `--keygen` produces
`ar0x-public-key.asc`; no signed repo / publication (RISK-048); `makepkg`,
`namcap`, `shellcheck`, `gpg`, `repo-add`, `pacman` never ran here (RISK-049).

**Reversal cost:** LOW for the applier layout (move an `install -D` prefix and
refresh sums); HIGH for the signing/CI split (a leaked key requires rotation,
revocation via `ar0x-revoked`, and re-signing every published package).

## Summary of accepted tradeoffs

| ADR | We gained | We gave up |
|---|---|---|
| 001 Arch | current Wayland stack, easy ISO/repo | rolling-release stability |
| 002 glibc | binary app compatibility | ~100 MB size |
| 003 systemd | zero-glue services | minimalism |
| 004 GRUB | BIOS+UEFI+theming | bootloader simplicity |
| 005 Hyprland | cyberpunk aesthetics | must write Lua configs, fast upstream churn |
| 006 LTS kernel | stability, signed updates | newest hardware support |
| 007 Calamares 3.4.3 | Wayland keyboard fix | non-GitHub CI source |
| 008 SDDM | branded login | Wayland-native greeter |
| 009 AppArmor complain | no broken portals | enforcing MAC |
| 010 ext4 | installer reliability | snapshots |
| 011 zsh + bash scripts | great interactive UX | one-shell simplicity |
| 012 frozen snapshot | reproducibility | ISO freshness |
| 013 zstd 15 | size target | some build CPU |
| 014 SB optional | safety | out-of-box SB enforcement |
| 015 palette | coherent identity | light-theme accessibility |
| 016 repo-add | simplicity | staged repo promotion |
| 017 two-tier sourcing | exact HARD pins + reproducibility | host needs a source-build toolchain; ~15–30 min cold build |
| 018 hooks + staged profile | no deprecated code, clean Git tree | one extra profile copy; build-time repo SigLevel relaxed |
| 019 stock LTS + zstd initramfs | zero kernel maintenance, fast boot | cannot enable options Arch left off; no fallback initramfs |
| 020 NetworkManager + balanced hardening | developer tools keep working | less kernel lockdown than a hardened distro |
| 021 Lua-only desktop + Qt6 SDDM | 0.57 correctness, no AUR deps, reproducible art | no custom GTK/Qt theme engine yet (deferred to `ar0x-theme` P8) |
| 022 SVG-authoritative identity + standard XCursor | one geometry source, no compiler, RISK-040 closed | no compiled hyprcursor, no neofetch package, no live art render |
| 023 Plain-GTK4 tools + non-root signed update + 5 packages deferred | three offline-testable tools, zero file-ownership conflicts, real SHA-256 PKGBUILDs | no `ar0x-meta` until P9, GTK4 window never rendered here (RISK-047) |
| 024 ONE OWNER PER PATH + PR-safe signed repo | all 8 PKGBUILDs, zero pacman conflicts, private key never on a PR workflow | duplicate reference data on disk; generation/signing/publication remain MANUAL |
