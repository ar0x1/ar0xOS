#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/setup-build-env.sh
# -----------------------------------------------------------------------------
# PHASE 2 — Build environment setup for the ar0x distribution.
#
# What it does (full mode, must run as root on an Arch x86_64 host):
#   1. Preflight: arch, CPU, RAM, free disk, loop devices, work-FS mount options.
#   2. Full system upgrade + install every host package ar0x needs (§5 groups).
#   3. Initialise the Arch pacman keyring.
#   4. Create /opt/ar0x-build/{work,out,chroot,cache,src,repo,keys,logs}
#      with correct permissions (keys/ is 0700).
#   5. Create the git-ignored symlink  <source-root>/build -> /opt/ar0x-build.
#   6. Optionally enable Docker / libvirt services for the container options.
#   7. Verify toolchain (mkarchiso, pacstrap, xorriso, mksquashfs, GRUB,
#      syslinux, GPG, QEMU/OVMF), run validate-versions.sh, write a host manifest.
#
# --check mode is READ-ONLY and needs NO root: it validates the package arrays,
# version pins, hardware and paths, then prints exactly what WOULD be installed.
# Use it in CI or before committing a build profile.
#
# Usage:
#   ./tools/setup-build-env.sh --check
#   sudo ./tools/setup-build-env.sh --yes
#   sudo ./tools/setup-build-env.sh --yes --with-docker
#   sudo ./tools/setup-build-env.sh --yes --no-upgrade --build-root /mnt/nvme/ar0x
# -----------------------------------------------------------------------------

set -euo pipefail
umask 022

# --- Section 0: resolve paths and load the shared library --------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- Section 1: minimum / recommended hardware -------------------------------
# Minimums are hard failures in full mode; recommended values only warn.
# Rationale (docs/BUILD_HOST.md §2):
#   * mksquashfs -comp zstd -Xcompression-level 15 uses ~1-2 GiB per worker.
#   * The QEMU "copytoram" test needs ~2x the ISO size in host RAM.
#   * work/ holds the full uncompressed airootfs (~4.5 GiB) plus the ISO staging
#     tree and intermediate squashfs — 25 GiB is the practical floor.
AR0X_MIN_CPUS=4
AR0X_REC_CPUS=8
AR0X_MIN_RAM_KB=$((8 * 1024 * 1024))       # 8 GiB
AR0X_REC_RAM_KB=$((16 * 1024 * 1024))      # 16 GiB
AR0X_MIN_DISK_BYTES=$((40 * 1024 * 1024 * 1024))   # 40 GiB
AR0X_REC_DISK_BYTES=$((64 * 1024 * 1024 * 1024))   # 64 GiB

# --- Section 2: host package groups ------------------------------------------
# Every name is a real Arch package. archiso 92-1's PKGBUILD depends are listed
# first; the rest are ar0x-specific (boot, signing, testing, source builds).
# makepkg -s resolves the big per-package makedepends automatically, so we do
# NOT hard-code the 79 Hyprland deps here.

# Core developer + distro tooling.
PKGS_CORE=(
    base-devel git pacman-contrib reflector jq shellcheck
    curl wget rsync archlinux-keyring
)

# archiso 92-1 hard depends + the optional deps ar0x actually uses.
#   libisoburn -> xorriso     (ISO9660/hybrid image)
#   squashfs-tools -> mksquashfs (airootfs.sfs)
#   erofs-utils -> mkfs.erofs  (archiso 92 can also build erofs images)
#   syslinux -> isolinux.bin   (bootmodes bios.syslinux)
#   grub -> grubx64.efi        (bootmodes uefi.grub + installed-system GRUB)
PKGS_ISO=(
    archiso arch-install-scripts bash dosfstools e2fsprogs erofs-utils
    libarchive libisoburn mtools squashfs-tools zstd xz syslinux grub
)

# Package/repo signing and the optional Secure Boot signing path.
PKGS_SIGNING=(
    gnupg openssl sbsigntools efitools
)

# QEMU UEFI + BIOS testing (Phase 11) and archiso's run_archiso helper.
PKGS_TEST=(
    qemu-desktop edk2-ovmf
)

# Clean-chroot package builds: phases 8/9 build Calamares 3.4.3 and Hyprland
# 0.57.1 from source because neither exact version is in the frozen snapshot.
PKGS_SRC=(
    devtools cmake ninja extra-cmake-modules pkgconf meson namcap
)

