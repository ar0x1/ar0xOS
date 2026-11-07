#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/build-kernel.sh
# -----------------------------------------------------------------------------
# PHASE 4 — Kernel policy + boot stack (stock linux-lts, GRUB/Plymouth themes).
#
# ⚠️ RISK-001: THIS SCRIPT NEVER PATCHES OR COMPILES A KERNEL. ar0x uses the
#    binary `[core] linux-lts 6.18.59-1` package. See config/kernel/README.md.
#    It only: audits the kernel config, syncs initramfs/boot configs and theme
#    files into the archiso profile, locks the full upstream .config, and
#    (optionally) rebuilds the initramfs inside the airootfs chroot.
#
# Modes:
#   --check                 Read-only validation. NO root, NO writes. (default)
#   --sync                  Copy config/{mkinitcpio.conf,mkinitcpio.d,default,plymouth}
#                           and assets/* into archiso/. NO root.
#   --audit-config FILE     Check config/kernel/ar0x-lts.config against a real
#                           kernel config (plain text or .gz). NO root.
#   --lock-config [FILE]    Download/lock the FULL frozen config.x86_64 from the
#                           6.18.59-1 packaging tag and audit it. Needs network.
#   --rebuild-initramfs     ⚠️ MANUAL, ROOT: arch-chroot + mkinitcpio -P +
#                           plymouth-set-default-theme -R ar0x.
#   --self-test             Prove the fragment auditor works on a synthetic
#                           config (used in the sandbox). NO root.
#   --all                   --sync, then --check.
#   -h | --help             Show this help.
#
# Examples:
#   ./tools/build-kernel.sh --check
#   ./tools/build-kernel.sh --self-test
#   ./tools/build-kernel.sh --sync
#   ./tools/build-kernel.sh --audit-config /boot/config-linux-lts
#   ./tools/build-kernel.sh --lock-config
#   sudo ./tools/build-kernel.sh --rebuild-initramfs
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

KERNEL_DIR="${AR0X_CONFIG_DIR}/kernel"
FRAGMENT="${KERNEL_DIR}/ar0x-lts.config"
PATCHES_DIR="${KERNEL_DIR}/patches"
PROFILE="${AR0X_PROFILE}"
ASSETS="${AR0X_ASSETS_DIR}"
OUT="${AR0X_OUT_DIR}"
AIROOTFS="${AR0X_WORK_DIR}/x86_64/airootfs"
# The GitLab packaging TAG is the full package version (6.18.59-1), not the
# upstream kernel version. `${AR0X_KERNEL_VERSION%-*}` would give 6.18.59 and
# 404, so use the full value.
UPSTREAM_CONFIG_URL="https://gitlab.archlinux.org/archlinux/packaging/packages/linux-lts/-/raw/${AR0X_KERNEL_VERSION}/config.x86_64"
LOCK_FILE="${OUT}/kernel-config.lock"
LOG_FILE="${AR0X_LOG_DIR}/03-kernel-boot.log"

MODE="check"
AUDIT_FILE=""

usage() {
    cat <<'USAGE'
ar0x Phase 4 — build-kernel.sh (stock LTS; NO kernel compilation, NO patches)

  --check                 Read-only validation (default). No root, no writes.
  --sync                  Regenerate profile files from config/ + assets/.
  --audit-config FILE     Validate the audit fragment against a real .config.
  --lock-config [FILE]    Fetch/lock the full frozen config.x86_64, then audit.
  --rebuild-initramfs     ⚠️ ROOT: mkinitcpio -P inside the airootfs chroot.
  --self-test             Validate the auditor against a synthetic config.
  --all                   --sync then --check.
  -h | --help             This help.
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)               MODE="check" ;;
        --sync)                MODE="sync" ;;
        --all)                 MODE="all" ;;
        --self-test)           MODE="self-test" ;;
        --audit-config)        MODE="audit"; shift; AUDIT_FILE="${1:-}"; [[ -n "$AUDIT_FILE" ]] || die "--audit-config needs a file." ;;
        --lock-config)         MODE="lock"; if [[ "${2:-}" != "" && "${2:-}" != --* ]]; then AUDIT_FILE="$2"; shift; fi ;;
        --rebuild-initramfs)   MODE="rebuild" ;;
        -h|--help)             usage; exit 0 ;;
        *)                     die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 1: RISK-001 warning ---------------------------------------------
