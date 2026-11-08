#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/configure-system.sh
# -----------------------------------------------------------------------------
# PHASE 5 — Core system configuration: networking, audio, Wayland env, users,
# locale/timezone/keyboard, journald, nftables, AppArmor and sysctl.
#
# All canonical configs live in config/system/** which maps 1:1 to /etc/**
# (BUILD_LAYOUT.md §4). This script:
#   --check   Read-only validation. NO root, NO writes. (default)
#   --sync    Copy config/system/** -> archiso/airootfs/etc/** and
#             config/pacman.conf.installed -> archiso/airootfs/etc/pacman.conf.
#             NO root. (tools/bootstrap.sh ALSO overlays config/system/** into
#             its disposable staged profile at build time.)
#   --apply   ⚠️ MANUAL, ROOT: locale-gen + systemctl preset-all inside the
#             airootfs chroot, plus SAFE syntax checks.
#
# ⚠️ HOST-KERNEL SAFETY: `sysctl --system` and `nft -f` are NEVER run inside a
#    chroot. Sysctls and nftables rulesets are HOST-kernel globals; running them
#    in a chroot silently reconfigures the BUILD MACHINE, not the image.
#    --apply only uses `nft -c -f` (check) and `visudo -cf` (check).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SYS="${AR0X_CONFIG_DIR}/system"
PROFILE="${AR0X_PROFILE}"
AIROOTFS="${AR0X_WORK_DIR}/x86_64/airootfs"
BUILD_CONF="${AR0X_CONFIG_DIR}/pacman.conf.build"
INSTALL_CONF="${AR0X_CONFIG_DIR}/pacman.conf.installed"
REPO_ENTRY="${AR0X_CONFIG_DIR}/repo/pacman.conf.ar0x-entry"
PRESET="${SYS}/systemd/system-preset/50-ar0x.preset"
LOG_FILE="${AR0X_LOG_DIR}/04-system-config.log"

MODE="check"