# OPT-IN pre-warm of Calamares 3.4.x runtime/build deps. Not installed by
# default: makepkg -s resolves them, and this list is only useful to fail early.
PKGS_CALAMARES_PREWARM=(
    qt6-base qt6-declarative qt6-svg qt6-tools qt6-translations qt6-location
    kcoreaddons kconfig kcrash kpackage kparts kirigami kpmcore polkit-qt6
    plasma-integration yaml-cpp libpwquality parted python python-yaml
    python-jsonschema python-toml hwinfo ckbcomp hicolor-icon-theme
    gtk-update-icon-cache boost
)

# OPT-IN container / VM tooling (see docs/BUILD_HOST.md §7 and §8).
PKGS_DOCKER=(docker docker-compose)
PKGS_VAGRANT=(vagrant)

# --- Section 3: CLI parsing ---------------------------------------------------
CHECK_ONLY=0
ASSUME_YES=0
DO_UPGRADE=1
WITH_DOCKER=0
WITH_VAGRANT=0
PREWARM_CALAMARES=0
SKIP_QEMU=0
NO_SYMLINK=0
ALLOW_NON_ARCH=0

usage() {
    cat <<'USAGE'
ar0x Phase 2 — setup-build-env.sh

  --check                 Read-only preflight. No root, no changes, no pacman.
  --yes                   Do not prompt before `pacman -Syu` (required for CI).
  --no-upgrade            Only `pacman -Sy`, NOT `-Syu`. ⚠️ Partial-upgrade risk.
  --skip-qemu             Do not install qemu-desktop / edk2-ovmf.
  --prewarm-calamares     Also install the full Calamares 3.4.x dep set.
  --with-docker           Install docker + docker-compose and enable docker.service.
  --with-vagrant          Install vagrant (provider installed separately).
  --no-symlink            Do not create <source-root>/build -> /opt/ar0x-build.
  --build-root PATH       Override AR0X_BUILD_ROOT (default /opt/ar0x-build).
  --allow-non-arch        Proceed on a non-Arch host (only for Arch containers).
  -h | --help             Show this help.

Examples:
  ./tools/setup-build-env.sh --check
  sudo ./tools/setup-build-env.sh --yes
  sudo ./tools/setup-build-env.sh --yes --with-docker --build-root /mnt/nvme/ar0x
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)              CHECK_ONLY=1 ;;
        --yes|-y)             ASSUME_YES=1 ;;
        --no-upgrade)         DO_UPGRADE=0 ;;
        --skip-qemu)          SKIP_QEMU=1 ;;
        --prewarm-calamares)  PREWARM_CALAMARES=1 ;;
        --with-docker)        WITH_DOCKER=1 ;;
        --with-vagrant)       WITH_VAGRANT=1 ;;
        --no-symlink)         NO_SYMLINK=1 ;;
        --allow-non-arch)     ALLOW_NON_ARCH=1 ;;
        --build-root)         [[ $# -ge 2 ]] || die "--build-root needs a PATH."
                              export AR0X_BUILD_ROOT="$2"; shift ;;
        -h|--help)            usage; exit 0 ;;
        *)                    die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 4: build the final package list ----------------------------------
ALL_PKGS=(
    "${PKGS_CORE[@]}" "${PKGS_ISO[@]}" "${PKGS_SIGNING[@]}" "${PKGS_SRC[@]}"
)
# Use explicit `if` blocks, NOT `(( cond )) && cmd`: a false arithmetic test
# inside an && list can trip `set -e` at the top level.
if (( SKIP_QEMU == 0 )); then ALL_PKGS+=("${PKGS_TEST[@]}"); fi
if (( PREWARM_CALAMARES == 1 )); then ALL_PKGS+=("${PKGS_CALAMARES_PREWARM[@]}"); fi
if (( WITH_DOCKER == 1 )); then ALL_PKGS+=("${PKGS_DOCKER[@]}"); fi
if (( WITH_VAGRANT == 1 )); then ALL_PKGS+=("${PKGS_VAGRANT[@]}"); fi

# Static sanity: no empty names and no duplicates (duplicates are harmless to
# pacman but indicate a maintenance error in this list).
declare -A _seen=()
DUPLICATES=0
for pkg in "${ALL_PKGS[@]}"; do
    [[ -n "$pkg" ]] || { fail "Empty package name in the package list."; continue; }
    if [[ -n "${_seen[$pkg]:-}" ]]; then
        warn "Duplicate package in list: ${pkg}"
        DUPLICATES=$((DUPLICATES + 1))
    fi
    _seen["$pkg"]=1
done

