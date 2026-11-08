# ar0x — Build Host Setup (Phase 2)

> Companion to [`tools/setup-build-env.sh`](../tools/setup-build-env.sh).
> Every command below is copy-pasteable on an **Arch Linux x86_64** host.
> Verified against upstream package metadata on 2026-11-03.

---

## 1. Supported host (hard requirements)

| Requirement | Value | Why |
|---|---|---|
| Distribution | **Arch Linux** (or an Arch container / Arch VM) | `mkarchiso` needs `pacman`, `archlinux-keyring`, `arch-install-scripts` and Arch repo layout. `ID=arch`, `archlinux`, `artix`, `endeavouros`, `manjaro` are accepted by `require_arch_host`. |
| Architecture | `x86_64` | ar0x v0.1 is x86_64-only |
| Privileges | **root** (`sudo` is fine) | `mkarchiso` calls `mount --bind`, `mknod`, `chroot`, `mkfs.*`, `losetup` |
| Kernel | ≥ 6.6, with `CONFIG_OVERLAY_FS`, `CONFIG_SQUASHFS`, `CONFIG_BLK_DEV_LOOP`, `CONFIG_FUSE_FS` | Live-root overlay, `airootfs.sfs`, ISO loop staging |
| Devices | `/dev/loop-control`, `/dev/fuse` present | Required by archiso bootstrap |
| Work filesystem | ext4 / xfs / btrfs, mounted **`rw,exec,dev`** — never `noexec`, `nodev`, NTFS, exFAT, FAT32, or an NFS share | Unix ownership, device nodes, and executable chroot binaries |
| Network | ≥ 50 Mbps, unmetered preferred | First bootstrap downloads ~3–5 GB of packages |
| archiso | `92-1` (pinned; see §3 correction) | `buildmodes` / `bootmodes` profile keys |

⚠️ **MANUAL INTERVENTION:** `tools/setup-build-env.sh` must be run **by you, as root, on a real Arch host**. The Arena sandbox has no root, no loop devices and no KVM, so `pacman -Syu`, `mkarchiso`, `chroot` and QEMU cannot execute there. Only its `--check` mode is runnable in the sandbox (and it is: `✅ --check completed`, 37 packages).

---

## 2. Minimum vs recommended hardware

| Resource | **Minimum** | **Recommended** | Rationale |
|---|---|---|---|
| CPU | 4 cores, x86_64-v2, VT-x/AMD-V | 8–16 cores | `mksquashfs -comp zstd -Xcompression-level 15` is CPU-bound and multithreaded. VT-x/AMD-V is needed for the Phase 11 QEMU/KVM tests. |
| RAM | **8 GiB** | **16–32 GiB** | zstd level 15 uses ~1–2 GiB per worker; the QEMU `copytoram` boot test needs ≈ 2× the ISO size (~4 GiB) in host RAM. At 8 GiB, add ≥ 8 GiB swap. |
| Disk | **40 GiB free on SSD/NVMe** | 64 GiB free, NVMe | `work/` 25 GiB + `cache/` 5 GiB + `out/` 5 GiB + headroom (see `PROJECT_PLAN.md` §7). A spinning disk makes a full rebuild 3–5× slower. |
| Swap | 8 GiB if RAM = 8 GiB | 16 GiB | Prevents OOM during squashfs compression and QEMU tests |
| Display | none | any | Builds are headless; a GUI is only needed for the Calamares/Hyprland visual QA |

**Why 40 GiB and not 2 GiB:** the ISO is ~2 GB but `work/x86_64/airootfs` holds the **uncompressed** ~4.5 GiB root, `work/iso/` duplicates the kernel/initramfs/squashfs, and `mksquashfs` writes a temporary output alongside the previous image. Two retained ISO generations plus a warm `pacman` cache add the rest.

### 2.1 Filesystem tradeoffs

