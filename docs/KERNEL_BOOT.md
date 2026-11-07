# ar0x — Phase 4: Kernel Policy, Initramfs & Boot Branding

> Companion to [`tools/build-kernel.sh`](../tools/build-kernel.sh) and
> [`tools/gen-theme-assets.sh`](../tools/gen-theme-assets.sh).
> Verified against archiso 92-1, the `6.18.59-1` `linux-lts` packaging tag,
> GRUB 2.16, Plymouth `26.134.222-2` on 2026-11-03.

---

## ⚠️ RISK-001 — STOP. KERNEL PATCHING IS DISABLED.

**ar0x v0.1 ships the STOCK, UNPATCHED-BY-US binary kernel `linux-lts 6.18.59-1` from `[core]`
at the frozen `2026/11/01` snapshot.** No kernel is compiled. No `make menuconfig` is actually
run. No out-of-tree modules. `config/kernel/patches/` is empty and `tools/build-kernel.sh
--check` **fails** if any `*.patch` or `*.diff` appears there.

| Temptation | Why it is rejected |
|---|---|
| "just one small patch" | You own a kernel fork forever: rebase, re-review, re-sign, re-QA on every LTS point release |
| NVIDIA / Wi-Fi out-of-tree fix | DKMS rebuild failure at boot can make the ISO unbootable |
| Custom `.config` + `make -j$(nproc)` | 15–40 min per build, ~200 MB toolchain, non-reproducible `localversion`, loses Arch's tested module set |
| Enabling a `CONFIG_*` Arch left off | Requires a full rebuild; a wrong `CONFIG_RD_ZSTD` or `CONFIG_EFI_STUB` = black screen on UEFI |

**Arch already patches its own LTS kernel.** The `6.18.59-1` packaging tag contains
`0001-add-sysctl-to-allow-disabling-unprivileged-CLONE_NEW.patch` plus two `drm-amdgpu` GFP
fixes. Those are Arch's reviewed, signed decisions; ar0x inherits them and adds **zero**.

Reversal (a future phase, not an edit): open an ADR → store the patch → add a `PKGBUILD` that
rebuilds `linux-lts` in a clean chroot → re-sign → re-run the Phase 11 QEMU UEFI+BIOS matrix.

⚠️ **MANUAL INTERVENTION**: any kernel patch must be explicitly approved by you before I write it.

---

## 1. What Phase 4 delivers

| File (full path) | Purpose |
|---|---|
| `/home/user/ar0xOS/config/kernel/README.md` | RISK-001 policy, audit-fragment value convention |
| `/home/user/ar0xOS/config/kernel/ar0x-lts.config` | **Exact `make menuconfig` selections** — audit fragment of every `CONFIG_*` the stack needs |
| `/home/user/ar0xOS/config/mkinitcpio.conf` | `/etc/mkinitcpio.conf` for the installed system; adds `plymouth` + `kms` hooks, zstd |
| `/home/user/ar0xOS/config/mkinitcpio.d/linux-lts.preset` | `/etc/mkinitcpio.d/linux-lts.preset`; **default only**, no `-fallback` (ISO size) |
| `/home/user/ar0xOS/config/default/grub` | `/etc/default/grub` with `GRUB_THEME`, `quiet splash`, ar0x colors |
| `/home/user/ar0xOS/config/plymouth/plymouthd.conf` | `/etc/plymouth/plymouthd.conf` → `Theme=ar0x` |
| `/home/user/ar0xOS/assets/grub-theme/ar0x/{theme.txt,background.png}` | GRUB gfxmenu theme (1024×768) |
| `/home/user/ar0xOS/assets/plymouth/ar0x/{ar0x.plymouth,ar0x.script,logo.png,progress-{0..20}.png}` | Plymouth script-plugin splash |
| `/home/user/ar0xOS/assets/syslinux/splash.png` | 640×480 vesamenu background |
| `/home/user/ar0xOS/tools/gen-theme-assets.sh` | Deterministic pure-Python PNG generator (24 files, ~110 KB) |
| `/home/user/ar0xOS/tools/build-kernel.sh` | `--check / --sync / --audit-config / --lock-config / --rebuild-initramfs / --self-test` |
| Updated | `archiso/profiledef.sh` (`quiet splash`), `archiso/grub/grub.cfg`, `archiso/syslinux/syslinux.cfg`, `archiso/airootfs/etc/mkinitcpio.conf.d/archiso.conf`, `config/packages.x86_64` (`plymouth`) |

