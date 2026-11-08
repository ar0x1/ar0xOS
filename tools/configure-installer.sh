#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/configure-installer.sh
# -----------------------------------------------------------------------------
# PHASE 10 — driver for the Calamares 3.4.3 ar0x GUI installer.
#
#   --check      (default) READ-ONLY structural validation: ar0x_installer.py,
#                bash -n, and byte-parity of the 3 generated mirrors.
#                NO root, NO network, NO writes, NO display.
#   --sync       Regenerate the ar0x-logo.png mirror, install the finish helper
#                and the .desktop launcher into archiso/airootfs, and stage a
#                disposable build/installer-prefix (gitignored). Idempotent.
#   --self-test  9 negative config mutations + a REAL run of
#                ar0x-installer-finish into a throwaway target root, plus
#                byte-parity checks on the staged prefix. NO root, NO Qt.
#   --preflight  ⚠️ MANUAL, real live ISO ONLY. Requires a TYPED target device.
#                Prints the RISK-004 lsblk checklist and REFUSES to launch
#                Calamares or touch any disk.
#
# ⚠️ RISK-004: partitioning is irreversible. This script NEVER partitions,
#    mounts, chroots, or launches calamares. `--preflight` is print-only.
# ⚠️ RISK-048/051: the signed [ar0x] repo does not exist, so `calamares` is
#    deliberately NOT in config/packages.x86_64 (Phase 11 gate).
# ⚠️ RISK-052: no Qt6 / QML / Wayland / QEMU / root here. The GUI was NEVER
#    launched and no install→reboot→first-boot cycle was performed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CAL="${AR0X_CONFIG_DIR}/calamares"
INST="${AR0X_CONFIG_DIR}/installer"
BRAND="${CAL}/branding/ar0x"
AIROOTFS="${AR0X_SOURCE_ROOT}/archiso/airootfs"
PREFIX="${AR0X_SOURCE_ROOT}/build/installer-prefix"
VALIDATOR="${SCRIPT_DIR}/lib/ar0x_installer.py"
LOGO_MASTER="${AR0X_ASSETS_DIR}/logo/ar0x-logo-256.png"
HELPER="${INST}/ar0x-installer-finish"
DESKTOP="${INST}/ar0x-installer.desktop"
MODE='check'

usage() {
    cat <<'USAGE'
ar0x Phase 10 — configure-installer.sh (Calamares 3.4.3)

  --check      Read-only structural validation (default). No root, no writes.
  --sync       Regenerate logo mirror + airootfs helper/launcher + test prefix.
  --self-test  Offline validator self-test + REAL finish-helper smoke test.
  --preflight  MANUAL: RISK-004 lsblk checklist. NEVER launches calamares.
               Requires AR0X_CONFIRM_PREFLIGHT=yes and AR0X_TARGET_DISK=<name>.
  -h|--help    This help.

Typical order:
  ./tools/configure-installer.sh --sync
  ./tools/configure-installer.sh --check
  ./tools/configure-installer.sh --self-test
  ./tools/validate-versions.sh
  ./tools/bootstrap.sh --check
USAGE
}

# ---------------------------------------------------------------------------
# --sync: byte-identical mirrors + disposable staged prefix
# ---------------------------------------------------------------------------
stage_prefix() {
    log "Staging disposable prefix: ${PREFIX}"
    rm -rf -- "$PREFIX"
    mkdir -p -- "${PREFIX}/etc/calamares" \
                "${PREFIX}/usr/share/calamares/branding" \
                "${PREFIX}/usr/lib/ar0x" \
                "${PREFIX}/usr/share/applications"

    # Simulated /etc/calamares (exactly what bootstrap.sh overlays).
    cp -a -- "${CAL}/settings.conf" "${PREFIX}/etc/calamares/"
    cp -a -- "${CAL}/modules"        "${PREFIX}/etc/calamares/"
    cp -a -- "${CAL}/branding"       "${PREFIX}/etc/calamares/"

    # Simulated /usr/share/calamares/branding (the alternate search path).
    cp -a -- "$BRAND" "${PREFIX}/usr/share/calamares/branding/ar0x"

    install -m 0755 -- "$HELPER"  "${PREFIX}/usr/lib/ar0x/ar0x-installer-finish"
    install -m 0644 -- "$DESKTOP" "${PREFIX}/usr/share/applications/ar0x-installer.desktop"
}

