# ar0x — Phase 3: Base System Bootstrap & Chroot Guide

> Companion to [`tools/bootstrap.sh`](../tools/bootstrap.sh).
> Verified against **archiso 92-1** source (`archiso/mkarchiso`, `docs/README.profile.rst`,
> `configs/releng/*`) on 2026-11-03.

---

## 1. What Phase 3 produces

| Artifact | Absolute path |
|---|---|
| Canonical build `pacman.conf` | `/home/user/ar0xOS/config/pacman.conf.build` |
| Canonical package list | `/home/user/ar0xOS/config/packages.x86_64` |
| Canonical bootstrap list | `/home/user/ar0xOS/config/bootstrap_packages.x86_64` |
| **Complete archiso 92 profile** | `/home/user/ar0xOS/archiso/` (`profiledef.sh`, `pacman.conf`, `packages.x86_64`, `bootstrap_packages.x86_64`, `airootfs/`, `grub/`, `syslinux/`, `efiboot/`) |
| Disposable staged profile | `/opt/ar0x-build/profile/` (generated, never in Git) |
| **Base filesystem (chroot target)** | `/opt/ar0x-build/work/x86_64/airootfs` |
| Bootstrap root tarball | `/opt/ar0x-build/out/ar0x-bootstrap-0.1.0-x86_64.tar.zst` |
| Base bootstrap ISO | `/opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso` |
| Reproducibility lockfile | `/opt/ar0x-build/out/packages.lock` |
| Build log | `/opt/ar0x-build/logs/02-bootstrap.log` |

⚠️ **This is a BASE BOOTSTRAP SMOKE TEST, not the release ISO.** It contains no Hyprland,
Calamares, Plymouth, ar0x branding or themes. Those arrive in Phases 4–10, and Phase 11 rebuilds
the ISO from the accumulated package list. This is intentional: a failure here is attributable to
the base system only.

---

## 2. Exact commands (native Arch host)

```bash
# --- 2.1 Prerequisite: Phase 2 must be done ----------------------------------
cd ~/ar0xOS
./tools/setup-build-env.sh --check      # must print ✅ --check completed
sudo ./tools/setup-build-env.sh --yes   # ⚠️ MANUAL: root, real Arch host

# --- 2.2 Read-only validation (no root, works in this sandbox) ---------------
./tools/bootstrap.sh --check

# --- 2.3 Keep the committed profile files in sync with config/ ----------------
./tools/bootstrap.sh --sync

# --- 2.4 Full base bootstrap --------------------------------------------------
sudo ./tools/bootstrap.sh               # ⚠️ MANUAL: root, ~40 GiB, 20–40 min

# --- 2.5 Alternatives ---------------------------------------------------------
sudo ./tools/bootstrap.sh --base-only   # tarball only (mkarchiso -m bootstrap)
sudo ./tools/bootstrap.sh --iso-only    # ISO + airootfs (mkarchiso -m iso)
sudo ./tools/bootstrap.sh --clean       # ⚠️ DESTRUCTIVE: deletes work/
```

`sudo ./tools/bootstrap.sh` expands to:

```bash
export SOURCE_DATE_EPOCH="$(date -u -d 2026-11-01 +%s)"
mkarchiso -v -m "bootstrap iso" \
  -w /opt/ar0x-build/work \
  -o /opt/ar0x-build/out \
  /opt/ar0x-build/profile
pacman -Q --sysroot /opt/ar0x-build/work/x86_64/airootfs \
  > /opt/ar0x-build/out/packages.lock
```

`SOURCE_DATE_EPOCH` is fixed to the frozen snapshot date so ISO9660 timestamps and file mtimes
are deterministic. `mkarchiso` must run as **root** (it calls `mount --bind`, `mknod`, `chroot`,
`mkfs.*`, `losetup`).

### 2.1 What `bootstrap.sh` stages

`archiso/` in the checkout is the canonical profile. The script copies it to
`/opt/ar0x-build/profile/` and only then modifies it, so `mkarchiso` never writes generated files
into your Git checkout:

1. `cp -af archiso/. /opt/ar0x-build/profile/`
2. delete every `.gitkeep` (they must never appear in the live root)
3. render `config/pacman.conf.build` → `<stage>/pacman.conf`, substituting
   `@AR0X_REPO_DIR@` with `$AR0X_REPO_DIR`
4. **drop** the marked `[ar0x]` repo block when `$AR0X_REPO_DIR/ar0x.db` does not exist
5. overlay `config/system/** → <stage>/airootfs/etc/**`,
   `config/desktop/skel/** → <stage>/airootfs/etc/skel/**`,
   assets → `/usr/share/...`, `config/branding/{os-release,lsb-release,issue,motd}` → `/etc/`