---

## 2. Exact commands

```bash
cd ~/ar0xOS

# --- Read-only validation (NO root; runs in this sandbox) ---------------------
./tools/build-kernel.sh --check
./tools/build-kernel.sh --self-test          # proves the config auditor works

# --- Regenerate the deterministic artwork (only after a palette change) ------
./tools/gen-theme-assets.sh

# --- Sync configs + assets into the archiso profile (NO root) ----------------
./tools/build-kernel.sh --sync

# --- Audit the real stock kernel (real Arch host) ----------------------------
./tools/build-kernel.sh --audit-config /boot/config-linux-lts
# or: ./tools/build-kernel.sh --audit-config /proc/config.gz   (auto gunzip)

# --- Lock the COMPLETE frozen .config for reproducibility --------------------
./tools/build-kernel.sh --lock-config
# writes /opt/ar0x-build/out/kernel-config.lock
# offline alternative: ./tools/build-kernel.sh --lock-config /path/to/config.x86_64

# --- Rebuild the initramfs inside the airootfs (⚠️ MANUAL, ROOT) -------------
sudo ./tools/bootstrap.sh --iso-only        # creates work/x86_64/airootfs
sudo ./tools/build-kernel.sh --rebuild-initramfs
```

`--rebuild-initramfs` expands to:

```bash
arch-chroot /opt/ar0x-build/work/x86_64/airootfs \
    /usr/bin/plymouth-set-default-theme -R ar0x
```

`-R` also runs `mkinitcpio -P`. If `plymouth-set-default-theme` is unavailable, the script falls
back to `arch-chroot ... mkinitcpio -P`.

### 2.1 Full `make menuconfig` selections

`config/kernel/ar0x-lts.config` is the answer to "give me the exact config". It uses valid
kernel-config syntax but is an **audit fragment**, interpreted by `build-kernel.sh`:

| Declared | Requirement on the real config |
|---|---|
| `CONFIG_FOO=y` | must be exactly `=y` |
| `CONFIG_FOO=m` | `=y` **or** `=m` (Arch builds most drivers as modules) |
| `# CONFIG_FOO is not set` | must be unset |

Groups, with their `make menuconfig` paths in the file comments:

- **General setup** — `IKCONFIG`/`IKCONFIG_PROC` (so `/proc/config.gz` exists), `CGROUPS`,
  `CGROUP_BPF`, `NAMESPACES`, `USER_NS`, `AUDIT`, `BPF_SYSCALL`, `SYSCTL`, `MULTIUSER`,
  `PREEMPT_VOLUNTARY`, `NO_HZ_FULL`
- **Initramfs** — `BLK_DEV_INITRD`, **`RD_ZSTD`** (critical: `COMPRESSION="zstd"`), `KERNEL_ZSTD`, `MODULES`
- **Live root** — `BLK_DEV_LOOP`, `SQUASHFS`, `SQUASHFS_ZSTD`, `OVERLAY_FS`, `ISO9660_FS`, `UDF_FS`,
  `FAT_FS`/`VFAT_FS`, `EXT4_FS`, `BTRFS_FS`, `XFS_FS`, `NLS_CODEPAGE_437`
- **UEFI/BIOS** — `EFI`, `EFI_STUB`, `EFIVAR_FS`, `VT`, `VT_CONSOLE`, `FRAMEBUFFER_CONSOLE`
- **DRM/Wayland** — `DRM`, `DRM_SIMPLEDRM`, `DRM_KMS_HELPER`, `FB` (simpledrm gives early KMS so
  Plymouth is not a black screen and Hyprland has outputs)
