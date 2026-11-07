# /home/user/ar0xOS/docker/Dockerfile
# -----------------------------------------------------------------------------
# Phase 2 — reproducible Arch build container for ar0x ISO builds.
#
# Build from the repository root:
#   docker compose -f docker/compose.yaml build
#
# ⚠️ RISK-016: this container MUST run with --privileged (see compose.yaml).
# mkarchiso calls mount --bind, mknod, chroot and mkfs.*; rootless Docker cannot
# build an ISO. Run it locally with trusted code only, never on untrusted PRs.
# -----------------------------------------------------------------------------

FROM archlinux:base-devel

LABEL org.opencontainers.image.title="ar0x-builder" \
      org.opencontainers.image.description="Arch toolchain for building ar0x live/install ISOs" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/ar0x1/ar0xOS"

# --- Section 1: bring the Arch userspace fully up to date --------------------
# A stale container image produces "signature is unknown trust" errors and
# pacman/pacstrap ABI mismatches. Always -Syu, never a partial -Sy upgrade.
RUN pacman -Syu --noconfirm \
 && pacman -S --needed --noconfirm archlinux-keyring \
 && pacman-key --init \
 && pacman-key --populate archlinux

# --- Section 2: host packages (same 37 as tools/setup-build-env.sh) ----------
# archiso 92-1 hard depends + ar0x bootmodes + signing + source builds + tests.
RUN pacman -S --needed --noconfirm \
      base-devel git pacman-contrib reflector jq shellcheck curl wget rsync \
      archiso arch-install-scripts bash dosfstools e2fsprogs erofs-utils \
      libarchive libisoburn mtools squashfs-tools zstd xz syslinux grub \
      gnupg openssl sbsigntools efitools \
      devtools cmake ninja extra-cmake-modules pkgconf meson namcap \
      qemu-desktop edk2-ovmf \
 && pacman -Scc --noconfirm

# --- Section 3: environment and build root -----------------------------------
ENV AR0X_SOURCE_ROOT=/ar0xOS \
    AR0X_BUILD_ROOT=/opt/ar0x-build \
    AR0X_VERSION=0.1.0

# The real work/ out/ cache/ from the host are bind-mounted here by compose.yaml,
# so these directories are only fallbacks when the container is run standalone.
RUN install -d -m 0755 \
      /opt/ar0x-build/work /opt/ar0x-build/out /opt/ar0x-build/chroot \
      /opt/ar0x-build/cache/pacman/pkg /opt/ar0x-build/src \
      /opt/ar0x-build/repo/x86_64 /opt/ar0x-build/logs \
 && install -d -m 0700 /opt/ar0x-build/keys /opt/ar0x-build/keys/public

WORKDIR /ar0xOS

# No ENTRYPOINT: `docker compose run --rm ar0x-builder <cmd>` overrides CMD,
# so both `./tools/setup-build-env.sh --check` and `mkarchiso ...` work directly.
CMD ["/bin/bash"]