warn_risk_001() {
    printf '\n%s⚠️ RISK-001 — KERNEL PATCHING IS DISABLED FOR ar0x v0.1%s\n' "$_AR0X_C_WARN" "$_AR0X_C_RST"
    printf '   The kernel is the STOCK binary package %s %s from the frozen\n' \
        "$AR0X_KERNEL_FLAVOR" "$AR0X_KERNEL_VERSION"
    printf '   2026/11/01 snapshot. Arch already ships 3 maintainer patches in\n'
    printf '   its 6.18.59-1 packaging tag; ar0x adds ZERO more. No patching,\n'
    printf '   no custom compile, no out-of-tree modules. See\n'
    printf '   config/kernel/README.md for the (expensive) reversal procedure.\n\n'
}

# --- Section 2: asset + contract validation ----------------------------------
validate_assets() {
    section "Validating Phase 4 kernel/boot files"

    local required=(
        "${KERNEL_DIR}/README.md" "${FRAGMENT}"
        "${AR0X_CONFIG_DIR}/mkinitcpio.conf"
        "${AR0X_CONFIG_DIR}/mkinitcpio.d/linux-lts.preset"
        "${AR0X_CONFIG_DIR}/default/grub"
        "${AR0X_CONFIG_DIR}/plymouth/plymouthd.conf"
        "${ASSETS}/grub-theme/ar0x/theme.txt"
        "${ASSETS}/grub-theme/ar0x/background.png"
        "${ASSETS}/plymouth/ar0x/ar0x.plymouth"
        "${ASSETS}/plymouth/ar0x/ar0x.script"
        "${ASSETS}/plymouth/ar0x/logo.png"
        "${ASSETS}/syslinux/splash.png"
        "${PROFILE}/grub/grub.cfg"
        "${PROFILE}/grub/themes/ar0x/theme.txt"
        "${PROFILE}/grub/themes/ar0x/background.png"
        "${PROFILE}/syslinux/syslinux.cfg"
        "${PROFILE}/syslinux/splash.png"
        "${PROFILE}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
        "${PROFILE}/airootfs/etc/mkinitcpio.conf"
        "${PROFILE}/airootfs/etc/mkinitcpio.d/linux-lts.preset"
        "${PROFILE}/airootfs/etc/default/grub"
        "${PROFILE}/airootfs/etc/plymouth/plymouthd.conf"
        "tools/gen-theme-assets.sh" "tools/build-kernel.sh" "docs/KERNEL_BOOT.md"
    )
    local f
    for f in "${required[@]}"; do
        [[ -f "$f" ]] && ok "$(realpath --relative-to="$AR0X_SOURCE_ROOT" "$f" 2>/dev/null || printf '%s' "$f")" \
                      || fail "Missing Phase 4 file: $f"
    done

    # RISK-001: absolutely no patches in v0.1.
    local patch_count
    patch_count="$(find "$PATCHES_DIR" -type f \( -name '*.patch' -o -name '*.diff' \) 2>/dev/null | wc -l)"
    if (( patch_count > 0 )); then
        fail "RISK-001: ${patch_count} kernel patch(es) found in config/kernel/patches/. ar0x v0.1 uses stock LTS."
    else
        ok "RISK-001: zero kernel patches present"
    fi

    # Plymouth hook order: after udev, before modconf/block.
    local live_hooks base_hooks
    live_hooks="$(grep -E '^HOOKS=' "${PROFILE}/airootfs/etc/mkinitcpio.conf.d/archiso.conf")"
    base_hooks="$(grep -E '^HOOKS=' "${AR0X_CONFIG_DIR}/mkinitcpio.conf")"
    [[ "$live_hooks" == *"udev "*"plymouth "* ]] || fail "Live HOOKS: plymouth must come after udev."
    [[ "$live_hooks" == *"plymouth "*"modconf"* ]] || fail "Live HOOKS: plymouth must come before modconf."
    [[ "$base_hooks" == *"udev "*"plymouth "* ]] || fail "Base HOOKS: plymouth must come after udev."
    ok "mkinitcpio plymouth hook order verified (live + installed)"

    # zstd is only safe because CONFIG_RD_ZSTD=y is in the pinned stock kernel.
    grep -Fq 'CONFIG_RD_ZSTD=y' "$FRAGMENT" || fail "zstd initramfs requires CONFIG_RD_ZSTD=y in the audit fragment."
    grep -Fq 'COMPRESSION="zstd"' "${PROFILE}/airootfs/etc/mkinitcpio.conf.d/archiso.conf" || fail "Live COMPRESSION must be zstd."
    ok "CONFIG_RD_ZSTD=y asserted; zstd initramfs enabled"

    # Theme + boot-menu contracts.
    grep -Fq 'desktop-image:' "${ASSETS}/grub-theme/ar0x/theme.txt" || fail "GRUB theme.txt missing desktop-image."
    grep -Fq '+ boot_menu' "${ASSETS}/grub-theme/ar0x/theme.txt" || fail "GRUB theme.txt missing boot_menu."
    grep -Fq 'set theme=' "${PROFILE}/grub/grub.cfg" || fail "GRUB cfg does not load the ar0x theme."
    grep -Fq 'insmod gfxmenu' "${PROFILE}/grub/grub.cfg" || fail "GRUB cfg missing insmod gfxmenu."
    grep -Fq 'ModuleName=script' "${ASSETS}/plymouth/ar0x/ar0x.plymouth" || fail "Plymouth descriptor must use the script plugin."
    grep -Fq 'SetBootProgressFunction' "${ASSETS}/plymouth/ar0x/ar0x.script" || fail "Plymouth script missing SetBootProgressFunction."
    grep -Fq 'UI vesamenu.c32' "${PROFILE}/syslinux/syslinux.cfg" || fail "syslinux needs vesamenu.c32 for MENU BACKGROUND."
    grep -Fq 'MENU BACKGROUND splash.png' "${PROFILE}/syslinux/syslinux.cfg" || fail "syslinux missing MENU BACKGROUND."
    ok "GRUB / Plymouth / syslinux theme contracts verified"

    # profiledef must hand the console to Plymouth, and plymouth must be installed.
    grep -Fq 'quiet splash' "${PROFILE}/profiledef.sh" || fail "profiledef.sh kernel_params_x86_64 missing 'quiet splash'."
    sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/packages.x86_64" \
        | grep -Fxq 'plymouth' || fail "plymouth missing from config/packages.x86_64."
    ok "profiledef quiet splash + plymouth package present"

    # PNG signature/dimensions (pure python, no ImageMagick dependency).
    python3 - "${ASSETS}" "${PROFILE}" <<'PY' || fail "PNG asset validation failed."
import os, struct, sys
assets, profile = sys.argv[1], sys.argv[2]
expected = [
    (os.path.join(assets, "grub-theme/ar0x/background.png"), 1024, 768),
    (os.path.join(assets, "syslinux/splash.png"), 640, 480),
    (os.path.join(assets, "plymouth/ar0x/logo.png"), 320, 80),
    (os.path.join(profile, "grub/themes/ar0x/background.png"), 1024, 768),
    (os.path.join(profile, "syslinux/splash.png"), 640, 480),
]
for i in range(21):
    expected.append((os.path.join(assets, f"plymouth/ar0x/progress-{i}.png"), 400, 6))
for path, w, h in expected:
    with open(path, "rb") as fh:
        head = fh.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"bad PNG: {path}"
    assert struct.unpack(">II", head[16:24]) == (w, h), f"bad size: {path}"
print(f"  PNG assets verified: {len(expected)} files")
PY
}