- **Input/net/audio/security** — `INPUT_EVDEV`, `HID*`, `UNIX`, `INET`, `NETFILTER`, `NF_TABLES`,
  `CFG80211`, `MAC80211`, `SND*`, `SECURITY`, **`SECURITY_APPARMOR`** (SELinux deliberately absent),
  `MICROCODE*`

The symbols asserted `=y` were verified in the actual `config.x86_64` at packaging tag
`6.18.59-1` (`IKCONFIG=y`, `IKCONFIG_PROC=y`, `CGROUPS=y`, `CGROUP_BPF=y`, `NAMESPACES=y`,
`USER_NS=y`, `AUDIT=y`, `BPF_SYSCALL=y`, `SYSCTL=y`, `MULTIUSER=y`, `PREEMPT_VOLUNTARY=y`,
`NO_HZ_FULL=y`, `BLK_DEV_INITRD=y`, `RD_ZSTD=y`, `KERNEL_ZSTD=y`, `MODULES=y`, `DEVTMPFS=y`).

⚠️ The upstream `config.x86_64` header at tag `6.18.59-1` says
`# Linux/x86 6.18.57 Kernel Configuration` — a packaging artefact. We pin the **package**
version `6.18.59-1`; `[core] 6.18.59-1` is the frozen pin and `6.18.60-*` (testing) is forbidden.

---

## 3. GRUB branding — how the theme actually reaches the EFI binary

Verified in `archiso/mkarchiso::_make_bootmode_uefi.grub`:

1. `grub-mkstandalone --themes="" ... "boot/grub/grub.cfg=${work_dir}/grub-embed.cfg"` —
   **no theme is embedded in the EFI binary**.
2. The embedded `grub-embed.cfg` searches for the ISO volume, sets `$root`, then
   `configfile (${ARCHISO_HINT})/boot/grub/grub.cfg`.
3. `files_to_copy += "${profile}/grub/"!(*.cfg)` — **every non-`.cfg` file/dir in
   `<profile>/grub/` is copied to `<ISO>/boot/grub/`**.

Therefore placing the theme at
`/home/user/ar0xOS/archiso/grub/themes/ar0x/{theme.txt,background.png}` puts it at
`/(ISO)/boot/grub/themes/ar0x/`, and `archiso/grub/grub.cfg` loads it with:

```grub
insmod png
insmod gfxmenu
insmod gfxterm
set gfxmode="auto"
terminal_output gfxterm
if [ -f /boot/grub/themes/ar0x/theme.txt ]; then
    set theme=/boot/grub/themes/ar0x/theme.txt
    export theme
fi
```

⚠️ **`theme.txt` contains no `*-font` keys** because `--themes=""` embeds no font. GRUB falls back
to its built-in font. `grub.cfg` keeps a guarded `loadfont ar0x-16.pf2`; **Phase 7 CONFIRMED
the fontless design** and ships no `.pf2` file, so the guard stays dormant.

The required modules (`png`, `gfxmenu`, `gfxterm`, `all_video`) are already in archiso 92's
`grubmodules` list, so `insmod` is safe.

### 3.1 BIOS syslinux

`archiso/syslinux/syslinux.cfg` uses **`UI vesamenu.c32`** (not `menu.c32`) so
`MENU BACKGROUND splash.png` works. mkarchiso copies `*.c32` and `splash.png` from the profile
and the airootfs's `syslinux` package. `MENU COLOR` uses `#RRGGBB` foreground and `#AARRGGBB`
background (transparent so the artwork shows). Three entries: normal, failsafe
(`nomodeset plymouth.enable=0 loglevel=7`), and text console (`multi-user.target`).

---

## 4. Plymouth theme

`/home/user/ar0xOS/assets/plymouth/ar0x/ar0x.plymouth`:

```ini
[Plymouth Theme]
Name=ar0x
Description=ar0x 0.1.0 Neon Root boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/ar0x
ScriptFile=/usr/share/plymouth/themes/ar0x/ar0x.script
```

