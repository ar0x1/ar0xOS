#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/validate-versions.sh
# -----------------------------------------------------------------------------
# Phase 1 helper — validates version pins, build-tree structure, and the two
# "stale upstream" traps before ANY build stage runs.
#
# This script is SAFE TO RUN IN A NON-ROOT SANDBOX: it only reads local files.
# Phase 11's build-iso.sh MUST call it as stage 1 and abort on any failure.
#
# Checks performed:
#   1. config/versions.env exists, parses, and every required key is non-empty.
#   2. Hyprland config format is Lua; NO stray hyprland.conf anywhere (RISK-002).
#   3. Calamares pin is 3.4.3 from Codeberg, not the archived GitHub 3.3.14 (RISK-003).
#   4. No custom kernel patches in v0.1 (RISK-001).
#   5. If config/pacman.conf.build exists, its archive date matches the pin
#      and it does NOT leak into the installed pacman.conf (RISK-006).
#   6. Every tools/*.sh has the mandated shebang + `set -euo pipefail`.
#   7. Required directory skeleton exists.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Resolve the SOURCE ROOT from this script's own location (no assumptions) -
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
VERSIONS_FILE="${AR0X_SOURCE_ROOT}/config/versions.env"

# --- Colours / logging helpers (local; tools/lib/common.sh arrives in Phase 2) -
if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RST=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_RST=""
fi
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK"   "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_ERR"  "$C_RST" "$*" >&2; exit 1; }

ERRORS=0
fail() { printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; ERRORS=$((ERRORS + 1)); }

# --- Section 1: load and validate versions.env --------------------------------
[[ -f "$VERSIONS_FILE" ]] || die "Missing ${VERSIONS_FILE} (Phase 1 deliverable)."
# shellcheck source=/dev/null
source "$VERSIONS_FILE"
ok "Loaded ${VERSIONS_FILE}"

REQUIRED_KEYS=(
    AR0X_VERSION AR0X_ARCH AR0X_ISO_LABEL AR0X_ISO_MAX_BYTES
    AR0X_SNAPSHOT_DATE AR0X_ARCHIVE_URL
    AR0X_GLIBC_VERSION AR0X_SYSTEMD_VERSION AR0X_KERNEL_VERSION
    AR0X_KERNEL_FLAVOR AR0X_MKINITCPIO_VERSION AR0X_GRUB_VERSION
    AR0X_INSTALL_DIR AR0X_ARCHISO_VERSION AR0X_ARCHISO_BUILDMODES
    AR0X_ARCHISO_BOOTMODES AR0X_ARCHISO_AIROOTFS_TYPE AR0X_HARD_PIN_REPO_PRIORITY
    AR0X_HYPRLAND_VERSION AR0X_HYPR_CONFIG_FORMAT AR0X_HYPR_CONFIG_ENTRY
    AR0X_CALAMARES_VERSION AR0X_CALAMARES_SOURCE AR0X_CALAMARES_SHA256
    AR0X_DEFAULT_SHELL AR0X_SCRIPT_SHELL AR0X_CYAN AR0X_VOID
    AR0X_SECURE_BOOT AR0X_APPARMOR_MODE AR0X_CUSTOM_KERNEL_PATCHES
)
for key in "${REQUIRED_KEYS[@]}"; do
    if [[ -z "${!key:-}" ]]; then
        fail "Required version key is empty or missing: ${key}"
    fi
done
ok "All ${#REQUIRED_KEYS[@]} required version keys are non-empty"

# --- Section 2: Hyprland 0.57 Lua gate (RISK-002) ----------------------------
if [[ "${AR0X_HYPR_CONFIG_FORMAT}" != "lua" || "${AR0X_HYPR_CONFIG_ENTRY}" != "hyprland.lua" ]]; then
    fail "Hyprland >= 0.57 requires Lua config. Set AR0X_HYPR_CONFIG_FORMAT=lua and AR0X_HYPR_CONFIG_ENTRY=hyprland.lua."