# --- Section 3: kernel config fragment auditor -------------------------------
# Reads a real kernel config (plain or gzip) into an associative array, then
# asserts every requirement declared in config/kernel/ar0x-lts.config.
audit_fragment() {
    local cfg="$1" label="${2:-$1}"
    section "Auditing kernel config: ${label}"
    [[ -r "$cfg" ]] || { fail "Kernel config not readable: $cfg"; return 1; }

    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f -- '$tmp'" RETURN
    if [[ "$cfg" == *.gz ]]; then
        gzip -cd -- "$cfg" > "$tmp" || { fail "Cannot decompress $cfg"; return 1; }
    else
        cp -- "$cfg" "$tmp"
    fi

    declare -A TARGET=()
    local line sym val
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=(.*)$ ]]; then
            TARGET["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^#[[:space:]]*(CONFIG_[A-Za-z0-9_]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set ]]; then
            TARGET["${BASH_REMATCH[1]}"]="n"
        fi
    done < "$tmp"

    local checked=0 missing=0 bad=0 want got
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^#[[:space:]]*(CONFIG_[A-Za-z0-9_]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set ]]; then
            sym="${BASH_REMATCH[1]}"; want="n"
        elif [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=([ymn])$ ]]; then
            sym="${BASH_REMATCH[1]}"; want="${BASH_REMATCH[2]}"
        else
            continue
        fi
        checked=$((checked + 1))
        got="${TARGET[$sym]:-n}"
        if [[ "$want" == "n" ]]; then
            [[ "$got" == "n" ]] || { warn "${sym}: required unset, found '${got}'"; bad=$((bad + 1)); }
        elif [[ "$want" == "m" ]]; then
            [[ "$got" == "y" || "$got" == "m" ]] || { warn "${sym}: required built-in or module, found '${got}'"; bad=$((bad + 1)); }
        else
            [[ "$got" == "y" ]] || { warn "${sym}: required =y, found '${got}'"; bad=$((bad + 1)); }
        fi
        if [[ "$got" == "n" && ! -v TARGET[$sym] ]]; then missing=$((missing + 1)); fi
    done < "$FRAGMENT"

    if (( bad > 0 )); then
        fail "Kernel audit FAILED: ${bad} of ${checked} required symbols unsatisfied (${missing} absent)."
        return 1
    fi
    ok "Kernel audit PASSED: all ${checked} required CONFIG_* symbols satisfied"
    return 0
}

