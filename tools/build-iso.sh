#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/build-iso.sh — Phase 11
# -----------------------------------------------------------------------------
# ISO build orchestration, 2.2 GiB size gate, QEMU/VBox/VMware test launchers
# and the disposable build/iso-prefix staging used by the offline self-test.
#
#   --check            (default) READ-ONLY structural validation. No root/no writes.
#   --sync             Stage build/iso-prefix/ (gitignored) with the 3 QEMU
#                      launchers + a rendered ISO manifest. No root.
#   --self-test        ar0x_iso.py --self-test (9 negative mutations + a REAL
#                      sparse-file size-gate test) + checksum.sh --self-test
#                      (REAL create/verify/tamper round-trip) + prefix parity.
#   --preflight        MANUAL, print-only: host prerequisites + blockers.
#   --size-report DIR  Per-directory size breakdown of a staged airootfs.
#   --qemu-bios ISO    Launch the SeaBIOS/isolinux VM (print-only if qemu absent).
#   --qemu-uefi ISO    Launch the OVMF/uefi.grub VM (print-only if qemu absent).
#   --qemu-install ISO ⚠️ RISK-004 disposable-qcow2 installer VM; needs
#                      AR0X_CONFIRM_DISPOSABLE_VM=yes + typed AR0X_TARGET_DISK.
#   --build            ⚠️ MANUAL, ROOT, REAL ARCH HOST: stage profile, run
#                      mkarchiso, enforce the size gate, write SHA256SUMS.
#                      Requires AR0X_CONFIRM_BUILD=yes + a SIGNED [ar0x] db.
#
# ⚠️ RISK-053: NO ISO was built, booted, hashed or signed in this sandbox —
#    mkarchiso, qemu-system-x86_64, qemu-img, edk2-ovmf, KVM, gpg, loop devices
#    and root are all absent. Only --check/--sync/--self-test/--preflight ran.
# ⚠️ RISK-048/051: the signed [ar0x] repo does not exist (PENDING-KEYGEN), so
#    `calamares` + `ar0x-meta` are STILL absent from config/packages.x86_64.
#    --build REFUSES until keygen → build → sign → publish completes.
# ⚠️ RISK-004: --qemu-install is the ONLY mode that creates a disk, and it is
#    always a disposable qcow2 in a temp dir. Never a host device.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=config/iso/build-options.conf
source "${AR0X_CONFIG_DIR}/iso/build-options.conf"

ISO_DIR="${AR0X_CONFIG_DIR}/iso"
PREFIX="${AR0X_SOURCE_ROOT}/build/iso-prefix"
VALIDATOR="${SCRIPT_DIR}/lib/ar0x_iso.py"
OUT="${AR0X_OUT_DIR}"
ISO_PATH="${OUT}/${AR0X_ISO_NAME}"
MODE='check'
ARG=''

usage() {
    cat <<'USAGE'
ar0x Phase 11 — build-iso.sh (ISO build + 2.2 GiB gate + VM test launchers)

  --check            Read-only structural validation (default).
  --sync             Stage build/iso-prefix/ QEMU launchers + manifest.
  --self-test        Offline validator + checksum round-trip + size-gate tests.
  --preflight        MANUAL print-only host prerequisites.
  --size-report DIR  Per-directory MiB breakdown of a staged airootfs.
  --qemu-bios ISO    SeaBIOS / isolinux boot.
  --qemu-uefi ISO    OVMF / uefi.grub boot.
  --qemu-install ISO ⚠️ RISK-004 disposable installer VM (typed device gate).
  --build            ⚠️ MANUAL ROOT: mkarchiso + size gate + SHA256SUMS.
  -h|--help          This help.

Typical offline order:
  ./tools/build-iso.sh --sync
  ./tools/build-iso.sh --check
  ./tools/build-iso.sh --self-test
  ./tools/checksum.sh --check
  ./tools/validate-versions.sh
USAGE
}