fi
STRAY_CONF="$(find "${AR0X_SOURCE_ROOT}/config" "${AR0X_SOURCE_ROOT}/archiso" \
                  "${AR0X_SOURCE_ROOT}/packages" -type f -name 'hyprland.conf' \
                  -print 2>/dev/null || true)"
if [[ -n "$STRAY_CONF" ]]; then
    fail "Stray hyprland.conf found (0.57 ignores it): ${STRAY_CONF//$'\n'/, }"
fi
ok "Hyprland Lua config gate passed (pinned ${AR0X_HYPRLAND_VERSION}, no stray .conf)"

# --- Section 3: Calamares upstream gate (RISK-003) ---------------------------
if [[ "${AR0X_CALAMARES_VERSION}" != "3.4.3" || "${AR0X_CALAMARES_SOURCE}" != "codeberg" ]]; then
    fail "Calamares must be 3.4.3 from Codeberg; github.com/calamares/calamares is an archived mirror at 3.3.14."
fi
if [[ "${#AR0X_CALAMARES_SHA256}" -ne 64 ]]; then
    fail "AR0X_CALAMARES_SHA256 is not a 64-char SHA256 digest."
fi
if [[ "${AR0X_CALAMARES_URL}" == *"github.com"* ]]; then
    fail "Calamares download URL points at GitHub; use the Codeberg release tarball."
fi
ok "Calamares gate passed (${AR0X_CALAMARES_VERSION} / ${AR0X_CALAMARES_SOURCE})"

# --- Section 4: no custom kernel patches in v0.1 (RISK-001) -----------------
if [[ "${AR0X_CUSTOM_KERNEL_PATCHES}" != "none" ]]; then
    warn "RISK-001: custom kernel patches are enabled (${AR0X_CUSTOM_KERNEL_PATCHES}). v0.1 must use stock linux-lts."
    fail "Set AR0X_CUSTOM_KERNEL_PATCHES=none or explicitly acknowledge RISK-001 in Phase 4."
fi
PATCH_COUNT="$(find "${AR0X_SOURCE_ROOT}/config/kernel/patches" -maxdepth 1 \
                   -type f \( -name '*.patch' -o -name '*.diff' \) -print 2>/dev/null | wc -l)"
if [[ "$PATCH_COUNT" -gt 0 ]]; then
    fail "RISK-001: ${PATCH_COUNT} kernel patch file(s) present but pin says none."
fi
ok "Kernel gate passed (stock ${AR0X_KERNEL_FLAVOR} ${AR0X_KERNEL_VERSION}, zero patches)"

# --- Section 4b: archiso 92 profile contract (RISK-017) ---------------------
# Phase 2 correction: upstream is 92-1, and its profiledef.sh uses buildmodes /
# bootmodes. Asserting this here prevents Phase 3 from shipping an 91-style
# profile that mkarchiso 92 would reject.
if [[ "${AR0X_ARCHISO_VERSION}" != "92-1" ]]; then
    fail "archiso pin is ${AR0X_ARCHISO_VERSION}; verified upstream release is 92-1 (see docs/BUILD_HOST.md §3)."
fi
if [[ "${AR0X_ARCHISO_BUILDMODES}" != "iso" ]]; then
    fail "archiso 92 buildmodes must be 'iso' (got '${AR0X_ARCHISO_BUILDMODES}')."
fi
if [[ "${AR0X_ARCHISO_BOOTMODES}" != *"bios.syslinux"* || "${AR0X_ARCHISO_BOOTMODES}" != *"uefi.grub"* ]]; then
    fail "archiso 92 bootmodes must include bios.syslinux AND uefi.grub (got '${AR0X_ARCHISO_BOOTMODES}')."