Points 4 and 5 are the ADR-017 sequencing solution: Phase 3 has no HARD-pinned packages yet, and
including a non-existent `[ar0x]` database would make `pacman -Sy` abort with *"failed to
synchronize all databases"*. Phase 11 keeps the block after Phases 8/9 build those packages.

---

## 3. The complete profile files

### 3.1 `/home/user/ar0xOS/archiso/profiledef.sh` — archiso 92 contract

| Key | Value | Why |
|---|---|---|
| `iso_name` / `iso_version` | `ar0x` / `0.1.0` | output name `ar0x-0.1.0-x86_64.iso` |
| `iso_label` | `AR0X_010` | ISO9660 volume label ≤ 32 chars |
| `install_dir` | `ar0x` | ⚠️ must match `^[a-z0-9]+$`, ≤ 30 chars — underscores are **not** allowed |
| `arch` | `x86_64` | resolves `packages.x86_64` |
| `buildmodes` | `('bootstrap' 'iso')` | emits a root tarball **and** a bootable ISO |
| `bootmodes` | `('bios.syslinux' 'uefi.grub')` | Phase 11's two QEMU test targets. `uefi.grub` is mutually exclusive with `uefi.systemd-boot` |
| `packages` / `bootstrap_packages` | `packages.x86_64` / `bootstrap_packages.x86_64` | archiso 92 requires both files |
| `pacman_conf` | `pacman.conf` | profile-relative, not host `/etc/pacman.conf` |
| `airootfs_image_type` | `squashfs` | ADR-013 |
| `airootfs_image_tool_options` | `('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')` | ~2 GB target |
| `bootstrap_tarball_compression` | `('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')` | upstream releng value |
| `kernel_params_x86_64` | `loglevel=4 systemd.show_status=auto rd.udev.log_level=3` | Phase 3 keeps boot messages visible; Phase 4 adds `quiet splash` |
| `file_permissions` | `/etc/shadow` 0400, `/root` 0750, `/etc/sudoers.d/` 0750, … | archiso does **not** preserve overlay file modes |

⚠️ `profiledef.sh` is **sourced by mkarchiso**. Never add `set -euo pipefail`, `exit`, or side
effects to it — they would leak into mkarchiso's own shell. `tools/validate-versions.sh` exempts
exactly this one file from the strict-mode sweep for that reason.

### 3.2 `/home/user/ar0xOS/archiso/pacman.conf` (rendered, complete)

```ini
# /home/user/ar0xOS/config/pacman.conf.build  ->  /home/user/ar0xOS/archiso/pacman.conf
# ⚠️ BUILD-ONLY. NEVER ship this as /etc/pacman.conf on an installed system (RISK-006).
[options]
Architecture = x86_64
HoldPkg      = pacman glibc
SigLevel     = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
CacheDir     = /opt/ar0x-build/cache/pacman/pkg

# --- BEGIN AR0X_REPO_BLOCK ---------------------------------------------------
[ar0x]
SigLevel = Optional TrustAll
Server = file:///opt/ar0x-build/repo/x86_64
# --- END AR0X_REPO_BLOCK -----------------------------------------------------

[core]
SigLevel = Required DatabaseOptional
Server = https://archive.archlinux.org/repos/2026/11/01/$repo/os/$arch

[extra]
SigLevel = Required DatabaseOptional
Server = https://archive.archlinux.org/repos/2026/11/01/$repo/os/$arch
```

Verified facts behind this file:

- `https://archive.archlinux.org/repos/2026/11/01/core/os/x86_64/` exists and serves `core.db`,
  `core.db.tar.gz` etc. It has **no database `.sig`**, hence `DatabaseOptional` is mandatory —
  `SigLevel = Required` alone would fail to sync. Packages remain signature-required.
- archiso 92's `_make_pacman_conf` runs `pacman-conf --config <profile>/pacman.conf`, strips
  `CacheDir`, `DBPath`, `HookDir`, `LogFile`, `RootDir`, then re-adds a computed `CacheDir` and
  forces `HookDir = <airootfs>/etc/pacman.d/hooks/`. Setting a **non-default** `CacheDir` here
  makes every build share the warm cache at `/opt/ar0x-build/cache/pacman/pkg`.
- ⚠️ **Never use `Include = /etc/pacman.d/mirrorlist` here.** `pacman-conf` would expand it to
  the host's live mirrors and silently destroy the frozen snapshot.