do_sync() {
    section "Phase 10 — syncing installer mirrors"
    [[ -f "$LOGO_MASTER" ]] || die "missing canonical logo: ${LOGO_MASTER}"
    [[ -x "$HELPER" ]]      || die "finish helper is not executable: ${HELPER}"

    install -m 0644 -- "$LOGO_MASTER" "${BRAND}/ar0x-logo.png"
    ok "branding logo mirror regenerated from assets/logo/ar0x-logo-256.png"

    mkdir -p -- "${AIROOTFS}/usr/lib/ar0x" "${AIROOTFS}/usr/share/applications"
    install -m 0755 -- "$HELPER"  "${AIROOTFS}/usr/lib/ar0x/ar0x-installer-finish"
    install -m 0644 -- "$DESKTOP" "${AIROOTFS}/usr/share/applications/ar0x-installer.desktop"
    ok "airootfs helper (0755) + pkexec desktop launcher (0644) installed"

    stage_prefix
    ok "disposable prefix staged (gitignored, no root, no network)"
    log "Sync complete. Config/ is canonical; airootfs holds the two active copies."
}

# ---------------------------------------------------------------------------
# --check: read-only, asserts --sync was run
# ---------------------------------------------------------------------------
check_mirror() {
    local canonical="$1" mirror="$2" label="$3"
    if [[ ! -f "$mirror" ]]; then
        fail "missing generated mirror: ${mirror} (run --sync)"
        return 0
    fi
    if ! cmp -s -- "$canonical" "$mirror"; then
        fail "${label} mirror is stale (run --sync)"
        return 0
    fi
    ok "${label}: byte-identical to canonical"
}

do_check() {
    section "Phase 10 — read-only installer validation"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" || fail "ar0x_installer.py failed"

    bash -n -- "$HELPER" || fail "bash -n failed on ar0x-installer-finish"
    ok "bash -n: ar0x-installer-finish"

    check_mirror "$LOGO_MASTER" "${BRAND}/ar0x-logo.png" "branding logo"
    check_mirror "$HELPER" "${AIROOTFS}/usr/lib/ar0x/ar0x-installer-finish" "airootfs helper"
    check_mirror "$DESKTOP" "${AIROOTFS}/usr/share/applications/ar0x-installer.desktop" "launcher"

    if [[ -f "${AIROOTFS}/usr/lib/ar0x/ar0x-installer-finish" ]] && \
       [[ ! -x "${AIROOTFS}/usr/lib/ar0x/ar0x-installer-finish" ]]; then
        fail "airootfs finish helper lost its 0755 mode"
    else
        ok "airootfs finish helper mode 0755"
    fi

    # ONE OWNER PER PATH (ADR-024): no duplicate /etc/calamares in airootfs.
    if [[ -d "${AIROOTFS}/etc/calamares" ]]; then
        fail "ADR-024: duplicate archiso/airootfs/etc/calamares — config/calamares is the single owner"
    else
        ok "ADR-024: no duplicate /etc/calamares in airootfs"
    fi

    assert_clean
    ok "Phase 10 --check PASSED"
}