fi
if [[ "${AR0X_HARD_PIN_REPO_PRIORITY}" != "first" ]]; then
    fail "ADR-017: the [ar0x] repo must be listed FIRST in pacman.conf.build for HARD pins to win."
fi
ok "archiso 92-1 profile contract + ADR-017 repo ordering verified"

# --- Section 5: frozen pacman.conf must not leak to installed systems --------
BUILD_CONF="${AR0X_SOURCE_ROOT}/config/pacman.conf.build"
INSTALL_CONF="${AR0X_SOURCE_ROOT}/config/pacman.conf.installed"
if [[ -f "$BUILD_CONF" ]]; then
    if ! grep -Fq "archive.archlinux.org/repos/${AR0X_SNAPSHOT_DATE}" "$BUILD_CONF"; then
        fail "config/pacman.conf.build does not pin the snapshot date ${AR0X_SNAPSHOT_DATE}."
    fi
    ok "Build pacman.conf pins the frozen archive date ${AR0X_SNAPSHOT_DATE}"
else
    warn "config/pacman.conf.build not created yet (expected: Phase 3)."
fi
if [[ -f "$INSTALL_CONF" ]]; then
    if grep -v '^[[:space:]]*#' "$INSTALL_CONF" | grep -Fq "archive.archlinux.org"; then
        fail "RISK-006: installed pacman.conf contains a frozen archive mirror."
    fi
    if ! grep -Fq "[ar0x]" "$INSTALL_CONF"; then
        fail "installed pacman.conf is missing the [ar0x] repository entry (expected by Phase 9)."
    fi
    ok "Installed pacman.conf has no frozen mirror and declares [ar0x]"
else
    warn "config/pacman.conf.installed not created yet (expected: Phase 5/9)."
fi