# --- Section 5: read-only preflight (shared by --check and full mode) ---------
section "Preflight: identity"
log "Source root : ${AR0X_SOURCE_ROOT}"
log "Build root  : ${AR0X_BUILD_ROOT}"
log "ar0x        : ${AR0X_VERSION} (snapshot ${AR0X_SNAPSHOT_DATE})"
log "archiso pin : ${AR0X_ARCHISO_VERSION}"
log "Host OS     : $(. /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-unknown}" "${VERSION_ID:-}")"
log "Kernel      : $(uname -sr) / $(uname -m)"

if (( CHECK_ONLY == 1 )); then
    # In --check mode a non-Arch host is EXPECTED (e.g. this sandbox / CI lint).
    require_arch_host 1
elif (( ALLOW_NON_ARCH == 1 )); then
    require_arch_host 1
else
    require_arch_host 0
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    fail "ar0x v0.1 targets x86_64 only; host is $(uname -m)."
else
    ok "Architecture is x86_64"
fi

section "Preflight: CPU / RAM / disk"
# --check runs on lint/CI machines that are not build hosts, so shortfalls are
# downgraded to warnings there. In full mode they are hard failures.
if (( CHECK_ONLY == 1 )); then PREFLIGHT_MODE="warn"; else PREFLIGHT_MODE="fail"; fi
CPUS="$(nproc 2>/dev/null || printf '0')"
RAM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
log "CPUs: ${CPUS} (min ${AR0X_MIN_CPUS}, recommended ${AR0X_REC_CPUS})"
log "RAM : $(human_bytes "$((RAM_KB * 1024))") (min $(human_bytes "$((AR0X_MIN_RAM_KB * 1024))"))"
if (( CPUS < AR0X_MIN_CPUS )); then
    _report_preflight "$PREFLIGHT_MODE" "Only ${CPUS} CPUs; minimum is ${AR0X_MIN_CPUS}."
fi
if (( CPUS < AR0X_REC_CPUS )); then
    warn "${CPUS} CPUs works but zstd squashfs builds are slow; ${AR0X_REC_CPUS}+ recommended."
fi
if (( RAM_KB < AR0X_MIN_RAM_KB )); then
    _report_preflight "$PREFLIGHT_MODE" \
        "Only $(human_bytes "$((RAM_KB * 1024))") RAM; 8 GiB minimum (16 GiB recommended)."
elif (( RAM_KB < AR0X_REC_RAM_KB )); then
    warn "8–16 GiB RAM: add swap before the QEMU copytoram test."
else
    ok "RAM is sufficient"
fi
require_free_space "$AR0X_BUILD_ROOT" "$AR0X_MIN_DISK_BYTES" "$PREFLIGHT_MODE"
check_mount_options "$AR0X_BUILD_ROOT" "$PREFLIGHT_MODE"

section "Preflight: kernel facilities mkarchiso needs"
if [[ -e /dev/loop-control ]]; then ok "/dev/loop-control present"; else warn "/dev/loop-control missing — loop devices needed for mkfs.erofs / ISO staging."; fi
if [[ -e /dev/fuse ]]; then ok "/dev/fuse present"; else warn "/dev/fuse missing (needed by some archiso bootstrap paths)."; fi
# Only warn here: CONFIG_* may be built-in (>=y) or module (>=m), and
# containerised hosts often hide /proc/config.gz entirely.
for knob in CONFIG_OVERLAY_FS CONFIG_SQUASHFS CONFIG_BLK_DEV_LOOP CONFIG_FUSE_FS; do
    if [[ -r /proc/config.gz ]] && zgrep -q "^${knob}=[ym]" /proc/config.gz 2>/dev/null; then
        ok "${knob} enabled"
    elif [[ -r "/boot/config-$(uname -r)" ]] && grep -q "^${knob}=[ym]" "/boot/config-$(uname -r)" 2>/dev/null; then
        ok "${knob} enabled"
    else
        warn "Could not confirm ${knob} — verify on the real host if the build fails."
    fi
done

section "Preflight: repository files"
[[ -f "${AR0X_SOURCE_ROOT}/PROJECT_PLAN.md" ]] && ok "PROJECT_PLAN.md present" || fail "PROJECT_PLAN.md missing (Phase 1 not applied)."
[[ -f "${AR0X_CONFIG_DIR}/versions.env" ]]    && ok "config/versions.env present" || fail "config/versions.env missing."
[[ -f "${AR0X_TOOLS_DIR}/validate-versions.sh" ]] && ok "tools/validate-versions.sh present" || fail "validator missing."
if (( DUPLICATES > 0 )); then warn "${DUPLICATES} duplicate package name(s) in the host list."; fi
ok "Package list: ${#ALL_PKGS[@]} unique packages across 4 mandatory groups"