- `[ar0x]` is **first** on purpose (ADR-017): pacman picks the first repo providing a package, so
  `hyprland 0.57.1` from `[ar0x]` wins over `[extra]`'s `0.57.0-3`. Build-time `SigLevel` is
  relaxed because it is a local `file://` repo of packages built and SHA256-verified on this
  machine; the **installed** system's `[ar0x]` entry (Phase 9) uses `SigLevel = Required` with
  `ar0x-keyring`.

### 3.3 `/home/user/ar0xOS/archiso/packages.x86_64` (complete)

68 packages in 6 groups at Phase 3 (plus `plymouth` in Phase 4 and `tzdata`/`rtkit` in Phase 5 = 71). **Mandatory** entries (verified against archiso 92 source):

| Package | Why |
|---|---|
| `mkinitcpio` + `mkinitcpio-archiso` | `docs/README.profile.rst`: both are mandatory or the live initramfs will not boot |
| `syslinux` | `mkarchiso::_validate_requirements_bootmode_bios.syslinux` errors if absent **from the package list**; `isolinux.bin` and `*.c32` are copied out of the *airootfs*, not the host |
| `grub` | needed inside the live system so Phase 10's Calamares can install GRUB to the target |
| `linux-lts` + `linux-lts-headers` | pinned kernel; produces `vmlinuz-linux-lts` / `initramfs-linux-lts.img` |
| `linux-firmware`, `intel-ucode`, `amd-ucode`, `sof-firmware`, `wireless-regdb` | Phase 11 WiFi/GPU checklist; full `linux-firmware` is the first size lever (RISK-005) |

Other groups: boot/disk utilities, core userspace (`networkmanager`, `nftables`, `apparmor`,
`sudo`, `polkit`), PipeWire audio, Mesa baseline, developer baseline (`git`, `base-devel`,
`neovim`, `zsh`, `starship`). Later phases append: Phase 4 `plymouth`, Phase 6 Hyprland/SDDM/GTK/Qt,
Phase 8 `ar0x-*` packages, Phase 10 `calamares`.

### 3.4 `/home/user/ar0xOS/archiso/bootstrap_packages.x86_64` (complete)

```
base
arch-install-scripts
```

archiso 92's `_validate_requirements_buildmode_bootstrap` requires this file to exist and be
non-empty. This matches upstream releng.

### 3.5 Boot configs (`archiso/grub/grub.cfg`, `archiso/syslinux/syslinux.cfg`)

Both use `vmlinuz-linux-lts` / `initramfs-linux-lts.img` and the archiso 92 template identifiers
`%INSTALL_DIR%`, `%ARCH%`, `%ARCHISO_UUID%`, `%KERNEL_PARAMS%`, `%ARCHISO_LABEL%`. archiso 92
requires at least one `syslinux/*.cfg` and an exact `grub/grub.cfg`. Both are deliberately plain
in Phase 3; Phase 4 replaces them with the ar0x theme.

⚠️ `grub/grub.cfg` may use `%ARCHISO_SEARCH_FILENAME%`; `syslinux/*.cfg` may **not** (GRUB-only).

### 3.6 `/home/user/ar0xOS/archiso/airootfs/etc/mkinitcpio.conf.d/archiso.conf`

Verbatim upstream releng hook list:
`HOOKS=(base udev microcode modconf memdisk archiso archiso_loop_mnt archiso_pxe_common
archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems keyboard)`,
`COMPRESSION="xz"`, `COMPRESSION_OPTIONS=(-9e)`. The `microcode` hook merges Intel/AMD ucode into
the initramfs, so one `INITRD` line suffices. Phase 4 adds the `plymouth` hook.

### 3.7 Customization: pacman hooks, NOT `customize_airootfs.sh`

