#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/vagrant/provision.sh
# -----------------------------------------------------------------------------
# Phase 2 — Vagrant provisioner, executed as root INSIDE the Arch guest VM.
#
#   1. Attach the 60 GiB data disk to /opt/ar0x-build (or warn and fall back to
#      the root disk if no suitable disk is present).
#   2. Fully update Arch and install the same 37 host packages as
#      tools/setup-build-env.sh.
#   3. Initialise the pacman keyring and create the BUILD ROOT layout.
#   4. Print a verification summary.
#
# Idempotent: `vagrant provision` can be re-run safely.
# -----------------------------------------------------------------------------

set -euo pipefail

BUILD_ROOT="/opt/ar0x-build"
SOURCE_ROOT="/ar0xOS"

log() { printf '[ .. ] %s\n' "$*"; }
ok()  { printf '[ OK ] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

# --- Section 1: locate and mount the 60 GiB data disk ------------------------
# vagrant-libvirt attaches the extra qcow2 as /dev/vdb (virtio-blk). We only
# touch a device that is >= 40 GiB AND has no existing filesystem, so a
# re-provision can never destroy an already-populated build root.
log "Looking for an unformatted >=40 GiB data disk for ${BUILD_ROOT} ..."
DATA_DISK=""
for dev in /dev/vdb /dev/vdc /dev/sdb /dev/sdc; do
    [[ -b "$dev" ]] || continue
    # lsblk -n -b -o SIZE,TYPE,FSTYPE  -> bytes, disk/part, filesystem
    size="$(lsblk -n -b -o SIZE -d -- "$dev" 2>/dev/null || printf '0')"
    fstype="$(lsblk -n -o FSTYPE -d -- "$dev" 2>/dev/null || true)"
    if (( size >= 40 * 1024 * 1024 * 1024 )) && [[ -z "$fstype" ]]; then
        DATA_DISK="$dev"
        break
    fi
done

if [[ -n "$DATA_DISK" ]]; then
    log "Formatting ${DATA_DISK} as ext4 (this is the dedicated build disk) ..."
    mkfs.ext4 -F -L ar0x-build "$DATA_DISK"
    install -d -m 0755 "$BUILD_ROOT"
    # Add an fstab entry once, then mount now.
    UUID="$(blkid -s UUID -o value -- "$DATA_DISK")"
    if ! grep -q "UUID=${UUID}" /etc/fstab; then
        printf 'UUID=%s %s ext4 defaults,noatime 0 2\n' "$UUID" "$BUILD_ROOT" >> /etc/fstab
    fi
    mount "$BUILD_ROOT"
    ok "${DATA_DISK} mounted at ${BUILD_ROOT}"
elif findmnt -n --target "$BUILD_ROOT" >/dev/null 2>&1; then
    ok "${BUILD_ROOT} is already mounted — leaving it alone"
else
    warn "No dedicated >=40 GiB disk found. Falling back to the box root disk."
    warn "⚠️ A full ISO build needs ~40 GiB free; enlarge the disk before Phase 11."
fi

# --- Section 2: update Arch and initialise the keyring -----------------------
log "pacman -Syu (full upgrade — never a partial -Sy) ..."
pacman -Syu --noconfirm
pacman -S --needed --noconfirm archlinux-keyring
if [[ -z "$(ls -A /etc/pacman.d/gnupg 2>/dev/null || true)" ]]; then
    pacman-key --init
    pacman-key --populate archlinux
fi
ok "Arch userspace up to date"

# --- Section 3: install the host package set ---------------------------------
# Identical to PKGS_CORE + PKGS_ISO + PKGS_SIGNING + PKGS_SRC + PKGS_TEST.
log "Installing the ar0x build host packages ..."
pacman -S --needed --noconfirm \
    base-devel git pacman-contrib reflector jq shellcheck curl wget rsync \
    archiso arch-install-scripts bash dosfstools e2fsprogs erofs-utils \
    libarchive libisoburn mtools squashfs-tools zstd xz syslinux grub \
    gnupg openssl sbsigntools efitools \
    devtools cmake ninja extra-cmake-modules pkgconf meson namcap \
    qemu-desktop edk2-ovmf
ok "Host packages installed"

# --- Section 4: create the BUILD ROOT layout ---------------------------------
for d in \
    "$BUILD_ROOT" "$BUILD_ROOT/work" "$BUILD_ROOT/out" "$BUILD_ROOT/chroot" \
    "$BUILD_ROOT/cache" "$BUILD_ROOT/cache/pacman/pkg" "$BUILD_ROOT/src" \
    "$BUILD_ROOT/repo" "$BUILD_ROOT/repo/x86_64" "$BUILD_ROOT/logs"; do
    install -d -m 0755 "$d"
done
install -d -m 0700 "$BUILD_ROOT/keys" "$BUILD_ROOT/keys/public"
ok "BUILD ROOT created (keys/ mode 0700)"

# Convenience symlink inside the guest's synced checkout — git-ignored.
if [[ -d "$SOURCE_ROOT" && ! -e "$SOURCE_ROOT/build" ]]; then
    ln -s "$BUILD_ROOT" "$SOURCE_ROOT/build" 2>/dev/null || true
fi

# --- Section 5: verification summary ----------------------------------------
printf '\n'
printf '  archiso : %s\n' "$(pacman -Q archiso 2>/dev/null || printf 'NOT INSTALLED')"
printf '  kernel  : %s\n' "$(uname -r)"
printf '  cpus    : %s\n' "$(nproc)"
printf '  disk    : %s\n' "$(findmnt -no SOURCE --target "$BUILD_ROOT" 2>/dev/null || printf 'root disk')"
printf '  free    : %s\n' "$(df -h -- "$BUILD_ROOT" | awk 'NR==2 {print $4}')"
printf '\n'
printf 'Next (inside the VM):\n'
printf '  cd /ar0xOS && ./tools/setup-build-env.sh --check\n'
printf '  cat /sys/module/kvm_intel/parameters/nested   # must print Y for KVM tests\n'
printf '\n'
ok "Vagrant provisioning complete"