usage() {
    cat <<'USAGE'
ar0x Phase 5 — configure-system.sh

  --check   Read-only validation (default). No root, no writes.
  --sync    Regenerate archiso/airootfs/etc/** from config/system/**.
  --apply   ⚠️ ROOT: locale-gen + systemctl preset-all inside the airootfs
            chroot, plus nft/visudo SYNTAX CHECKS (never applies host rules).
  -h|--help This help.

Examples:
  ./tools/configure-system.sh --check
  ./tools/configure-system.sh --sync
  sudo ./tools/bootstrap.sh --iso-only
  sudo ./tools/configure-system.sh --apply
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)     MODE="check" ;;
        --sync)      MODE="sync" ;;
        --apply)     MODE="apply" ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 1: canonical file inventory -------------------------------------
SYS_FILES=(
    hostname hosts locale.conf locale.gen vconsole.conf localtime
    passwd shadow sysusers.d/ar0x-live.conf sudoers.d/10-ar0x-wheel
    security/limits.d/90-ar0x-audio.conf polkit-1/rules.d/10-ar0x.rules
    NetworkManager/conf.d/10-ar0x.conf
    pipewire/pipewire.conf.d/10-ar0x.conf
    pipewire/wireplumber.conf.d/10-ar0x.conf
    environment.d/10-ar0x-wayland.conf profile.d/ar0x-wayland.sh
    nftables.conf
    sysctl.d/50-ar0x-security.conf sysctl.d/60-ar0x-network.conf
    systemd/journald.conf.d/10-ar0x.conf
    systemd/logind.conf.d/10-ar0x.conf
    systemd/system-preset/50-ar0x.preset
    systemd/system/apparmor.service.d/10-ar0x-complain.conf
)

pkg_in_list() {
    sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/packages.x86_64" \
        | grep -Fxq -- "$1"
}

# --- Section 2: validation ----------------------------------------------------
validate() {
    section "Validating Phase 5 core-system configuration"

    local f
    for f in "${SYS_FILES[@]}"; do
        [[ -e "${SYS}/${f}" ]] && ok "config/system/${f}" \
                               || fail "Missing config/system/${f}"
    done
    for f in "$INSTALL_CONF" "$REPO_ENTRY" "$BUILD_CONF" \
             "tools/configure-system.sh" "docs/SYSTEM_CONFIG.md"; do
        [[ -f "$f" ]] && ok "$(realpath --relative-to="$AR0X_SOURCE_ROOT" "$f" 2>/dev/null || printf '%s' "$f")" \
                      || fail "Missing Phase 5 file: $f"
    done

    # RISK-006: the installed config must be ROLLING; the build config FROZEN.
    # Strip comments first: the file's own RISK-006 warning mentions the domain.
    if grep -v '^[[:space:]]*#' "$INSTALL_CONF" | grep -Fq "archive.archlinux.org"; then
        fail "RISK-006: config/pacman.conf.installed contains a frozen archive mirror."
    else
        ok "Installed pacman.conf is ROLLING (no archive.archlinux.org)"
    fi
    grep -Fq "archive.archlinux.org/repos/${AR0X_SNAPSHOT_DATE}/\$repo/os/\$arch" "$BUILD_CONF" \
        || fail "Build pacman.conf lost its frozen snapshot ${AR0X_SNAPSHOT_DATE}."
    ok "Two pacman.conf files correctly separated (build frozen / installed rolling)"

    grep -Eq '^SigLevel[[:space:]]*=[[:space:]]*Required' "$INSTALL_CONF" \
        || fail "[ar0x] installed SigLevel must be Required."
    grep -Fq 'Server = https://repo.ar0x.dev/$arch' "$INSTALL_CONF" \
        || fail "[ar0x] server missing in installed conf."
    diff -q <(sed -n '/^\[ar0x\]/,/^$/p' "$INSTALL_CONF" | sed '/^$/d') \
            <(sed '/^#/d;/^$/d' "$REPO_ENTRY") >/dev/null 2>&1 \
        || fail "config/repo/pacman.conf.ar0x-entry is out of sync with config/pacman.conf.installed."
    ok "[ar0x] repo entry identical in installed conf + Phase 9 snippet"
    warn "repo.ar0x.dev is a RESERVED endpoint — Phase 9/12 must publish the signed db (MANUAL)."

    # AppArmor kernel params on live + installed + every failsafe entry.
    grep -Fq 'apparmor=1 security=apparmor' "${PROFILE}/profiledef.sh" \
        || fail "profiledef.sh kernel_params_x86_64 missing AppArmor boot params."
    grep -Fq 'apparmor=1 security=apparmor' "${AR0X_CONFIG_DIR}/default/grub" \
        || fail "config/default/grub missing AppArmor boot params."
    local gf sf
    gf="$(grep -c 'apparmor=1 security=apparmor' "${PROFILE}/grub/grub.cfg" || true)"
    sf="$(grep -c 'apparmor=1 security=apparmor' "${PROFILE}/syslinux/syslinux.cfg" || true)"
    (( gf >= 2 )) || fail "GRUB failsafe/text entries are missing AppArmor boot params (found ${gf})."
    (( sf >= 2 )) || fail "syslinux failsafe/text entries are missing AppArmor boot params (found ${sf})."
    ok "AppArmor boot params present on live, installed and ${gf}+${sf} failsafe entries"

    # Presets: NetworkManager ON, systemd-networkd OFF.
    grep -Fxq 'enable NetworkManager.service' "$PRESET" || fail "NetworkManager.service not enabled in preset."
    grep -Fxq 'disable systemd-networkd.service' "$PRESET" || fail "systemd-networkd.service not disabled — two DHCP clients would fight."
    grep -Fxq 'enable nftables.service' "$PRESET" || fail "nftables.service not enabled."
    grep -Fxq 'enable apparmor.service' "$PRESET" || fail "apparmor.service not enabled."
    ok "systemd presets: NetworkManager/nftables/apparmor ON, systemd-networkd OFF"

    # RISK-008: complain mode, and the developer-friendly userns decision.
    grep -Fq 'aa-complain' "${SYS}/systemd/system/apparmor.service.d/10-ar0x-complain.conf" \
        || fail "AppArmor complain-mode drop-in missing."
    grep -Fq 'kernel.unprivileged_userns_clone = 1' "${SYS}/sysctl.d/50-ar0x-security.conf" \
        || fail "Unprivileged user namespaces must stay ENABLED for developers."
    [[ "$AR0X_APPARMOR_MODE" == "complain" ]] || fail "AR0X_APPARMOR_MODE must be complain in v0.1."
    ok "AppArmor complain mode + developer-safe userns sysctl verified"

    # WirePlumber 0.5+ correction.
    [[ -f "${SYS}/pipewire/wireplumber.conf.d/10-ar0x.conf" ]] \
        || fail "WirePlumber 0.5+ fragment must be in config/system/pipewire/wireplumber.conf.d/."
    if [[ -d "${SYS}/wireplumber" ]]; then
        fail "Legacy WirePlumber 0.4 skeleton dir config/system/wireplumber/ still exists."
    fi
    # The Phase 1 skeleton created config/system/apparmor/ for profile DATA, but
    # ar0x ships NO custom profiles and AppArmor policy is toggled with a systemd
    # drop-in instead. Keep the tree honest: no empty placeholder directory.
    if [[ -d "${SYS}/apparmor" ]]; then
        fail "Empty config/system/apparmor/ skeleton dir present; ar0x ships no custom profiles."
    fi
    ok "WirePlumber 0.5+ path corrected (legacy 0.4 dir removed)"

    # Wayland env: no global GDK_BACKEND (breaks XWayland GTK apps).
    if grep -Eq '^[[:space:]]*GDK_BACKEND=' "${SYS}/environment.d/10-ar0x-wayland.conf" \
              "${SYS}/profile.d/ar0x-wayland.sh"; then
        fail "GDK_BACKEND must NOT be forced globally (breaks GTK under XWayland)."
    fi
    ok "Wayland env has no global GDK_BACKEND"

    # Sensitive file modes enforced by archiso profiledef.
    grep -Fq '["/etc/sudoers.d/10-ar0x-wheel"]="0:0:440"' "${PROFILE}/profiledef.sh" \
        || fail "profiledef.sh must set /etc/sudoers.d/10-ar0x-wheel to 0:0:440."
    grep -Fq '["/etc/shadow"]="0:0:400"' "${PROFILE}/profiledef.sh" \
        || fail "profiledef.sh must set /etc/shadow to 0:0:400."
    ok "Sensitive modes asserted: shadow 0400, sudoers drop-in 0440"
    warn "RISK-033: /etc/shadow has EMPTY passwords for root+ar0x on the LIVE ISO only."

    # localtime symlink.
    [[ -L "${SYS}/localtime" ]] && [[ "$(readlink "${SYS}/localtime")" == "/usr/share/zoneinfo/UTC" ]] \
        || fail "config/system/localtime must be a symlink to /usr/share/zoneinfo/UTC."
    ok "UTC timezone symlink verified"

    # Syntax checks (best-effort; tools absent in the sandbox).
    local bad_sysctl
    # -h suppresses the "file:line" prefix that grep adds for multiple inputs.
    bad_sysctl="$(grep -hEv '^[[:space:]]*(#|$)' "${SYS}/sysctl.d/50-ar0x-security.conf" \
                        "${SYS}/sysctl.d/60-ar0x-network.conf" \
                   | grep -Ev '^[a-z0-9._-]+[[:space:]]*=[[:space:]]*[0-9-]+[[:space:]]*$' || true)"
    if [[ -n "$bad_sysctl" ]]; then
        fail "Malformed sysctl line(s): ${bad_sysctl}"
    else
        ok "sysctl key=value syntax valid in both drop-ins"
    fi

    grep -Fq 'table inet ar0x' "${SYS}/nftables.conf" || fail "nftables.conf missing 'table inet ar0x'."
    grep -Fq 'policy drop' "${SYS}/nftables.conf" || fail "nftables.conf must default to policy drop."
    if command -v nft >/dev/null 2>&1; then
        nft -c -f "${SYS}/nftables.conf" >/dev/null 2>&1 \
            && ok "nft -c -f: ruleset syntax OK" \
            || fail "nft -c -f: ruleset syntax ERROR"
    else
        warn "nft not installed here — run 'nft -c -f config/system/nftables.conf' on the Arch host."
    fi
    if command -v visudo >/dev/null 2>&1; then
        visudo -cf "${SYS}/sudoers.d/10-ar0x-wheel" >/dev/null 2>&1 \
            && ok "visudo -cf: sudoers drop-in syntax OK" \
            || fail "visudo -cf: sudoers drop-in syntax ERROR"
    else
        warn "visudo not installed here — run 'visudo -cf config/system/sudoers.d/10-ar0x-wheel' on the Arch host."
    fi

    # Required packages.
    local p
    for p in networkmanager pipewire wireplumber pipewire-pulse rtkit tzdata \
             apparmor nftables sudo polkit; do
        pkg_in_list "$p" || fail "Required Phase 5 package missing from config/packages.x86_64: ${p}"
    done
    ok "All 10 Phase 5 packages present in config/packages.x86_64"
}

# --- Section 3: --sync (no root) ---------------------------------------------
sync_profile() {
    section "Syncing config/system/** -> archiso/airootfs/etc/**"
    local dst="${PROFILE}/airootfs/etc"
    install -d -m 0755 "$dst"
    # tar preserves the /etc/localtime SYMLINK and file modes, and --exclude
    # keeps skeleton .gitkeep placeholders out of the profile. Do NOT blanket
    # delete .gitkeep here: archiso/airootfs/etc/.gitkeep is TRACKED, and
    # tools/bootstrap.sh strips placeholders only in the disposable STAGE.
    tar -C "$SYS" --exclude='.gitkeep' -cf - . | tar -C "$dst" -xf -
    install -m 0644 -- "$INSTALL_CONF" "${dst}/pacman.conf"
    # Git only tracks the executable bit, so enforce sensitive modes explicitly.
    chmod 0400 "${dst}/shadow"
    chmod 0440 "${dst}/sudoers.d/10-ar0x-wheel"
    ok "Profile /etc synced ($(find "$dst" -type f -o -type l | wc -l) files/symlinks)"
    log "Pacman: archiso/airootfs/etc/pacman.conf is the ROLLING installed config."
    log "mkarchiso installs packages with archiso/pacman.conf (FROZEN) — RISK-006 separation intact."
}

# --- Section 4: --apply (root, manual) ---------------------------------------
apply_in_chroot() {
    section "Applying Phase 5 config inside the airootfs chroot"
    require_root
    require_command arch-chroot
    [[ -d "$AIROOTFS" ]] || die "No airootfs at ${AIROOTFS}. Run 'sudo ./tools/bootstrap.sh --iso-only' first."
    if [[ ! -s "${AIROOTFS}/etc/resolv.conf" ]]; then
        cp -L -- /etc/resolv.conf "${AIROOTFS}/etc/resolv.conf"
    fi

    printf '%s⚠️ HOST-KERNEL SAFETY: --apply does NOT run `sysctl --system` or `nft -f`.%s\n' \
        "$_AR0X_C_WARN" "$_AR0X_C_RST"
    printf '   Those are HOST-kernel globals; running them in a chroot would\n'
    printf '   reconfigure the BUILD MACHINE. Only syntax CHECKS are used.\n\n'

    log "locale-gen"
    arch-chroot "$AIROOTFS" /usr/bin/locale-gen 2>&1 | tee -a "$LOG_FILE"
    log "systemctl preset-all (offline symlink operations only)"
    arch-chroot "$AIROOTFS" /usr/bin/systemctl preset-all 2>&1 | tee -a "$LOG_FILE"
    log "nft -c -f /etc/nftables.conf (syntax check, no rules loaded)"
    arch-chroot "$AIROOTFS" /usr/bin/nft -c -f /etc/nftables.conf 2>&1 | tee -a "$LOG_FILE"
    log "visudo -cf /etc/sudoers.d/10-ar0x-wheel (syntax check)"
    arch-chroot "$AIROOTFS" /usr/bin/visudo -cf /etc/sudoers.d/10-ar0x-wheel 2>&1 | tee -a "$LOG_FILE"
    ok "Phase 5 applied in chroot (log: ${LOG_FILE})"
}

# --- Section 5: dispatch -----------------------------------------------------
cd "$AR0X_SOURCE_ROOT"
warn "RISK-033: the LIVE ISO has passwordless root+ar0x (/etc/shadow). Calamares creates real passwords on the target."
case "$MODE" in
    check)
        validate
        assert_clean
        ok "Phase 5 --check PASSED (no root, no writes)"
        printf '\nNext steps on a real Arch host:\n'
        printf '  ./tools/configure-system.sh --sync\n'
        printf '  sudo ./tools/bootstrap.sh --iso-only\n'
        printf '  sudo ./tools/configure-system.sh --apply\n'
        ;;
    sync)
        sync_profile
        validate
        assert_clean
        ok "Phase 5 --sync complete"
        ;;
    apply)
        validate
        assert_clean
        apply_in_chroot
        ;;
esac