# --- Section 4: --sync (no root, writes only into the checkout) --------------
sync_profile() {
    section "Syncing Phase 4 configs/assets into the archiso profile"
    install -d -m 0755 \
        "${PROFILE}/airootfs/etc/mkinitcpio.d" \
        "${PROFILE}/airootfs/etc/default" \
        "${PROFILE}/airootfs/etc/plymouth" \
        "${PROFILE}/airootfs/usr/share/plymouth/themes/ar0x" \
        "${PROFILE}/airootfs/usr/share/grub/themes/ar0x" \
        "${PROFILE}/grub/themes/ar0x"

    install -m 0644 -- "${AR0X_CONFIG_DIR}/mkinitcpio.conf" "${PROFILE}/airootfs/etc/mkinitcpio.conf"
    install -m 0644 -- "${AR0X_CONFIG_DIR}/mkinitcpio.d/linux-lts.preset" "${PROFILE}/airootfs/etc/mkinitcpio.d/linux-lts.preset"
    install -m 0644 -- "${AR0X_CONFIG_DIR}/default/grub" "${PROFILE}/airootfs/etc/default/grub"
    install -m 0644 -- "${AR0X_CONFIG_DIR}/plymouth/plymouthd.conf" "${PROFILE}/airootfs/etc/plymouth/plymouthd.conf"

    # `cp -af` (not -f): these are DIRECTORIES, and -f alone refuses them with
    # "cp: -r not specified; omitting directory". -a also preserves the exact
    # bytes so --sync is byte-idempotent.
    cp -af -- "${ASSETS}/plymouth/ar0x/." "${PROFILE}/airootfs/usr/share/plymouth/themes/ar0x/"
    cp -af -- "${ASSETS}/grub-theme/ar0x/." "${PROFILE}/airootfs/usr/share/grub/themes/ar0x/"
    cp -af -- "${ASSETS}/grub-theme/ar0x/." "${PROFILE}/grub/themes/ar0x/"
    cp -f -- "${ASSETS}/syslinux/splash.png" "${PROFILE}/syslinux/splash.png"

    # Do NOT delete .gitkeep from the SOURCE profile: they are tracked skeleton
    # placeholders for later phases. tools/bootstrap.sh strips them only in the
    # disposable STAGED profile, so they never reach the live root filesystem.
    ok "Profile synced: mkinitcpio, GRUB defaults, Plymouth, themes, splash"
    log "NOTE: archiso/profiledef.sh, grub.cfg, syslinux.cfg and packages.x86_64 are canonical — edit them directly."
}

