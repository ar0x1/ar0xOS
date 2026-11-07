#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/archiso/profiledef.sh
# -----------------------------------------------------------------------------
# PHASE 3 — canonical archiso 92 profile definition for ar0x.
#
# ⚠️ THIS FILE IS SOURCED BY mkarchiso. Do NOT add `set -euo pipefail`,
# `exit`, or any side effects: they would leak into mkarchiso's own shell.
# tools/validate-versions.sh deliberately excludes this one file from the
# strict-mode script-hygiene sweep for that reason.
#
# archiso 92 contract (verified against archiso/docs/README.profile.rst and
# archiso/mkarchiso): buildmodes, bootmodes, pacman_conf, packages,
# bootstrap_packages, airootfs_image_type, airootfs_image_tool_options,
# bootstrap_tarball_compression, arch, kernel_params_<arch>, file_permissions.
#
# `install_dir` MUST match ^[a-z0-9]+$ and be <= 30 chars (mkarchiso::_validate_requirements_buildmode_iso).
# `bootmodes` cannot mix `uefi.grub` with `uefi.systemd-boot`.
# -----------------------------------------------------------------------------

# --- ISO identity ------------------------------------------------------------
iso_name="ar0x"
iso_label="AR0X_010"
iso_publisher="ar0x <https://github.com/ar0x1/ar0xOS>"
iso_application="ar0x 0.1.0 ar0x root Live/Install ISO"
iso_version="0.1.0"
install_dir="ar0x"
arch="x86_64"

# --- Build modes -------------------------------------------------------------
# `bootstrap` emits a minimal root tarball; `iso` emits the bootable live ISO.
# `mkarchiso -m "bootstrap iso"` can override this at the command line.
buildmodes=('bootstrap' 'iso')

# --- Boot modes --------------------------------------------------------------
# BIOS via isolinux (requires `syslinux` in packages.x86_64 AND a
# syslinux/*.cfg in this profile); UEFI via GRUB (requires grub/grub.cfg and
# grub-mkstandalone on the HOST). These two are the Phase 11 QEMU test targets.
bootmodes=('bios.syslinux'
           'uefi.grub')

# --- Profile-relative file names --------------------------------------------
packages="packages.x86_64"
bootstrap_packages="bootstrap_packages.x86_64"
pacman_conf="pacman.conf"

# --- Root filesystem image ---------------------------------------------------
# ADR-013: zstd level 15 / 1 MiB blocks hits the ~2 GB ISO target without the
# ~40% CPU penalty of level 19. erofs is available in archiso 92 but is
# read-only-only and less debugged, so squashfs is the v0.1 choice (BUILD_HOST.md §6).
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# --- Kernel command line -----------------------------------------------------
# Phase 4: `quiet splash` hands the console to Plymouth; `vt.global_cursor_default=0`
# hides the blinking VT cursor behind the splash. The FAILSAFE menu entries in
# grub/grub.cfg and syslinux/syslinux.cfg override this with
# `plymouth.enable=0 nomodeset loglevel=7` for debugging.
# No hardware-specific quirks are added here — those require a review warning.
kernel_params_x86_64="quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0 apparmor=1 security=apparmor"

# --- File permissions --------------------------------------------------------
# archiso copies airootfs/ files as 0644/0755 root:root and does NOT preserve
# mode/ownership. Anything security-sensitive must be listed here.
# A trailing slash applies recursively to everything in that directory.
# `declare -A` is required: without an associative declaration bash evaluates
# ["/etc/shadow"] as arithmetic and dies with "operand expected". mkarchiso
# pre-declares this array itself; declaring it here too makes the profile
# standalone-sourceable (used by tools/bootstrap.sh --check) and is a no-op
# when mkarchiso has already declared it.
declare -A file_permissions
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/passwd"]="0:0:644"
  ["/etc/sudoers"]="0:0:400"
  ["/etc/sudoers.d/"]="0:0:750"
  ["/etc/sudoers.d/10-ar0x-wheel"]="0:0:440"
  ["/root"]="0:0:750"
  ["/etc/pacman.d/gnupg/"]="0:0:700"
  ["/usr/local/bin/"]="0:0:755"
)