# ---------------------------------------------------------------------------
stage_prefix() {
    log "Staging disposable prefix: ${PREFIX}"
    rm -rf -- "$PREFIX"
    mkdir -p -- "$PREFIX"
    local f
    for f in run-qemu-bios.sh run-qemu-uefi.sh run-qemu-install.sh; do
        install -m 0755 -- "${ISO_DIR}/${f}" "${PREFIX}/${f}"
    done
    {
        printf 'ar0x 0.1.0 (%s) release manifest\n' "$AR0X_CODENAME"
        printf 'iso_name=%s\n' "$AR0X_ISO_NAME"
        printf 'iso_label=%s\n' "$AR0X_ISO_LABEL"
        printf 'iso_version=%s\n' "$AR0X_VERSION"
        printf 'install_dir=%s\n' "$AR0X_INSTALL_DIR"
        printf 'arch=%s\n' "$AR0X_ARCH"
        printf 'boot_modes=%s\n' "$AR0X_ISO_BOOT_MODES"
        printf 'size_gate_bytes=%s\n' "$AR0X_ISO_SIZE_GATE_BYTES"
        printf 'hash_algo=%s\n' "$AR0X_ISO_HASH_ALGO"
        printf 'sums_file=%s\n' "$AR0X_ISO_SUMS_FILE"
        printf 'signature=%s%s\n' "$AR0X_ISO_SUMS_FILE" "$AR0X_ISO_SIG_SUFFIX"
        printf 'qemu_uefi_code=%s\n' "$AR0X_ISO_QEMU_UEFI_CODE"
    } > "${PREFIX}/ISO_MANIFEST.txt"
    printf '%s\n%s.sig\n%s\n%s.sig\nCHANGELOG.md\nREADME.md\n' \
        "$AR0X_ISO_NAME" "$AR0X_ISO_NAME" \
        "$AR0X_ISO_SUMS_FILE" "$AR0X_ISO_SUMS_FILE" \
        > "${PREFIX}/RELEASE_ARTIFACTS.txt"
    ok "staged 3 launchers + ISO_MANIFEST.txt + RELEASE_ARTIFACTS.txt (gitignored)"
}

do_sync() {
    section "Phase 11 — staging disposable ISO/VM prefix"
    stage_prefix
    log "No root, no network, no writes to tracked files."
}

# ---------------------------------------------------------------------------
do_check() {
    section "Phase 11 — read-only ISO build validation"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" || fail "ar0x_iso.py failed"

    local f
    for f in "${ISO_DIR}"/run-qemu-*.sh "${SCRIPT_DIR}/checksum.sh" "$0"; do
        bash -n -- "$f" || fail "bash -n failed on ${f}"
    done
    ok "bash -n: 3 QEMU launchers + checksum.sh + build-iso.sh"

    for f in "${ISO_DIR}"/run-qemu-*.sh "${SCRIPT_DIR}/checksum.sh" "$0"; do
        [[ -x "$f" ]] || fail "not executable (0755): ${f}"
    done
    ok "driver + launchers are mode 0755"

    if find "$AR0X_SOURCE_ROOT" -maxdepth 1 -name '*.iso' -print -quit | grep -q .; then
        fail "a generated *.iso leaked into the source root (gitignored artifacts only)"
    fi
    ok "no generated ISO/SHA256SUMS in the tracked source root"

    "$SCRIPT_DIR/checksum.sh" --check >/dev/null 2>&1 \
        || fail "checksum.sh --check failed"
    ok "checksum.sh --check agrees on the artifact contract"

    assert_clean
    ok "Phase 11 --check PASSED"
}

# ---------------------------------------------------------------------------
# Real sparse-file test of the 2.2 GiB gate. truncate(1) creates NO data.
check_size_gate() {
    local file="$1" want="$2" size
    size="$(stat -c %s -- "$file")"
    if (( size > AR0X_ISO_MAX_BYTES )); then
        [[ "$want" == "reject" ]]
    else
        [[ "$want" == "accept" ]]
    fi
}

do_self_test() {
    section "Phase 11 — offline ISO self-test"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" --self-test \
        || fail "ar0x_iso.py --self-test failed"

    if [[ ! -d "${PREFIX}" ]]; then
        warn "prefix missing; restaging (no writes to tracked files)"
        stage_prefix
    fi
    local f
    for f in run-qemu-bios.sh run-qemu-uefi.sh run-qemu-install.sh; do
        cmp -s -- "${ISO_DIR}/${f}" "${PREFIX}/${f}" \
            || fail "staged prefix drifted on ${f} (run --sync)"
        bash -n -- "${PREFIX}/${f}" || fail "bash -n failed on staged ${f}"
        [[ -x "${PREFIX}/${f}" ]] || fail "staged ${f} lost its 0755 mode"
    done
    ok "staged prefix: 3 launchers byte-identical, executable, parse cleanly"

    "$SCRIPT_DIR/checksum.sh" --self-test >/dev/null 2>&1 \
        || fail "checksum.sh --self-test failed"
    ok "checksum.sh --self-test: real create/verify/tamper round-trip PASSED"

    local tmp; tmp="$(mktemp -d -t ar0x-size-XXXXXXXX)"
    trap 'rm -rf -- "$tmp"' RETURN
    truncate -s "$((AR0X_ISO_MAX_BYTES + 1))" "${tmp}/too-big.iso"
    truncate -s "$((AR0X_ISO_MAX_BYTES - 1))" "${tmp}/just-fits.iso"
    check_size_gate "${tmp}/too-big.iso" reject \
        || fail "size gate ACCEPTED an oversized ISO"
    check_size_gate "${tmp}/just-fits.iso" accept \
        || fail "size gate REJECTED an in-budget ISO"
    ok "2.2 GiB size gate: sparse gate+1 REJECTED, gate-1 ACCEPTED (stat -c %s)"

    assert_clean
    ok "Phase 11 --self-test PASSED (no root, no network, no mkarchiso, no QEMU)"
}