# --- Section 6: script hygiene (#!/bin/bash + set -euo pipefail) -------------
SCRIPT_COUNT=0
# Check EVERY shell script in the repo (tools/, docker/, vagrant/), not just
# tools/, so the Phase 2 container and VM helper scripts are covered too.
while IFS= read -r -d '' sh; do
    # Exempt SOURCED config snippets, which are not standalone scripts:
    #   * archiso/profiledef.sh     -> sourced by mkarchiso (strict mode would
    #                                  leak into mkarchiso itself)
    #   * config/system/profile.d/  -> sourced by zsh/bash LOGIN shells; a
    #                                  shebang or set -euo pipefail is invalid
    #                                  and would break every login shell
    case "$sh" in
        */archiso/profiledef.sh|*/config/system/profile.d/*.sh|*/archiso/airootfs/etc/profile.d/*.sh) continue ;;
    esac
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
    first_line="$(head -n 1 -- "$sh")"
    [[ "$first_line" == "#!/bin/bash" ]] || fail "${sh}: first line must be #!/bin/bash (got '${first_line}')."
    grep -Eq '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail' "$sh" \
        || fail "${sh}: missing 'set -euo pipefail'."
done < <(find "${AR0X_SOURCE_ROOT}" \
             -path "${AR0X_SOURCE_ROOT}/.git" -prune -o \
             -type f -name '*.sh' -print0 2>/dev/null)
ok "Script hygiene passed for ${SCRIPT_COUNT} shell script(s)"

# --- Section 7: required directory skeleton ----------------------------------
REQUIRED_DIRS=(
    docs/architecture config/kernel/patches config/system config/desktop/hypr
    config/branding config/calamares/modules config/repo archiso/airootfs/etc
    archiso/grub archiso/isolinux archiso/syslinux assets/logo assets/wallpapers
    assets/plymouth assets/grub-theme assets/sddm packages tools/lib ci/workflows
    tests repo/x86_64 docker vagrant
    archiso/grub archiso/syslinux archiso/airootfs/etc/mkinitcpio.conf.d
    config/kernel config/mkinitcpio.d config/default config/plymouth
    assets/grub-theme/ar0x assets/plymouth/ar0x assets/syslinux
    archiso/grub/themes/ar0x archiso/airootfs/usr/share/plymouth/themes/ar0x
)
for d in "${REQUIRED_DIRS[@]}"; do
    [[ -d "${AR0X_SOURCE_ROOT}/${d}" ]] || fail "Missing directory: ${d}/"
done
ok "Directory skeleton present (${#REQUIRED_DIRS[@]} required paths)"

# --- Section 7b: Phase 2 deliverable files -----------------------------------
PHASE2_FILES=(
    tools/setup-build-env.sh tools/lib/common.sh docs/BUILD_HOST.md
    docker/Dockerfile docker/compose.yaml docker/run.sh
    vagrant/provision.sh Vagrantfile
)
for f in "${PHASE2_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 2 deliverable: ${f}"
done
ok "Phase 2 deliverable files present (${#PHASE2_FILES[@]} files)"

# --- Section 7c: Phase 3 deliverable files -----------------------------------
PHASE3_FILES=(
    config/pacman.conf.build config/packages.x86_64
    config/bootstrap_packages.x86_64
    archiso/profiledef.sh archiso/pacman.conf archiso/packages.x86_64
    archiso/bootstrap_packages.x86_64 archiso/grub/grub.cfg
    archiso/syslinux/syslinux.cfg
    archiso/airootfs/etc/mkinitcpio.conf.d/archiso.conf
    archiso/airootfs/etc/hostname archiso/airootfs/etc/locale.conf
    archiso/airootfs/etc/pacman.d/hooks/90-ar0x-build-stamp.hook
    tools/bootstrap.sh docs/BOOTSTRAP_GUIDE.md
)
for f in "${PHASE3_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 3 deliverable: ${f}"
done
ok "Phase 3 deliverable files present (${#PHASE3_FILES[@]} files)"

# --- Section 7d: Phase 4 deliverable files + RISK-001 -----------------------
PHASE4_FILES=(
    config/kernel/README.md config/kernel/ar0x-lts.config
    config/mkinitcpio.conf config/mkinitcpio.d/linux-lts.preset
    config/default/grub config/plymouth/plymouthd.conf
    assets/grub-theme/ar0x/theme.txt assets/grub-theme/ar0x/background.png
    assets/plymouth/ar0x/ar0x.plymouth assets/plymouth/ar0x/ar0x.script
    assets/plymouth/ar0x/logo.png assets/syslinux/splash.png
    archiso/grub/themes/ar0x/theme.txt archiso/syslinux/splash.png
    tools/build-kernel.sh tools/gen-theme-assets.sh docs/KERNEL_BOOT.md
)
for f in "${PHASE4_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 4 deliverable: ${f}"
done
ok "Phase 4 deliverable files present (${#PHASE4_FILES[@]} files)"

# --- Section 7e: Phase 5 deliverable files + policy gates --------------------
PHASE5_FILES=(
    config/pacman.conf.installed config/repo/pacman.conf.ar0x-entry
    config/system/hostname config/system/hosts config/system/locale.conf
    config/system/locale.gen config/system/vconsole.conf config/system/localtime
    config/system/passwd config/system/shadow config/system/nftables.conf
    config/system/sysusers.d/ar0x-live.conf
    config/system/sudoers.d/10-ar0x-wheel
    config/system/NetworkManager/conf.d/10-ar0x.conf
    config/system/pipewire/pipewire.conf.d/10-ar0x.conf
    config/system/pipewire/wireplumber.conf.d/10-ar0x.conf
    config/system/environment.d/10-ar0x-wayland.conf
    config/system/sysctl.d/50-ar0x-security.conf
    config/system/sysctl.d/60-ar0x-network.conf
    config/system/systemd/system-preset/50-ar0x.preset
    config/system/systemd/system/apparmor.service.d/10-ar0x-complain.conf
    tools/configure-system.sh docs/SYSTEM_CONFIG.md
)
for f in "${PHASE5_FILES[@]}"; do
    [[ -e "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 5 deliverable: ${f}"
done
ok "Phase 5 deliverable files present (${#PHASE5_FILES[@]} files)"

# Developer toolchain compatibility must survive sysctl hardening.
grep -Fq 'kernel.unprivileged_userns_clone = 1' \
    "${AR0X_SOURCE_ROOT}/config/system/sysctl.d/50-ar0x-security.conf" \
    || fail "RISK-014: unprivileged user namespaces must stay ENABLED for developers."
# AppArmor complain mode in v0.1.
[[ "${AR0X_APPARMOR_MODE}" == "complain" ]] \
    || fail "RISK-008: AppArmor must stay in complain mode in v0.1."
# WirePlumber 0.5+ correction: legacy 0.4 skeleton dir must be gone.
[[ ! -d "${AR0X_SOURCE_ROOT}/config/system/wireplumber" ]] \
    || fail "WirePlumber 0.4 legacy config dir present; use config/system/pipewire/wireplumber.conf.d/."
[[ ! -d "${AR0X_SOURCE_ROOT}/config/system/apparmor" ]] \
    || fail "Empty config/system/apparmor/ skeleton present; ar0x ships no custom profiles."
ok "Phase 5 policy gates: userns enabled, AppArmor complain, WP 0.5+ path"

PKG_DUPES="$(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' \
    "${AR0X_SOURCE_ROOT}/config/packages.x86_64" | sort | uniq -d)"
if [[ -n "$PKG_DUPES" ]]; then
    fail "Duplicate package(s) in config/packages.x86_64: ${PKG_DUPES}"
else
    ok "Package list contains no duplicates"
fi

# RISK-001: zero kernel patches in v0.1 (stock LTS binary kernel only).
PATCH_COUNT="$(find "${AR0X_SOURCE_ROOT}/config/kernel/patches" -type f \
    \( -name '*.patch' -o -name '*.diff' \) 2>/dev/null | wc -l)"
if (( PATCH_COUNT > 0 )); then
    fail "RISK-001: ${PATCH_COUNT} kernel patch(es) found. ar0x v0.1 uses stock linux-lts."
else
    ok "RISK-001: zero kernel patches (stock linux-lts ${AR0X_KERNEL_VERSION})"
fi
# A zstd initramfs is only bootable if the kernel can decompress it.
if [[ -f "${AR0X_SOURCE_ROOT}/config/kernel/ar0x-lts.config" ]]; then
    grep -Fq 'CONFIG_RD_ZSTD=y' "${AR0X_SOURCE_ROOT}/config/kernel/ar0x-lts.config" \
        || fail "zstd initramfs requires CONFIG_RD_ZSTD=y in the kernel audit contract."
    ok "CONFIG_RD_ZSTD=y asserted for zstd initramfs"
fi

# --- Final verdict -----------------------------------------------------------
if [[ "$ERRORS" -gt 0 ]]; then
    die "Validation FAILED with ${ERRORS} error(s). Fix them before running build-iso.sh."
fi
printf '\n%s✅ ar0x version + structure validation PASSED%s\n' "$C_OK" "$C_RST"
printf '   Distro       : ar0x %s (%s)\n' "${AR0X_VERSION}" "${AR0X_CODENAME:-}"
printf '   Kernel       : %s %s\n' "${AR0X_KERNEL_FLAVOR}" "${AR0X_KERNEL_VERSION}"
printf '   Snapshot     : %s\n' "${AR0X_SNAPSHOT_DATE}"
printf '   Desktop      : Hyprland %s (%s config)\n' "${AR0X_HYPRLAND_VERSION}" "${AR0X_HYPR_CONFIG_FORMAT}"
printf '   Installer    : Calamares %s (%s)\n' "${AR0X_CALAMARES_VERSION}" "${AR0X_CALAMARES_SOURCE}"
exit 0