# --- Section 5: --lock-config (network, full frozen .config) -----------------
lock_config() {
    section "Locking the full frozen kernel config"
    install -d -m 0755 "$OUT"
    local src="${AUDIT_FILE:-${OUT}/kernel-config.upstream.x86_64}"
    if [[ -z "${AUDIT_FILE:-}" ]]; then
        require_command curl
        log "GET ${UPSTREAM_CONFIG_URL}"
        curl -fL --retry 2 --max-time 60 -o "$src" "$UPSTREAM_CONFIG_URL" \
            || { fail "Could not download the frozen config.x86_64. Pass a local file: --lock-config /path/to/config"; return 1; }
        grep -Fq 'CONFIG_IKCONFIG' "$src" || { fail "Downloaded file is not a kernel .config"; return 1; }
    fi
    cp -f -- "$src" "$LOCK_FILE"
    ok "Locked full config: ${LOCK_FILE} ($(wc -l < "$LOCK_FILE") lines)"
    audit_fragment "$LOCK_FILE" "kernel-config.lock"
}

# --- Section 6: --rebuild-initramfs (ROOT, MANUAL) ---------------------------
rebuild_initramfs() {
    section "Rebuilding initramfs inside the airootfs chroot"
    require_root
    require_command arch-chroot
    [[ -d "$AIROOTFS" ]] || die "No airootfs at ${AIROOTFS}. Run 'sudo ./tools/bootstrap.sh --iso-only' first."
    if [[ ! -s "${AIROOTFS}/etc/resolv.conf" ]]; then
        cp -L -- /etc/resolv.conf "${AIROOTFS}/etc/resolv.conf"
    fi
    log "arch-chroot ${AIROOTFS} plymouth-set-default-theme -R ar0x"
    arch-chroot "$AIROOTFS" /usr/bin/plymouth-set-default-theme -R ar0x \
        || { warn "plymouth-set-default-theme -R failed; falling back to mkinitcpio -P"; 
             arch-chroot "$AIROOTFS" /usr/bin/mkinitcpio -P; }
    ok "initramfs rebuilt with the ar0x Plymouth theme (log: ${LOG_FILE})"
}

# --- Section 7: --self-test ---------------------------------------------------
self_test() {
    section "Self-test: audit fragment parser"
    local tmp
    tmp="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f -- '$tmp'" RETURN
    # Build a synthetic config that satisfies every declared requirement.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^(CONFIG_[A-Za-z0-9_]+)=([ymn])$ ]]; then
            printf '%s=%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$tmp"
        fi
    done < "$FRAGMENT"
    audit_fragment "$tmp" "synthetic (all requirements met)"
    # Negative test: break one symbol and confirm the auditor catches it.
    sed -i 's/^CONFIG_IKCONFIG=y$/CONFIG_IKCONFIG=n/' "$tmp"
    local before="$AR0X_FAILURES"
    audit_fragment "$tmp" "synthetic (deliberately broken)" >/dev/null 2>&1 || true
    if (( AR0X_FAILURES > before )); then
        ok "Negative test: auditor correctly rejected a broken config"
        AR0X_FAILURES="$before"
    else
        fail "Negative test: auditor FAILED to detect a broken config"
    fi
}

# --- Section 8: dispatch -----------------------------------------------------
cd "$AR0X_SOURCE_ROOT"
warn_risk_001

case "$MODE" in
    check)
        validate_assets
        assert_clean
        ok "Phase 4 --check PASSED (no root, no writes)"
        printf '\nNext steps on a real Arch host:\n'
        printf '  ./tools/build-kernel.sh --sync\n'
        printf '  ./tools/build-kernel.sh --audit-config /boot/config-linux-lts\n'
        printf '  ./tools/build-kernel.sh --lock-config\n'
        printf '  sudo ./tools/build-kernel.sh --rebuild-initramfs\n'
        ;;
    self-test)
        validate_assets
        self_test
        assert_clean
        ok "Phase 4 --self-test PASSED"
        ;;
    sync|all)
        sync_profile
        validate_assets
        assert_clean
        ok "Phase 4 --sync complete"
        ;;
    audit)
        validate_assets
        audit_fragment "$AUDIT_FILE" "$AUDIT_FILE"
        assert_clean
        ok "Phase 4 --audit-config complete"
        ;;
    lock)
        validate_assets
        lock_config
        assert_clean
        ok "Phase 4 --lock-config complete"
        ;;
    rebuild)
        validate_assets
        assert_clean
        rebuild_initramfs
        ;;
esac