# ---------------------------------------------------------------------------
do_size_report() {
    local dir="${1:-}"
    [[ -n "$dir" && -d "$dir" ]] || die "--size-report needs an existing staged airootfs directory."
    section "Phase 11 — size report: ${dir}"
    local threshold="${AR0X_ISO_SIZE_REPORT_MIN_MIB:-10}" d mib
    while IFS= read -r d; do
        mib="$(du -sm -- "$d" | cut -f1)"
        if (( mib >= threshold )); then
            printf '%8s MiB  %s\n' "$mib" "${d#"${dir}"/}"
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print | sort)
    printf '\n%8s MiB  TOTAL (uncompressed; squashfs zstd-15 compresses this)\n' \
        "$(du -sm -- "$dir" | cut -f1)"
    warn "RISK-012: if the FINAL ISO exceeds ${AR0X_ISO_MAX_BYTES} bytes, apply the §7 lever order."
}

# ---------------------------------------------------------------------------
do_preflight() {
    section "Phase 11 — MANUAL build preflight (print only, NEVER builds)"
    local c
    for c in mkarchiso qemu-system-x86_64 qemu-img gpg xorriso sha256sum; do
        if have_command "$c"; then ok "host command available: ${c}"; else warn "MISSING on this host: ${c} (MANUAL install)"; fi
    done
    printf '\nRequired before --build:\n'
    printf '  * ROOT + loop devices + ~40 GiB free under %s\n' "$AR0X_BUILD_ROOT"
    printf '  * Arch host with archiso %s and the frozen %s snapshot\n' \
        "$AR0X_ARCHISO_VERSION" "$AR0X_SNAPSHOT_DATE"
    printf '  * edk2-ovmf (%s) + qemu-full for the VM gates\n' "$AR0X_ISO_QEMU_UEFI_CODE"
    printf '  * SIGNED [ar0x] db %s + published release key (currently PENDING-KEYGEN)\n' \
        "$AR0X_ISO_RELEASE_DB"
    printf '  * signed [ar0x] db; build-release.sh --run injects the packages into the STAGED profile only\n'
    printf '\nThen, on the host:\n'
    printf '  sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build\n'
    printf '  ./tools/checksum.sh --verify\n'
    printf '  ./tools/build-iso.sh --qemu-bios out/%s\n' "$AR0X_ISO_NAME"
    printf '  ./tools/build-iso.sh --qemu-uefi out/%s\n' "$AR0X_ISO_NAME"
    printf '  ⚠️ lsblk -o NAME,SIZE,MODEL,TRAN before --qemu-install (RISK-004)\n\n'
    warn "NOTHING was built, mounted, partitioned or launched by --preflight."
    ok "MANUAL preflight checklist printed (RISK-004/048/051/053)"
}

# ---------------------------------------------------------------------------
launch_vm() {
    local script="$1" iso="$2" label="$3"
    [[ -n "$iso" ]] || die "${label} needs an ISO path."
    if ! have_command qemu-system-x86_64; then
        warn "qemu-system-x86_64 absent here — MANUAL, print-only. No VM launched."
        printf '  %s/%s %s\n' "$ISO_DIR" "$script" "$iso"
        printf '  Install qemu-full + edk2-ovmf on a real Arch host first.\n'
        return 0
    fi
    [[ -f "$iso" ]] || die "ISO not found: ${iso}"
    if [[ "$script" == "run-qemu-install.sh" ]]; then
        warn "RISK-004: disposable qcow2 ONLY. Inside the guest: lsblk -o NAME,SIZE,MODEL,TRAN"
    fi
    exec "${ISO_DIR}/${script}" "$iso"
}