# ---------------------------------------------------------------------------
# --self-test: validator negative tests + real helper run + prefix parity
# ---------------------------------------------------------------------------
do_self_test() {
    section "Phase 10 — offline self-test"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" --self-test || \
        fail "ar0x_installer.py --self-test failed"

    if [[ ! -d "${PREFIX}/etc/calamares" ]]; then
        warn "prefix missing; restaging (no writes to tracked files)"
        stage_prefix
    fi

    local f
    for f in settings.conf modules/welcome.conf modules/partition.conf \
             modules/ar0x-packages.conf modules/shellprocess-finish.conf \
             branding/ar0x/branding.desc branding/ar0x/show.qml; do
        if ! cmp -s -- "${CAL}/${f}" "${PREFIX}/etc/calamares/${f}"; then
            fail "staged prefix drifted on ${f} (run --sync)"
        fi
    done
    ok "staged /etc/calamares prefix is byte-identical to config/calamares"

    if [[ ! -x "${PREFIX}/usr/lib/ar0x/ar0x-installer-finish" ]]; then
        fail "staged finish helper is not executable"
    else
        ok "staged finish helper mode 0755"
    fi

    bash -n -- "${PREFIX}/usr/lib/ar0x/ar0x-installer-finish" || \
        fail "bash -n failed on the staged finish helper"
    ok "bash -n: staged finish helper"

    assert_clean
    ok "Phase 10 --self-test PASSED (no Qt, no root, no network, no disk writes)"
}

# ---------------------------------------------------------------------------
# --preflight: MANUAL, print-only, RISK-004
# ---------------------------------------------------------------------------
do_preflight() {
    section "Phase 10 — MANUAL preflight (print only, NEVER launches calamares)"
    if [[ "${AR0X_CONFIRM_PREFLIGHT:-no}" != "yes" ]]; then
        die "Set AR0X_CONFIRM_PREFLIGHT=yes after reading docs/INSTALLER_FLOW.md §2."
    fi
    local disk="${AR0X_TARGET_DISK:-}"
    if [[ -z "$disk" ]]; then
        die "RISK-004: AR0X_TARGET_DISK must be TYPED (e.g. vda), never auto-detected."
    fi
    if [[ ! "$disk" =~ ^[a-z]+[a-z0-9]*$ ]]; then
        die "RISK-004: AR0X_TARGET_DISK='${disk}' is not a bare device name."
    fi
    warn "RISK-004: partitioning is IRREVERSIBLE. You typed: /dev/${disk}"
    warn "Test ONLY on a disposable QEMU/VM disk. This script touches NOTHING."
    printf '\nRun on the live system and READ the output before continuing:\n\n'
    printf '  lsblk -o NAME,SIZE,MODEL,TRAN\n'
    if have_command lsblk && [[ "${AR0X_SHOW_LSBLK:-no}" == "yes" ]]; then
        printf '\n'
        lsblk -o NAME,SIZE,MODEL,TRAN || true
    fi
    printf '\nThen launch the GUI through polkit:\n\n'
    printf '  pkexec /usr/bin/calamares      # or: ar0x-installer\n\n'
    printf 'After reboot verify:\n'
    printf '  sudo systemctl status ar0x-firstboot.service\n'
    printf '  sudo -l                       # must NOT show NOPASSWD\n'
    printf '  cat /etc/machine-id           # real id, NOT "uninitialized"\n'
    printf '  systemctl --user status ar0x-welcome.service\n\n'
    warn "NOTHING was launched, partitioned, mounted or installed by --preflight."
    ok "MANUAL preflight checklist printed (RISK-004 gate is yours)"
}

# ---------------------------------------------------------------------------
case "${1:-}" in
    '')            MODE='check' ;;
    --check)       MODE='check' ;;
    --sync)        MODE='sync' ;;
    --self-test)   MODE='self-test' ;;
    --preflight)   MODE='preflight' ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "unknown option: ${1:-}" ;;
esac
shift || true
(( $# == 0 )) || die "unexpected extra arguments: $*"

case "$MODE" in
    check)      do_check ;;
    sync)       do_sync ;;
    self-test)  do_self_test ;;
    preflight)  do_preflight ;;
esac