# --- Section 6: --check short-circuits here (no root, no writes) -------------
if (( CHECK_ONLY == 1 )); then
    section "CHECK MODE — nothing was installed or written"
    printf 'Would install %d packages:\n' "${#ALL_PKGS[@]}"
    printf '  %s\n' "${ALL_PKGS[@]}" | fold -s -w 96 | sed 's/^/    /'
    printf '\nWould create:\n'
    printf '    %s/{work,out,chroot,cache/pacman/pkg,src,repo/x86_64,keys,logs}\n' "$AR0X_BUILD_ROOT"
    printf '    %s/build -> %s (symlink)\n' "$AR0X_SOURCE_ROOT" "$AR0X_BUILD_ROOT"
    printf '\nHard preflight failures: %d (hardware shortfalls are warnings in --check mode)\n' "$AR0X_FAILURES"
    if (( AR0X_FAILURES > 0 )); then
        warn "Some preflight items failed. On a real Arch host with root these are fatal."
    fi
    printf '\n%s✅ --check completed (read-only)%s\n' "$_AR0X_C_OK" "$_AR0X_C_RST"
    exit 0
fi

# --- Section 7: from here on we need root and confirmation -------------------
require_root
assert_clean

if (( DO_UPGRADE == 1 )) && (( ASSUME_YES == 0 )); then
    printf '\n%s⚠️  This performs a FULL `pacman -Syu` on your host, then installs %d packages.%s\n' \
        "$_AR0X_C_WARN" "${#ALL_PKGS[@]}" "$_AR0X_C_RST"
    printf '    A kernel upgrade may require a reboot before mkarchiso works reliably.\n'
    read -r -p '    Continue? [y/N] ' reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Aborted by user."
fi
if (( DO_UPGRADE == 0 )); then
    # Single quotes: backticks here are literal text, not command substitution.
    warn '--no-upgrade given: pacman -Sy without -u is a PARTIAL UPGRADE. Arch does not support this; use only on a host updated within the last 24h.'
fi

# --- Section 8: install host packages ----------------------------------------
section "Installing host packages"
install -d -m 0755 "$AR0X_LOG_DIR"
SETUP_LOG="${AR0X_LOG_DIR}/01-setup.log"
log "Logging to ${SETUP_LOG}"

if ! have_command pacman; then
    die "pacman not found — this script requires an Arch host (or an Arch container)."
fi

{
    if (( DO_UPGRADE == 1 )); then
        printf '# pacman -Syu --noconfirm\n'
        pacman -Syu --noconfirm
    else
        printf '# pacman -Sy --noconfirm (partial upgrade, see warning above)\n'
        pacman -Sy --noconfirm
    fi
} 2>&1 | tee -a "$SETUP_LOG"

log "Installing ${#ALL_PKGS[@]} packages with pacman -S --needed ..."
pacman -S --needed --noconfirm "${ALL_PKGS[@]}" 2>&1 | tee -a "$SETUP_LOG"
ok "Host packages installed"

# --- Section 9: pacman keyring ------------------------------------------------
section "Initialising Arch keyring"
# On a fresh Arch install / container the keyring may be empty; mkarchiso's
# pacstrap will then fail with "signature is unknown trust".
pacman -S --needed --noconfirm archlinux-keyring 2>&1 | tee -a "$SETUP_LOG" || true
if [[ -z "$(ls -A /etc/pacman.d/gnupg 2>/dev/null || true)" ]]; then
    pacman-key --init 2>&1 | tee -a "$SETUP_LOG"
    pacman-key --populate archlinux 2>&1 | tee -a "$SETUP_LOG"
    ok "pacman keyring initialised"
else
    ok "pacman keyring already populated"
fi

# --- Section 10: create the BUILD ROOT ---------------------------------------
section "Creating build root"
for d in \
    "$AR0X_BUILD_ROOT" "$AR0X_WORK_DIR" "$AR0X_OUT_DIR" "$AR0X_CHROOT_DIR" \
    "$AR0X_BUILD_ROOT/cache" "$AR0X_PKG_CACHE" "$AR0X_SRC_DIR" \
    "$AR0X_BUILD_ROOT/repo" "$AR0X_REPO_DIR" "$AR0X_LOG_DIR"; do
    install -d -m 0755 "$d"
done
# Private keys must NEVER be world-readable, and keys/ must never enter Git.
install -d -m 0700 "$AR0X_KEYS_DIR"
install -d -m 0700 "${AR0X_KEYS_DIR}/public"
ok "Build root created at ${AR0X_BUILD_ROOT} (keys/ mode 0700)"