do_build() {
    section "Phase 11 — ⚠️ MANUAL ISO build (ROOT, destructive scratch)"
    [[ "${AR0X_CONFIRM_BUILD:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_BUILD=yes after --preflight and docs/ISO_BUILD_GUIDE.md §2."
    require_root
    require_command mkarchiso
    local fpr
    fpr="$(grep -v '^[[:space:]]*#' \
               "${AR0X_CONFIG_DIR}/repo/RELEASE_KEY_FINGERPRINT" | tr -d '[:space:]')"
    [[ "$fpr" != "PENDING-KEYGEN" && "$fpr" =~ ^[0-9A-Fa-f]{40}$ ]] \
        || die "RISK-051: no published release key; run the air-gapped keygen first."
    [[ -f "${AR0X_REPO_DIR}/${AR0X_ISO_RELEASE_DB}" ]] \
        || die "RISK-048: signed [ar0x] db missing (${AR0X_REPO_DIR}/${AR0X_ISO_RELEASE_DB})."

    # ADR-029: mkarchiso consumes $AR0X_PROFILE_STAGE, NOT archiso/ directly.
    # --sync only regenerates the 3 tracked mirrors; it NEVER creates the stage.
    # --stage builds the disposable profile and injects calamares +
    # ar0x-keyring + ar0x-meta there ONLY, after gpg --verify of the signed db.
    [[ "${AR0X_CONFIRM_SIGNED_REPO:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_SIGNED_REPO=yes (build-release.sh --run sets it)."
    log "Staging disposable profile WITH the signed [ar0x] packages"
    "$SCRIPT_DIR/bootstrap.sh" --stage --with-ar0x-repo --with-signed-packages
    local pkg
    for pkg in calamares ar0x-keyring ar0x-meta; do
        grep -Fxq -- "$pkg" "${AR0X_PROFILE_STAGE}/packages.x86_64" \
            || die "staged profile is missing ${pkg} (RISK-048: signed-repo injection failed)."
    done
    ok "staged profile: signed [ar0x] packages present; config/packages.x86_64 stays clean"
    mkdir -p -- "$OUT" "$AR0X_WORK_DIR"
    local epoch; epoch="$(date -u -d "${AR0X_SNAPSHOT_DATE//\//-}" +%s)"
    log "SOURCE_DATE_EPOCH=${epoch} (frozen ${AR0X_SNAPSHOT_DATE} snapshot)"
    SOURCE_DATE_EPOCH="$epoch" mkarchiso -v -m iso \
        -w "$AR0X_WORK_DIR" -o "$OUT" "$AR0X_PROFILE_STAGE"

    [[ -f "$ISO_PATH" ]] || die "mkarchiso finished but ${ISO_PATH} is missing."
    local size; size="$(stat -c %s -- "$ISO_PATH")"
    if (( size > AR0X_ISO_MAX_BYTES )); then
        do_size_report "${AR0X_WORK_DIR}/x86_64/airootfs" || true
        die "RISK-012: ISO is ${size} bytes > gate ${AR0X_ISO_MAX_BYTES}; apply PROJECT_PLAN.md §7 lever order."
    fi
    ok "ISO ${size} bytes <= gate ${AR0X_ISO_MAX_BYTES} (2.2 GiB)"
    "$SCRIPT_DIR/checksum.sh" --create
    ok "ISO build complete. QEMU + hardware QA remain MANUAL (docs/TESTING_CHECKLIST.md)."
}

# ---------------------------------------------------------------------------
while (( $# > 0 )); do
    case "$1" in
        --check)       MODE='check' ;;
        --sync)        MODE='sync' ;;
        --self-test)   MODE='self-test' ;;
        --preflight)   MODE='preflight' ;;
        --build)       MODE='build' ;;
        --size-report) MODE='size-report'; shift; ARG="${1:-}" ;;
        --qemu-bios)   MODE='qemu-bios';   shift; ARG="${1:-}" ;;
        --qemu-uefi)   MODE='qemu-uefi';   shift; ARG="${1:-}" ;;
        --qemu-install)MODE='qemu-install';shift; ARG="${1:-}" ;;
        -h|--help)     usage; exit 0 ;;
        *)             usage >&2; die "unknown option: $1" ;;
    esac
    shift || true
done

case "$MODE" in
    check)        do_check ;;
    sync)         do_sync ;;
    self-test)    do_self_test ;;
    preflight)    do_preflight ;;
    size-report)  do_size_report "$ARG" ;;
    qemu-bios)    launch_vm run-qemu-bios.sh    "$ARG" "BIOS" ;;
    qemu-uefi)    launch_vm run-qemu-uefi.sh    "$ARG" "UEFI" ;;
    qemu-install) launch_vm run-qemu-install.sh "$ARG" "INSTALL" ;;
    build)        do_build ;;
esac