archiso 92's `_make_customize_airootfs` still runs `airootfs/root/customize_airootfs.sh` **but
emits "`customize_airootfs.sh is deprecated! Support for it will be removed in a future archiso
version`"**. ar0x therefore uses
`/home/user/ar0xOS/archiso/airootfs/etc/pacman.d/hooks/90-ar0x-build-stamp.hook` — mkarchiso
explicitly forces `HookDir` into the airootfs, so hooks are the supported path.
`tools/bootstrap.sh --check` **fails** if a `customize_airootfs.sh` appears.

---

## 4. Chroot into the build for testing

`mkarchiso` sets `pacstrap_dir="${work_dir}/${arch}/airootfs"`, i.e.
`/opt/ar0x-build/work/x86_64/airootfs`. It remains after a normal build — the whole directory is
removed only when `mkarchiso -r` is passed, and `bootstrap.sh` never passes `-r`.

### 4.1 Using the script (recommended)

```bash
sudo ./tools/bootstrap.sh chroot                         # interactive /bin/bash
sudo ./tools/bootstrap.sh chroot pacman -Q               # list installed packages
sudo ./tools/bootstrap.sh chroot pacman -Q | wc -l
sudo ./tools/bootstrap.sh chroot systemctl list-unit-files --type=service
sudo ./tools/bootstrap.sh chroot cat /etc/os-release
sudo ./tools/bootstrap.sh chroot ls -l /etc/mkinitcpio.conf.d/
```

### 4.2 Manual equivalent (exact commands)

```bash
AIROOTFS=/opt/ar0x-build/work/x86_64/airootfs
sudo cp -L /etc/resolv.conf "$AIROOTFS/etc/resolv.conf"   # ⚠️ MANUAL: arch-chroot does NOT copy it
sudo arch-chroot "$AIROOTFS" /bin/bash
```

Inside the chroot, copy-paste these checks:

```bash
cat /etc/hostname                       # ar0x-live
cat /etc/locale.conf                    # LANG=en_US.UTF-8
cat /etc/mkinitcpio.conf.d/archiso.conf
cat /etc/ar0x-build-stamp               # written by the pacman hook
pacman -Q | wc -l                       # ~180-220 packages for the base set
pacman -Q linux-lts mkinitcpio mkinitcpio-archiso syslinux grub
systemctl list-unit-files --type=service | grep -E 'NetworkManager|systemd-journald'
ls -l /etc/shadow /etc/sudoers          # 0400 / 0400 via file_permissions
exit
```

### 4.3 What mkarchiso's cleanup removes (important)

`mkarchiso::_cleanup_pacstrap_dir` deletes the contents of `<airootfs>/boot`,
`/var/lib/pacman/sync`, `/var/cache/pacman/pkg`, `/var/log/*`, `/var/tmp/*`, and resets
`/etc/machine-id` to `uninitialized`. Also `_copy_boot_out_of_pacstrap_dir` moves kernel+initramfs
out to `work/x86_64/boot/`. Therefore inside the chroot:

| Works | Does NOT work without extra steps |
|---|---|
| `pacman -Q` (local DB intact) | `pacman -S <pkg>` — run `pacman -Sy` first |
| `systemctl list-unit-files` | `systemctl start` (no running systemd in chroot) |
| reading `/etc/*` configs | `mkinitcpio -P` (no kernel in `/boot`) |
| `locale` / `bash` / `zsh` | booting (that is what the QEMU test in Phase 11 is for) |

⚠️ Copying host `/etc/resolv.conf` into the staged root is a **temporary, test-only mutation**;
the next clean build recreates it. Do not commit it.

---

## 5. Tradeoffs (many-option configs)

| Decision | Alternatives | Tradeoff accepted |
|---|---|---|
| Frozen `2026/11/01` archive mirror vs live mirrors | live mirrors = newest packages, non-reproducible | Reproducible builds at the cost of no post-snapshot security fixes in the ISO; `ar0x-update` fixes that at first boot |
| `[ar0x]` first, local `file://` repo | enable `[extra-testing]` to get `hyprland 0.57.1` | Keeps every other package frozen; adds a source-build prerequisite (ADR-017) |
| `SigLevel = Optional TrustAll` for build-time `[ar0x]` | `Required` (needs a trusted key before the first install — chicken/egg) | Local packages are SHA256-verified at build time; the **installed** config uses `Required` |
| `squashfs` zstd 15 | `erofs` lzma (archiso 92 baseline default) | Best-documented, easiest to debug; erofs is read-only-only |
| `buildmodes=('bootstrap' 'iso')` | `iso` only | +1 tarball artifact and ~5 min, but gives a reusable minimal root for CI/recovery |
| Disposable staged profile | generate files directly into `archiso/` | Keeps `git status` clean and lets `--check` verify sync; costs one copy of a small profile |
| pacman hooks | deprecated `customize_airootfs.sh` | Supported path, no deprecation warning, idempotent |
| 83-package base set now, append later | write the final ~150-package list now | Respects the phase gates; Phase 11 rebuilds from the accumulated list |

---

## 6. Manual-intervention register (Phase 3)

| # | Action | Why manual |
|---|---|---|
| 1 | `sudo ./tools/bootstrap.sh` on a real Arch x86_64 host | Needs root, loop devices, ~40 GiB; impossible in this sandbox |
| 2 | Re-run `./tools/bootstrap.sh --sync` after editing `config/packages.x86_64` or `config/pacman.conf.build` | Keeps the committed `archiso/` copies canonical |
| 3 | `sudo cp -L /etc/resolv.conf <airootfs>/etc/resolv.conf` for manual chroot DNS | Host-specific network config |
| 4 | Confirm the `DELETE` word for `--clean` | Destructive: removes 10–25 GiB of scratch data |
| 5 | Approve dropping/keeping the `[ar0x]` block via `--with-ar0x-repo` / `--no-ar0x-repo` | Depends on whether Phases 8/9 have run |
| 6 | Visual BIOS/UEFI boot QA in QEMU (Phase 11) | Requires KVM |

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `The 'syslinux' package is missing from the package list!` | `syslinux` removed from `packages.x86_64` | Restore it; archiso copies `isolinux.bin` from the **airootfs** |
| `The 'mkinitcpio' package is missing` / no initramfs | removed from package list | Restore `mkinitcpio` + `mkinitcpio-archiso` |
| `Invalid install_dir 'ar0x_010'. Use only [a-z0-9]` | underscore in `install_dir` | Use `ar0x`; underscores belong in `iso_label` only |
| `cannot be used with the 'uefi.systemd-boot' bootmode` | both UEFI bootmodes set | Keep only `uefi.grub` |
| `failed to synchronize all databases` | `[ar0x]` block present but no `ar0x.db` | `bootstrap.sh` drops it automatically; or run `--no-ar0x-repo`; or build the repo in Phase 9 |
| `signature ... is unknown trust` | empty pacman keyring | `sudo pacman -S archlinux-keyring && sudo pacman-key --init && sudo pacman-key --populate archlinux` |
| `database signature is missing` | `SigLevel = Required` on the archive | Use `Required DatabaseOptional` (the archive has no `core.db.sig`) |
| Packages come from *live* mirrors, not 2026-11-01 | an `Include = /etc/pacman.d/mirrorlist` line | Remove it; use explicit `Server =` only |
| `arch-chroot: failed to run command` | `work/` on `noexec` | Rebuild on ext4/xfs/btrfs with `exec,dev` (BUILD_HOST.md §10) |
| `No space left on device` | < 40 GiB free | `--build-root /mnt/nvme/ar0x` + `AR0X_BUILD_ROOT` env |
| `customize_airootfs.sh is deprecated!` | someone added the old hook | Delete it; use `airootfs/etc/pacman.d/hooks/*.hook` |
| `mksquashfs: zstd compression level invalid` | squashfs-tools built without zstd | `sudo pacman -S squashfs-tools zstd` |
| `grub-mkstandalone: command not found` | missing host `grub` | `sudo pacman -S grub` (Phase 2 installs it) |

---

## 8. Phase 3 risks

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| **RISK-021** | **HIGH** | `Include = mirrorlist` or a wrong `CacheDir` silently bypasses the frozen snapshot | Explicit `Server =` only; `--check` greps `config/pacman.conf.build` for the exact archive date |
| **RISK-022** | **HIGH** | Missing `mkinitcpio-archiso` / `syslinux` produces an unbootable ISO | `--check` asserts all 6 mandatory packages against archiso 92's own validators |
| **RISK-023** | ⚠️ **HIGH** | `--clean` irreversibly deletes 10–25 GiB of work/ data | Requires typing `DELETE`; never called automatically |
| **RISK-024** | **MEDIUM** | `customize_airootfs.sh` removal in a future archiso breaks the build | Not used; pacman hooks are the supported path; `--check` fails if one appears |
| **RISK-025** | **MEDIUM** | `[ar0x]` listed after `[core]`/`[extra]` → stale `hyprland 0.57.0-3` wins | `--check` compares line numbers; `AR0X_HARD_PIN_REPO_PRIORITY=first` |
| **RISK-026** | **LOW** | `.gitkeep` placeholders ship into the live root | `bootstrap.sh` deletes all `.gitkeep` from the staged profile |

---

## 9. Verification actually performed in the sandbox

```bash
./tools/bootstrap.sh --check     # ✅ PASSED (no root, read-only)
./tools/bootstrap.sh --sync      # regenerates the 3 profile files, then re-validates
bash -n tools/*.sh tools/lib/*.sh
./tools/validate-versions.sh
```

`mkarchiso`, `pacstrap`, `arch-chroot` and QEMU **cannot run here** — no root, no loop devices,
no KVM. Those are the manual host-side steps in §6.