`ar0x.script` uses `Window.SetBackgroundTopColor/BottomColor` (converted from
`#07090F` / `#11151F` to 0–1 floats), a `logo.png` sprite, and 21 pre-rendered
`progress-N.png` frames driven by `Plymouth.SetBootProgressFunction`.

**Initramfs hook order** (verified against Arch's `plymouth` package):
`base udev microcode plymouth modconf memdisk archiso … block filesystems keyboard`.
`plymouth` must be **after `udev`** (needs `/dev`) and **before any passphrase prompt**.
`tools/build-kernel.sh --check` enforces that order in both the live drop-in and the base config.

⚠️ **Known limitation**: the script has no message renderer (no label plugin in the initramfs),
so LUKS passphrase prompts fall back to the `details` text theme. v0.1 ships unencrypted ext4
(Phase 10), so this is acceptable. For encrypted installs run
`plymouth-set-default-theme -R details`, or boot the FAILSAFE entry.

---

## 5. Artwork — deterministic, not opaque blobs

`tools/gen-theme-assets.sh` is `#!/bin/bash` + `set -euo pipefail`, embeds a pure-Python
zlib PNG encoder (no ImageMagick, no fonts, no network, no root) and produces:

| File | Size |
|---|---|
| `assets/grub-theme/ar0x/background.png` | 1024×768 |
| `assets/syslinux/splash.png` | 640×480 |
| `assets/plymouth/ar0x/logo.png` | 320×80 |
| `assets/plymouth/ar0x/progress-{0..20}.png` | 400×6 each |

**Phase 7 FINAL ART (RISK-031 CLOSED).** The old bitmap-font placeholder wordmark is gone.
`tools/gen-theme-assets.sh` now draws the OFFICIAL 512×512 logomark from
`tools/lib/ar0x_logo.py` (geometry mirrored from `assets/logo/ar0x-logo.svg`) into
all three boot surfaces at the SAME paths and dimensions. GRUB `theme.txt` was
re-laid out (`boot_menu top = 34%`) so the menu never overlaps the logo. The
5×7 bitmap font remains only for the short "ar0x" caption. Palette comes from
`config/versions.env` (ADR-015): void `#07090F`, surface `#11151F`, cyan
`#00E5FF`, magenta `#FF2E88`, lime `#A8FF60`, text `#D7E0EE`, muted `#6B7891`.

Regenerate + propagate: `./tools/gen-theme-assets.sh && ./tools/build-kernel.sh --sync`.
Full style rules: `docs/BRANDING_GUIDE.md`.

---

## 6. Tradeoffs

| Decision | Alternatives | Why |
|---|---|---|
| Stock LTS binary kernel | custom compile + patches | User chose Stock LTS; RISK-001; reproducible, Arch-tested module set |
| Audit fragment, not full `.config` in Git | ship the 11k-line `config.x86_64` | `--lock-config` stores the full file in `out/`; the fragment is reviewable and machine-checkable |
| `=m` accepts `=y` in the auditor | exact-value compare | Arch moves symbols between built-in/module across point releases |
| `COMPRESSION="zstd"` | upstream `xz -9e` | `CONFIG_RD_ZSTD=y` verified; far faster live-boot decompress |
| `PRESETS=('default')` only | also build `-fallback` | Halves initramfs payload on a ~2 GB ISO; failsafe GRUB entries are the recovery path |
| Fontless GRUB theme | custom `ar0x.pf2` | archiso embeds no font; built-in font is guaranteed. **Phase 7 confirmed this** and ships no font |
| `UI vesamenu.c32` | `menu.c32` (text) | Required for `MENU BACKGROUND`; costs one `.c32` already shipped |
| Script-plugin Plymouth | `two-step` / `fade-in` plugins | No compiled plugin, tiny initramfs footprint, deterministic frames |

---

## 7. Manual-intervention register (Phase 4)

| # | Action | Why manual |
|---|---|---|
| 1 | Approve any kernel patch | RISK-001; none are applied in v0.1 |
| 2 | `sudo ./tools/build-kernel.sh --rebuild-initramfs` | Needs root + an existing airootfs |
| 3 | `--lock-config` on a real host | Needs outbound internet (GitLab) |
| 4 | Visual QEMU UEFI + BIOS splash QA (Phase 11) | Needs KVM; cannot verify graphics in a chroot |
| 5 | ✅ DONE in Phase 7: replaced placeholder PNGs with SVG-derived logomark | Design decision; `gen-theme-assets.sh` regenerates them |
| 6 | `plymouth-set-default-theme -R details` for LUKS | Only if encrypted installs are wanted |

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Black screen after GRUB | missing `CONFIG_RD_ZSTD` / wrong initramfs compression | `--audit-config`; use the FAILSAFE entry (`plymouth.enable=0 nomodeset loglevel=7`) |
| GRUB shows plain text menu | theme file not at `/boot/grub/themes/ar0x/` | `./tools/build-kernel.sh --sync`; check `archiso/grub/themes/ar0x/theme.txt` |
| GRUB menu labels invisible | no font loaded | Built-in font is used; the guarded `loadfont ar0x-16.pf2` activates only if a font is ever shipped (not in v0.1) |
| BIOS menu ignores background | `UI menu.c32` instead of `vesamenu.c32` | `syslinux.cfg` must use `UI vesamenu.c32` |
| Plymouth never appears | `plymouth` missing from `packages.x86_64` or hook order wrong | `--check` fails on both |
| `plymouth-set-default-theme: command not found` | `plymouth` package absent in airootfs | `sudo pacman -S plymouth` on host; ensure package list synced |
| LUKS password invisible | no message renderer in the script theme | `plymouth-set-default-theme -R details` or FAILSAFE entry |
| `--lock-config` 404 | wrong GitLab tag | URL uses full `${AR0X_KERNEL_VERSION}` = `6.18.59-1`, not `6.18.59` |
| `CONFIG_X: required =y, found n` | wrong kernel (`linux` instead of `linux-lts`) | Boot/install `linux-lts 6.18.59-1` from the frozen snapshot |

---

## 9. Phase 4 risks

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| **RISK-001** | ⚠️ **CRITICAL** | Custom kernel patch / compile | Zero patches, stock LTS, `--check` fails on any `*.patch`/`*.diff` |
| **RISK-027** | **HIGH** | `CONFIG_RD_ZSTD` absent → initramfs won't unpack | Asserted `=y` in fragment; `--audit-config` on the real kernel |
| **RISK-028** | **MEDIUM** | GRUB theme not embedded → unbranded boot | Verified archiso 92 `files_to_copy` non-`.cfg` rule; `--check` asserts `set theme=` |
| **RISK-029** | **MEDIUM** | Plymouth hook before `udev` → no splash / broken initramfs | `--check` enforces hook order in both configs |
| **RISK-030** | **LOW** | LUKS prompt invisible | Documented; `details` theme fallback + FAILSAFE entry |
| **RISK-031** | ✅ **CLOSED** | Placeholder art shipped as final | **Phase 7 replaced** the bitmap wordmark with the official SVG-derived logomark at the same paths/dimensions |

---

## 10. Verification actually performed in the sandbox

```bash
bash tools/gen-theme-assets.sh        # 24 PNGs generated, signatures + dimensions verified
./tools/build-kernel.sh --check       # ✅ PASSED (no root, no writes)
./tools/build-kernel.sh --self-test   # ✅ PASSED (positive + negative auditor test)
./tools/build-kernel.sh --sync        # byte-idempotent sync into archiso/
bash tools/validate-versions.sh
bash tools/bootstrap.sh --check
bash -n tools/*.sh tools/lib/*.sh
```

`mkinitcpio -P`, `plymouth-set-default-theme`, the QEMU splash check and the GitLab download
**cannot run here** (no root / no Arch userspace / no KVM). They are the manual host steps
in §2 and §7.