| Option | Pros | Cons |
|---|---|---|
| ext4 on NVMe ✅ | Predictable, fast, no COW surprises | No snapshots |
| btrfs on NVMe | Compression + snapshots of `work/` | COW amplifies the thousands of small `pacstrap` files; use `chattr +C` on `work/` if you choose it |
| XFS | Excellent large-file throughput | Cannot shrink; slower with millions of small files |
| `tmpfs` for `work/` | Extremely fast | Needs ≥ 32 GiB RAM, and everything is lost on reboot — bad for debugging |
| Network/NTFS/exFAT share | — | ❌ **Will not work**: no Unix perms / device nodes / exec |

---

## 3. Version correction made in Phase 2 (read this)

Phase 1 pinned `archiso 91` from the October 2026 ISO coverage. Upstream metadata now shows
**`archiso 92-1`**, built 2026-10-31 and published to `[extra]` before the November ISO
(<https://archlinux.org/packages/extra/any/archiso/>). The pin in `config/versions.env`,
`COMPONENT_VERSIONS.md` and `PROJECT_PLAN.md` has been corrected to `92-1`.

archiso 92 also changed the **profile contract** — Phase 3's `profiledef.sh` must use:

```bash
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')     # BIOS via isolinux, UEFI via GRUB
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--long' '-19')
```

This **confirms** Phase 1's GRUB-for-UEFI + syslinux-for-BIOS design and its zstd level 15 choice.
It also means the host needs `syslinux` (for `isolinux.bin`) and `grub` (for `grubx64.efi`) — both are
in the Phase 2 package list. archiso 92's hard depends are `arch-install-scripts bash dosfstools
e2fsprogs erofs-utils libarchive libisoburn mtools squashfs-tools`; `grub`, `edk2-ovmf`, `gnupg`,
`openssl` and `qemu-desktop` are optional depends that ar0x actually uses.

### 3.1 The frozen-snapshot / HARD-pin conflict → ADR-017

Two HARD-pinned versions are **not** in the frozen `2026/11/01` Arch snapshot:

- `hyprland 0.57.1` — released **today** (2026-11-03). Arch `[extra]` has `0.57.0-3`;
  `0.57.1-1` is in `[extra-testing]` only (<https://archlinux.org/packages/extra/x86_64/hyprland/>).
- `calamares 3.4.3` — not in the official repos at all (AUR / Codeberg source only).

Enabling `[extra-testing]` in `pacman.conf.build` would drag in every testing package and destroy
reproducibility. Instead (ADR-017): those packages are built from their exact upstream tarballs by
`makepkg` in Phases 8/9 into the signed `[ar0x]` repo, and `config/pacman.conf.build` lists
`[ar0x]` **first** with a local `file:///opt/ar0x-build/repo/x86_64` server. pacman prefers the
first repo that provides a package, so `hyprland 0.57.1` wins over `[extra]`'s `0.57.0-3`.

**Host consequence:** the build host needs a real source-build toolchain (`base-devel devtools
cmake ninja extra-cmake-modules pkgconf meson namcap`), which is why `PKGS_SRC` exists.
`makepkg -s` resolves the remaining 79 Hyprland deps and the ~35 Calamares deps automatically;
we deliberately do **not** hard-code them. `--prewarm-calamares` installs the Calamares 3.4.x dep
set up-front if you want failures to surface early.

---

## 4. Exact commands — native host (recommended path)

```bash
# --- 4.1 Start from a fully-updated Arch host --------------------------------
sudo pacman -Syu
sudo reboot                       # ⚠️ MANUAL: only if kernel/glibc/systemd was upgraded
                                  # A stale kernel vs. new userspace breaks mkarchiso.

# --- 4.2 Get the source tree --------------------------------------------------
sudo pacman -S --needed git base-devel
git clone -b arena/53f7f9f8-ar0xos https://github.com/ar0x1/ar0xOS.git ~/ar0xOS
cd ~/ar0xOS
git checkout arena/53f7f9f8-ar0xos

# --- 4.3 Read-only preflight (no root, no changes) ---------------------------
./tools/setup-build-env.sh --check

# --- 4.4 Full automated setup (root required) --------------------------------
sudo ./tools/setup-build-env.sh --yes

# --- 4.5 Verify ---------------------------------------------------------------
mkarchiso -h
pacman -Q archiso                                  # expect: archiso 92-1
ls -ld /opt/ar0x-build/keys                       # expect: drwx------
findmnt -no OPTIONS --target /opt/ar0x-build      # must NOT contain noexec / nodev
cat /opt/ar0x-build/logs/host-manifest.txt
./tools/validate-versions.sh
```

### 4.1 The exact package install, if you want to do it by hand

This is the literal expansion of the four mandatory groups in `setup-build-env.sh`
(37 unique packages, verified names):

```bash
sudo pacman -Syu
sudo pacman -S --needed \
  base-devel git pacman-contrib reflector jq shellcheck curl wget rsync archlinux-keyring \
  archiso arch-install-scripts bash dosfstools e2fsprogs erofs-utils libarchive \
  libisoburn mtools squashfs-tools zstd xz syslinux grub \
  gnupg openssl sbsigntools efitools \
  devtools cmake ninja extra-cmake-modules pkgconf meson namcap \
  qemu-desktop edk2-ovmf

sudo pacman-key --init
sudo pacman-key --populate archlinux

sudo install -d -m 0755 \
  /opt/ar0x-build/{work,out,chroot,src,repo,logs} \
  /opt/ar0x-build/cache/pacman/pkg /opt/ar0x-build/repo/x86_64
sudo install -d -m 0700 /opt/ar0x-build/keys /opt/ar0x-build/keys/public
sudo ln -s /opt/ar0x-build ~/ar0xOS/build
```

Optional groups:

```bash
# Calamares 3.4.x dependency pre-warm (fails early instead of mid-build)
sudo ./tools/setup-build-env.sh --yes --prewarm-calamares

# Container / VM tooling
sudo ./tools/setup-build-env.sh --yes --with-docker
sudo ./tools/setup-build-env.sh --yes --with-vagrant

# Secure Boot testing (Phase 4/11) — AUR packages, needs an AUR helper
paru -S shim-signed edk2-ovmf-fedora
```

⚠️ **Arch's own `OVMF_CODE.secboot.4m.fd` does not actually enforce Secure Boot** — use
`edk2-ovmf-fedora` (AUR) for a real Secure Boot QEMU test in Phase 11.

### 4.2 host-package rationale

| Group | Packages | Why |
|---|---|---|
| Core | `base-devel git pacman-contrib reflector jq shellcheck curl wget rsync archlinux-keyring` | `makepkg`, Git source, mirror sorting, JSON parsing, script lint, tarball fetching, keyring |
| ISO (archiso 92 hard depends) | `archiso arch-install-scripts bash dosfstools e2fsprogs erofs-utils libarchive libisoburn mtools squashfs-tools zstd xz` | `pacstrap`, `xorriso`, `mksquashfs`, `mkfs.erofs`, FAT ESP, zstd compression |
| ISO (ar0x bootmodes) | `syslinux grub` | `isolinux.bin` for `bios.syslinux`; `grubx64.efi` for `uefi.grub` |
| Signing | `gnupg openssl sbsigntools efitools` | `repo-add -s`, `SHA256SUMS.sig`, optional `sbsign` for Secure Boot |
| Source builds | `devtools cmake ninja extra-cmake-modules pkgconf meson namcap` | Clean-chroot `makepkg` for Hyprland 0.57.1 / Calamares 3.4.3 / 8 ar0x packages |
| Testing | `qemu-desktop edk2-ovmf` | Phase 11 UEFI (`OVMF_CODE.4m.fd`) + BIOS (SeaBIOS) QEMU boots |
| Optional | `docker docker-compose` / `vagrant` | §7 / §8 |

---

## 5. Directory layout the script creates

```
/opt/ar0x-build/                 root:root 0755
├── work/                        0755  mkarchiso -w  (25 GiB)
├── out/                         0755  mkarchiso -o  (final ISO + sums)
├── chroot/                      0755  manual arch-chroot tests (Phase 3)
├── cache/pacman/pkg/            0755  shared pacman cache (5 GiB)
├── src/                         0755  vendored Calamares / Hyprland tarballs
├── repo/x86_64/                 0755  [ar0x] db + signed packages
├── keys/                        0700  ⚠️ private keys, NEVER in Git
│   └── public/                  0700
└── logs/                        0755  01-setup.log, host-manifest.txt, ...
```

`~/ar0xOS/build -> /opt/ar0x-build` is a **git-ignored symlink**, so you can use
`build/out/ar0x-0.1.0-x86_64.iso` from the checkout. It must be a symlink, not a real directory.

⚠️ **Never put `work/` inside the Git checkout.** `mkarchiso` generates 10–25 GiB of untracked
files there; Git becomes unusably slow and a careless `git add -A` would try to commit them.
`.gitignore` excludes `/build/`, `/work/`, `/out/` and all `*.iso` / `*.pkg.tar.zst`.

---

## 6. Tradeoffs you are choosing (many-option configs)

| Decision | Alternatives | Tradeoff |
|---|---|---|
| Full `pacman -Syu` (default) vs `--no-upgrade` | `-Syu` is safe and correct; `-Sy` alone is a **partial upgrade**, explicitly unsupported by Arch | Full upgrade may update your kernel → reboot needed. `--no-upgrade` only acceptable on a host updated in the last 24 h. |
| Native host | Docker / Vagrant | Fastest, direct KVM, no nested virt. Requires a dedicated Arch machine and root. |
| `squashfs` + zstd 15 | `erofs` + lzma (archiso 92 baseline default) | erofs is faster to mount and slightly smaller, but **read-only-only** and less widely debugged; squashfs is the safer, better-documented path for v0.1. |
| `[ar0x]` repo listed first in build `pacman.conf` | Enable `[extra-testing]` | Repo-first keeps reproducibility; testing repos would silently change dozens of packages. |
| `makepkg -s` auto-deps | Hard-code 79 Hyprland + 35 Calamares deps | Auto-deps always match the PKGBUILD; hard-coding rots on every Arch update. |
| `--prewarm-calamares` off by default | On | Off keeps the host install small and avoids fragile package names; on surfaces missing deps early. |
| `--privileged` Docker | Rootless / unprivileged | ⚠️ `mkarchiso` genuinely needs `CAP_SYS_ADMIN` + device nodes. Rootless Docker **cannot** build an ISO. See §7. |
| libvirt Vagrant provider | VirtualBox provider | libvirt + `host-passthrough` allows nested KVM (fast QEMU tests); VirtualBox nested virt is unreliable. |
| `shim-signed` from AUR | Skip Secure Boot tooling | AUR packages need a helper (`paru`) and are unverified by Arch; Phase 4 makes SB optional, so default is skip. |

---

## 7. Docker option

Files: `/home/user/ar0xOS/docker/Dockerfile`, `docker/compose.yaml`, `docker/run.sh`.

```bash
# One-time, on the host:
sudo pacman -S --needed docker docker-compose
sudo systemctl enable --now docker.service
sudo usermod -aG docker "$USER"
newgrp docker                    # ⚠️ MANUAL: or log out/in for the group to apply

cd ~/ar0xOS
docker compose -f docker/compose.yaml build
docker compose -f docker/compose.yaml run --rm ar0x-builder \
    ./tools/setup-build-env.sh --check
docker compose -f docker/compose.yaml run --rm ar0x-builder mkarchiso -h
```

Or use the helper:

```bash
./docker/run.sh --check
./docker/run.sh bash            # interactive root shell inside the Arch container
./docker/run.sh mkarchiso -h
```

⚠️ **RISK-016 — `--privileged` is required and is a real security exposure.** `mkarchiso`
mounts filesystems and creates device nodes, so the container gets `CAP_SYS_ADMIN`, host
`/dev/loop-control`, and full device access. Run it **only locally, only with code you trust**,
and **never** in a CI job that checks out untrusted PRs. The compose file deliberately binds only
the repository and a named cache volume — no Docker socket, no host `/`.

What the container gives you: an Arch `base-devel` userspace on a non-Arch host, a disposable and
reproducible toolchain, and no changes to the host's packages. What it costs: overlayfs-on-overlayfs
slowness, `--privileged`, and no direct KVM (QEMU tests still run on the host, not in the container).

**OVMF/UEFI note:** install `edk2-ovmf` on the **host** for Phase 11 QEMU UEFI tests; the container
is for building the ISO, not for booting it.

---

## 8. Vagrant option

Files: `/home/user/ar0xOS/Vagrantfile`, `vagrant/provision.sh`.

```bash
# libvirt provider (recommended: nested KVM works)
sudo pacman -S --needed vagrant libvirt qemu-desktop dnsmasq bridge-utils virt-manager
sudo systemctl enable --now libvirtd.service
sudo usermod -aG libvirt "$USER"
newgrp docker 2>/dev/null || true; newgrp libvirt   # ⚠️ MANUAL: re-login preferred
vagrant plugin install vagrant-libvirt

cd ~/ar0xOS
vagrant up --provider=libvirt
vagrant rsync                    # sync host edits into /ar0xOS after each change
vagrant ssh
# inside the VM:
cd /ar0xOS && ./tools/setup-build-env.sh --check
```

VirtualBox alternative (nested KVM is unreliable — QEMU tests will be slow):

```bash
sudo pacman -S --needed vagrant virtualbox virtualbox-host-modules-arch
vagrant up --provider=virtualbox
```

The Vagrantfile provisions:
- box `archlinux/archlinux` (libvirt) or `generic/arch` (VirtualBox),
- 8 vCPUs with `host-passthrough` + `nested=true` so KVM works inside the VM,
- 12 GiB RAM,
- a dedicated **60 GiB qcow2 data disk** mounted at `/opt/ar0x-build` (the box's root disk is far
  too small for `work/`),
- `/ar0xOS` as a synced folder of the repository checkout,
- `vagrant/provision.sh`, which runs `pacman -Syu` and installs the same 37-package list.

⚠️ **MANUAL:** enabling nested virtualization on the outer host may require
`options kvm_intel nested=1` (or `kvm_amd`) in `/etc/modprobe.d/kvm.conf` plus a reboot. Check with
`cat /sys/module/kvm_intel/parameters/nested`.

---

## 9. Verification checklist after setup

```bash
./tools/setup-build-env.sh --check          # ✅ read-only, exit 0
mkarchiso -h                                # usage prints (archiso present)
pacman -Q archiso                           # archiso 92-1
pacman -Q | grep -E '^(grub|syslinux|squashfs-tools|libisoburn|qemu-desktop|edk2-ovmf) '
command -v pacstrap xorriso mksquashfs grub-mkstandalone sbsign namcap
ls -l /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd
findmnt -no OPTIONS --target /opt/ar0x-build   # rw,relatime,... — no noexec/nodev
ls -ld /opt/ar0x-build/keys                   # drwx------
bash -n tools/*.sh tools/lib/*.sh
shellcheck tools/*.sh tools/lib/*.sh
./tools/validate-versions.sh
```

Expected: all commands return 0, `keys/` is `0700`, OVMF files exist, and the validator prints
`✅ ar0x version + structure validation PASSED`. The two `[WARN]` lines about
`pacman.conf.build` / `pacman.conf.installed` are **expected** — those files are Phase 3 and
Phase 5/9 deliverables; creating them now would skip phases.

---

## 10. Troubleshooting (exact fixes)

| Symptom | Cause | Fix |
|---|---|---|
| `error: signature from "..." is unknown trust` | Empty/stale pacman keyring | `sudo pacman -S archlinux-keyring && sudo pacman-key --init && sudo pacman-key --populate archlinux` |
| `mount: ... permission denied` / `mknod: Operation not permitted` | Not root, or container lacks `CAP_SYS_ADMIN` | Run with `sudo`; for Docker use `--privileged` (§7) |
| `mksquashfs: command not found` | Missing `squashfs-tools` | `sudo pacman -S squashfs-tools` |
| `xorriso: command not found` | Missing `libisoburn` | `sudo pacman -S libisoburn` |
| `isolinux.bin not found` | Missing `syslinux` while `bootmodes` includes `bios.syslinux` | `sudo pacman -S syslinux` |
| `grub-mkstandalone: command not found` | Missing `grub` while `bootmodes` includes `uefi.grub` | `sudo pacman -S grub` |
| `No space left on device` during squashfs | < 40 GiB free | Move `AR0X_BUILD_ROOT`: `sudo ./tools/setup-build-env.sh --yes --build-root /mnt/nvme/ar0x` |
| `chroot: failed to run command: Permission denied` | `work/` mounted `noexec` or on FAT/NTFS | Remount with `exec,dev` on ext4/xfs/btrfs |
| `error: could not open file /var/lib/pacman/sync/...` | Stale sync DB | `sudo rm -f /var/lib/pacman/db.lck && sudo pacman -Syy` |
| `profiledef.sh: unknown key buildmodes` | Host has archiso < 92 | `sudo pacman -Syu`; re-check `pacman -Q archiso` |
| `profiledef.sh: unknown key bootmodes` | Host archiso newer than 92 with changed syntax | Inspect `/usr/share/archiso/configs/baseline/profiledef.sh` on the host and diff against Phase 3's file |
| QEMU UEFI boot instantly exits | Wrong OVMF path | Use `/usr/share/edk2/x64/OVMF_CODE.4m.fd` **and** a writable copy of `OVMF_VARS.4m.fd` |
| Secure Boot test does nothing | Arch's `secboot` firmware is not actually enforcing | Install `edk2-ovmf-fedora` (AUR), use `/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd` |
| Vagrant VM has no disk space | Only the small box root disk | Confirm the 60 GiB data disk is mounted at `/opt/ar0x-build` (`findmnt /opt/ar0x-build`) |

---

## 11. Phase 2 manual-intervention register

| # | Action | Why it is manual |
|---|---|---|
| 1 | Run `sudo ./tools/setup-build-env.sh --yes` on a real Arch host | Needs root + `pacman -Syu`; impossible in this sandbox |
| 2 | Reboot after a kernel/glibc/systemd upgrade | Firmware/bootloader state |
| 3 | Choose native vs Docker vs Vagrant | Depends on your hardware and whether you have a spare Arch machine |
| 4 | `usermod -aG docker` / `libvirt` + re-login | Group membership only applies to new login sessions |
| 5 | Enable nested virtualization in the outer host's modprobe config (Vagrant) | Host firmware/module config |
| 6 | Install AUR `shim-signed` / `edk2-ovmf-fedora` if you want Secure Boot tests | Requires an AUR helper and a trust decision |
| 7 | Generate and back up the release GPG key (Phase 9) | Key custody — never automated, never in Git |
| 8 | Visual/first-boot QA on real hardware (Phase 11) | Requires physical devices |

---

## 12. Phase 2 risks

| ID | Severity | Risk | Mitigation |
|---|---|---|---|
| **RISK-016** | ⚠️ HIGH | Docker `--privileged` grants `CAP_SYS_ADMIN` and host device access | Local use only, trusted code only, never in PR-driven CI; compose binds only the repo + a named cache volume |
| **RISK-017** | MEDIUM | Host `archiso` drifts past 92 and `profiledef.sh` keys change | `setup-build-env.sh` compares `pacman -Q archiso` to the pin and warns; Phase 3 diffs the shipped baseline profile |
| **RISK-018** | MEDIUM | `--no-upgrade` partial upgrade breaks `pacman`/`pacstrap` | Default is `-Syu`; explicit warning; flag documented as last resort |
| **RISK-019** | MEDIUM | `work/` on `noexec`/`nodev`/NTFS yields cryptic chroot failures | `check_mount_options` preflight + troubleshooting table |
| **RISK-020** | LOW | HARD-pinned packages built from source fail due to missing makedepends | `makepkg -s` resolves them; `--prewarm-calamares` surfaces failures early |