# --- Section 11: convenience symlink in the source tree ----------------------
SYMLINK="${AR0X_SOURCE_ROOT}/build"
if (( NO_SYMLINK == 0 )); then
    section "Creating build/ symlink"
    if [[ -L "$SYMLINK" ]]; then
        current="$(readlink -f -- "$SYMLINK")"
        [[ "$current" == "$AR0X_BUILD_ROOT" ]] \
            && ok "build/ already points to ${current}" \
            || warn "build/ points to ${current}, expected ${AR0X_BUILD_ROOT}; leaving it alone."
    elif [[ -e "$SYMLINK" ]]; then
        fail "${SYMLINK} exists and is not a symlink. Remove it manually or pass --no-symlink."
    else
        ln -s -- "$AR0X_BUILD_ROOT" "$SYMLINK"
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            chown -h -- "${SUDO_USER}:$(id -gn "$SUDO_USER")" "$SYMLINK" 2>/dev/null || true
        fi
        ok "Created ${SYMLINK} -> ${AR0X_BUILD_ROOT}"
    fi
fi

# --- Section 12: optional services -------------------------------------------
if (( WITH_DOCKER == 1 )); then
    section "Enabling Docker"
    if have_command systemctl && systemctl is-system-running >/dev/null 2>&1; then
        systemctl enable --now docker.service 2>&1 | tee -a "$SETUP_LOG" \
            || warn "Could not enable docker.service (common inside containers). Start it manually on the host."
    else
        warn "systemd not running here; start docker.service on the host manually."
    fi
fi

# --- Section 13: verify the toolchain ----------------------------------------
section "Verifying the installed toolchain"
for cmd in mkarchiso pacstrap xorriso mksquashfs mkfs.erofs mkfs.vfat mformat \
           grub-mkstandalone syslinux gpg sbsign openssl cmake ninja makepkg \
           namcap shellcheck jq; do
    have_command "$cmd" && ok "$cmd" || fail "$cmd is missing after installation"
done
if (( SKIP_QEMU == 0 )); then
    have_command qemu-system-x86_64 && ok "qemu-system-x86_64" || fail "qemu-system-x86_64 missing"
    for fw in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd; do
        [[ -f "$fw" ]] && ok "OVMF: ${fw}" || warn "OVMF firmware not found at ${fw} (Phase 11 UEFI test needs it)."
    done
fi

# archiso is rolling: a newer host version is acceptable but must be recorded.
INSTALLED_ARCHISO="$(pacman -Q archiso 2>/dev/null | awk '{print $2}' || printf 'NOT-INSTALLED')"
if [[ "$INSTALLED_ARCHISO" == "$AR0X_ARCHISO_VERSION" ]]; then
    ok "archiso ${INSTALLED_ARCHISO} matches the Phase 1 pin"
elif [[ "$INSTALLED_ARCHISO" == "NOT-INSTALLED" ]]; then
    fail "archiso is not installed"
else
    warn "Host archiso ${INSTALLED_ARCHISO} differs from pinned ${AR0X_ARCHISO_VERSION}. Profile syntax is written for 92; re-verify profiledef.sh keys (buildmodes/bootmodes) in Phase 3."
fi

# --- Section 14: run the Phase 1 validator + write a host manifest -----------
section "Final validation"
bash "${AR0X_TOOLS_DIR}/validate-versions.sh" || die "Phase 1 validator failed; fix before Phase 3."
report_host "${AR0X_LOG_DIR}/host-manifest.txt"
assert_clean

# --- Section 15: next steps ---------------------------------------------------
cat <<EOF

${_AR0X_C_OK}✅ Phase 2 build environment is ready.${_AR0X_C_RST}

  Build root : ${AR0X_BUILD_ROOT}
  Manifest   : ${AR0X_LOG_DIR}/host-manifest.txt
  Log        : ${SETUP_LOG}

Verify manually (no root needed):
  ./tools/setup-build-env.sh --check
  mkarchiso -h
  ls -ld ${AR0X_KEYS_DIR}            # must be drwx------
  findmnt -no OPTIONS --target ${AR0X_BUILD_ROOT}   # must NOT contain noexec/nodev

Phase 3 will create:
  archiso/profiledef.sh  archiso/packages.x86_64  archiso/pacman.conf
  archiso/airootfs/      tools/bootstrap.sh

⚠️ MANUAL: run this script as root on a real Arch x86_64 host. It cannot be
   executed in the Arena sandbox (no root, no loop devices, no KVM).
EOF
exit 0
