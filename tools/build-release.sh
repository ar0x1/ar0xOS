#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/build-release.sh — post-plan completion driver
# -----------------------------------------------------------------------------
# ONE ENTRY POINT for turning the source-complete tree into a REAL ar0x ISO on
# a real Arch build host. It closes the automatable MANUAL gates of
# docs/RELEASE_GUIDE.md §2 and PHASE 11/12: profile staging, signed-repo
# package injection, mkarchiso, the 2.2 GiB gate, SHA256SUMS, detached GPG
# signatures, and fresh verification.
#
#   --plan        Print the exact ordered command chain. Read-only, offline.
#   --preflight   Check host capabilities, key/repo state, disk space. Read-only.
#   --run         ⚠️ REAL BUILD: root + Arch toolchain + published 40-hex FPR +
#                 signed [ar0x] db + gpg secret key + explicit confirmations.
#   --self-test   Offline: validator negative tests + a REAL disposable
#                 bootstrap.sh --stage in a temp build root + refusal gates.
#   --check       Read-only structural validation (default, offline).
#
# ⚠️ THIS DRIVER NEVER tags, NEVER uploads and NEVER announces. Publication is
#    docs/RELEASE_GUIDE.md §4 (MANUAL). It NEVER creates an ISO in the Arena
#    sandbox: mkarchiso/pacman/gpg/root/Arch mirrors are all absent here
#    (RISK-053/054). It FAILS CLOSED rather than fabricating an ISO.
# ⚠️ RISK-004: no disk is ever partitioned here; QEMU QA stays MANUAL.
# ⚠️ ADR-029: calamares + ar0x-keyring + ar0x-meta are injected into the
#    DISPOSABLE staged profile ONLY, never into tracked config/packages.x86_64.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

VALIDATOR="${SCRIPT_DIR}/lib/ar0x_build_release.py"
DB="${AR0X_REPO_DIR}/${AR0X_REPO_DB}"
MODE='check'

usage() {
    cat <<'USAGE'
ar0x — build-release.sh (post-plan ISO completion driver)

  --check       Read-only structural validation (default, offline).
  --plan        Print the exact ordered real-host command chain (read-only).
  --preflight   Check host capabilities + key/repo state (read-only).
  --run         ⚠️ REAL ISO build on a real Arch host (root + signed repo).
  --self-test   Offline self-test (negative gates + REAL disposable --stage).
  -h|--help     This help.

  Required for --run:
    AR0X_CONFIRM_RELEASE_CHAIN=yes   AR0X_CONFIRM_SIGNED_REPO=yes
    AR0X_CONFIRM_BUILD=yes           AR0X_CONFIRM_SIGN=yes
    root, mkarchiso/pacman/gpg/repo-add/xorriso/mksquashfs/sha256sum,
    a published 40-hex release FPR, the signed [ar0x] db + .sig,
    and the offline private key in AR0X_KEYS_DIR/gnupg (auto-used as GNUPGHOME).

  This driver NEVER tags, NEVER uploads and NEVER announces (RISK-054).
  See docs/BUILD_RELEASE_ISO.md for Docker / Vagrant / native Arch recipes.
USAGE
}

fpr_value() {
    grep -v '^[[:space:]]*#' "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT" \
        | tr -d '[:space:]'
}

# Emit a status line without aborting (used by --preflight / --plan).
gate_state() {
    local label="$1" ok="$2" note="$3"
    if [[ "$ok" == "yes" ]]; then ok "${label}: READY — ${note}"
    else warn "${label}: MISSING — ${note}"; fi
}

do_plan() {
    section "Real-host ISO build chain (PRINT ONLY — nothing is executed)"
    printf '  0. MANUAL (air-gapped, NON-ROOT): AR0X_CONFIRM_KEYGEN=yes ./tools/setup-repo.sh --keygen\n'
    printf '     commit the 40-hex FPR, publish it OUT OF BAND, then --sync/--build/--sign/--verify\n'
    printf '  1. ./tools/validate-versions.sh\n'
    printf '  2. ./tools/setup-repo.sh --verify "$AR0X_REPO_DIR"\n'
    printf '  3. ./tools/bootstrap.sh --sync\n'
    printf '  4. AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build\n'
    printf '       -> bootstrap.sh --stage --with-ar0x-repo --with-signed-packages (ADR-029)\n'
    printf '       -> mkarchiso -m iso, stat -c %%s <= 2362232012 bytes, SHA256SUMS\n'
    printf '  5. AR0X_CONFIRM_SIGN=yes ./tools/checksum.sh --sign\n'
    printf '  6. ./tools/checksum.sh --verify   (sha256sum -c + gpg --verify)\n'
    printf '  7. ./tools/prepare-release.sh --check ; QEMU BIOS/UEFI + 40/40 checklist\n'
    printf '  8. MANUAL: docs/RELEASE_GUIDE.md §4 publication (this driver NEVER uploads)\n'
    warn "Steps 0 and 8 are human. Steps 1-7 are automated by --run on a real Arch host."
    ok "plan printed (RISK-053/054: nothing built here)"
}

do_preflight() {
    section "Real-host preflight (READ-ONLY — nothing is built)"
    local fpr; fpr="$(fpr_value)"
    if [[ "$fpr" == "PENDING-KEYGEN" ]]; then
        warn "release key: PENDING-KEYGEN — --run will REFUSE (RISK-051)."
    elif [[ "$fpr" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        ok "release key: published 40-hex FPR ${fpr:0:8}…"
    else
        warn "release key: INVALID fingerprint '${fpr}'."
    fi
    gate_state "signed [ar0x] db" "$([[ -f "$DB" && -f "${DB}.sig" ]] && echo yes || echo no)" "$DB (+ .sig)"
    local root_state="no"; (( EUID == 0 )) && root_state="yes"
    gate_state "root" "$root_state" "mkarchiso needs mount/mknod/chroot"
    local c
    for c in mkarchiso pacman pacstrap repo-add gpg xorriso mksquashfs sha256sum; do
        gate_state "host command $c" "$(have_command "$c" && echo yes || echo no)" "Arch build toolchain"
    done
    if have_command df; then
        df -h -- "${AR0X_BUILD_ROOT}/.." 2>/dev/null | tail -1 || true
    fi
    warn "~40 GiB free under ${AR0X_BUILD_ROOT} is required by mkarchiso."
    warn "⚠️ This sandbox has NO root, NO Arch toolchain and NO Arch mirror access."
    ok "preflight printed; --run will fail closed here (RISK-053)"
}

require_real_build() {
    section "Hard gates before a REAL ISO build"
    # The offline master key lives in AR0X_KEYS_DIR/gnupg, NOT in root's
    # ~/.gnupg. Export it BEFORE any gpg call (db verification, secret-key
    # lookup) and let child scripts (checksum.sh --sign) inherit it.
    export GNUPGHOME="${GNUPGHOME:-${AR0X_KEYS_DIR}/gnupg}"
    [[ "${AR0X_CONFIRM_RELEASE_CHAIN:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_RELEASE_CHAIN=yes after reading docs/BUILD_RELEASE_ISO.md."
    [[ "${AR0X_CONFIRM_SIGNED_REPO:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_SIGNED_REPO=yes (RISK-048/051)."
    [[ "${AR0X_CONFIRM_BUILD:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_BUILD=yes (build-iso.sh gate)."
    [[ "${AR0X_CONFIRM_SIGN:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_SIGN=yes (checksum.sh gate)."
    require_root
    local c
    for c in mkarchiso pacman pacstrap repo-add gpg xorriso mksquashfs sha256sum; do
        require_command "$c"
    done
    local fpr; fpr="$(fpr_value)"
    [[ "$fpr" != "PENDING-KEYGEN" && "$fpr" =~ ^[0-9A-Fa-f]{40}$ ]] \
        || die "RISK-051: published 40-hex FPR required (found '${fpr}')."
    [[ -f "$DB" && -f "${DB}.sig" ]] \
        || die "RISK-048: signed [ar0x] db + .sig missing at ${DB}."
    gpg --verify "${DB}.sig" "$DB" >/dev/null 2>&1 \
        || die "RISK-048: gpg --verify FAILED on ${DB}.sig — refusing to build."
    gpg --list-secret-keys "$fpr" >/dev/null 2>&1 \
        || die "RISK-051: offline private key for ${fpr} is not available."
    ok "hard gates PASSED: root, Arch toolchain, published FPR, signed db, secret key"
}

do_run() {
    section "REAL ar0x ISO build — this writes ONLY into ${AR0X_BUILD_ROOT}"
    require_real_build

    log "1/7 validate-versions.sh"
    "${SCRIPT_DIR}/validate-versions.sh"

    log "2/7 verify the signed [ar0x] repository"
    "${SCRIPT_DIR}/setup-repo.sh" --verify "${AR0X_REPO_DIR}"

    log "3/7 sync the 3 generated archiso mirrors"
    "${SCRIPT_DIR}/bootstrap.sh" --sync

    log "4/7 stage disposable profile + mkarchiso + 2.2 GiB gate + SHA256SUMS"
    "${SCRIPT_DIR}/build-iso.sh" --build

    log "5/7 detached GPG signatures"
    "${SCRIPT_DIR}/checksum.sh" --sign

    log "6/7 sha256sum -c + gpg --verify"
    "${SCRIPT_DIR}/checksum.sh" --verify

    log "7/7 release contract check"
    "${SCRIPT_DIR}/prepare-release.sh" --check

    local size; size="$(stat -c %s -- "${AR0X_OUT_DIR}/${AR0X_ISO_NAME}")"
    section "ISO BUILT: ${AR0X_OUT_DIR}/${AR0X_ISO_NAME} (${size} bytes)"
    ok "6 release artifacts are in ${AR0X_OUT_DIR}"
    warn "MANUAL QA STILL REQUIRED: docs/TESTING_CHECKLIST.md 40/40 (100%),"
    warn "  QEMU BIOS + UEFI boots, disposable-qcow2 install → reboot → ar0x-welcome,"
    warn "  real-hardware WiFi/BT/audio/GPU, fresh-download verification."
    warn "PUBLICATION IS MANUAL: this driver NEVER tags, NEVER uploads, NEVER announces."
    ok "build chain complete (RISK-004/052/053/054: runtime + publication still human)"
}

# ---------------------------------------------------------------------------
do_check() {
    section "Read-only build-release validation (offline)"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" || fail "ar0x_build_release.py failed"
    bash -n -- "$0" || fail "bash -n failed on build-release.sh"
    [[ -x "$0" ]] || fail "build-release.sh must be mode 0755"
    ok "bash -n + 0755 mode + structural validator PASSED"
    assert_clean
    ok "--check PASSED (no writes)"
}

# ---------------------------------------------------------------------------
do_self_test() {
    section "Offline build-release self-test"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" --self-test \
        || fail "ar0x_build_release.py --self-test failed"

    # --plan must stay read-only and name every real step.
    local plan; plan="$("$0" --plan)"
    for needle in "setup-repo.sh --verify" "bootstrap.sh --sync" "build-iso.sh --build" \
                  "checksum.sh --sign" "checksum.sh --verify" "2362232012"; do
        [[ "$plan" == *"$needle"* ]] || fail "--plan lost a real build step: ${needle}"
    done
    ok "--plan: all 5 real build steps + size gate present"

    # --run MUST fail closed in this sandbox (no confirmations / no key).
    if AR0X_CONFIRM_RELEASE_CHAIN=no "$0" --run >/dev/null 2>&1; then
        fail "--run succeeded WITHOUT AR0X_CONFIRM_RELEASE_CHAIN=yes"
    else
        ok "--run REFUSES without explicit confirmation"
    fi
    if AR0X_CONFIRM_RELEASE_CHAIN=yes AR0X_CONFIRM_SIGNED_REPO=yes \
       AR0X_CONFIRM_BUILD=yes AR0X_CONFIRM_SIGN=yes \
       "$0" --run >/dev/null 2>&1; then
        fail "--run succeeded with PENDING-KEYGEN / no root / no mkarchiso"
    else
        ok "--run fails closed here (PENDING-KEYGEN, no root, no Arch toolchain)"
    fi

    # --- REAL disposable staging test (no root, no Arch tools) -------------
    local tmp; tmp="$(mktemp -d -t ar0x-build-release-XXXXXXXX)"
    trap 'rm -rf -- "$tmp"' RETURN
    local src="${tmp}/src" br="${tmp}/build" repo="${tmp}/repo/x86_64" bin="${tmp}/bin"
    mkdir -p -- "$src" "$br" "$repo" "$bin"
    # common.sh EXPORTS default /opt/ar0x-build paths; override EVERY one so
    # the offline staging test writes ONLY into $tmp (never the host build root).
    local -a E=(
        AR0X_SOURCE_ROOT="$src" AR0X_BUILD_ROOT="$br"
        AR0X_PROFILE_STAGE="${br}/profile" AR0X_PROFILE="${src}/archiso"
        AR0X_WORK_DIR="${br}/work" AR0X_OUT_DIR="${br}/out"
        AR0X_LOG_DIR="${br}/logs" AR0X_REPO_DIR="$repo"
        AR0X_KEYS_DIR="${br}/keys" AR0X_CHROOT_DIR="${br}/chroot"
        AR0X_PKG_CACHE="${br}/cache" AR0X_SRC_DIR="${br}/src"
    )
    ( cd -- "$AR0X_SOURCE_ROOT" && tar -cf - --exclude='./.git' --exclude='./build' . ) \
        | ( cd -- "$src" && tar -xf - )
    printf '%s\n' 'A1B2C3D4E5F60718293A4B5C6D7E8F9012345678' \
        > "${src}/config/repo/RELEASE_KEY_FINGERPRINT"
    printf 'fake db for offline staging test\n'   > "${repo}/${AR0X_REPO_DB}"
    printf 'fake db signature\n'                  > "${repo}/${AR0X_REPO_DB}.sig"
    # Stub gpg ONLY for the offline plumbing test. --run uses the real gpg.
    cat > "${bin}/gpg" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "--verify" ]] && exit 0
exit 1
STUB
    chmod 0755 "${bin}/gpg"

    # (a) plain stage: staged profile must NOT contain ar0x-*/calamares.
    env "${E[@]}" "${SCRIPT_DIR}/bootstrap.sh" --stage --with-ar0x-repo \
        > "${tmp}/stage-plain.log" 2>&1 \
        || { tail -12 "${tmp}/stage-plain.log" >&2; fail "REAL --stage failed"; }
    [[ -f "${br}/profile/packages.x86_64" && -f "${br}/profile/pacman.conf" ]] \
        || fail "REAL --stage did not produce a mkarchiso profile"
    grep -q '^\[ar0x\]$' "${br}/profile/pacman.conf" \
        || fail "REAL --stage dropped the [ar0x] repo block"
    ! grep -Eq '^(calamares|ar0x-[a-z]+)$' "${br}/profile/packages.x86_64" \
        || fail "plain --stage leaked signed packages (RISK-048)"
    ok "REAL --stage: mkarchiso profile built, [ar0x] block kept, source gate intact"

    # (b) signed-package injection: staged ONLY, tracked sources stay clean.
    env PATH="${bin}:${PATH}" "${E[@]}" AR0X_CONFIRM_SIGNED_REPO=yes \
        "${SCRIPT_DIR}/bootstrap.sh" --stage --with-ar0x-repo --with-signed-packages \
        > "${tmp}/stage-inject.log" 2>&1 \
        || { tail -12 "${tmp}/stage-inject.log" >&2; fail "REAL --stage --with-signed-packages failed"; }
    local pkg
    for pkg in calamares ar0x-keyring ar0x-meta; do
        grep -Fxq -- "$pkg" "${br}/profile/packages.x86_64" \
            || fail "staged profile missing injected ${pkg}"
    done
    ! grep -Eq '^(calamares|ar0x-[a-z]+)$' "${src}/config/packages.x86_64" \
        || fail "ADR-029 violated: tracked config/packages.x86_64 was modified"
    ! grep -Eq '^(calamares|ar0x-[a-z]+)$' "${src}/archiso/packages.x86_64" \
        || fail "ADR-029 violated: tracked archiso/packages.x86_64 was modified"
    ok "REAL injection: 3 signed packages in STAGE only; tracked sources clean"

    # (c) negative gate: PENDING-KEYGEN must REFUSE injection.
    printf 'PENDING-KEYGEN\n' > "${src}/config/repo/RELEASE_KEY_FINGERPRINT"
    if env PATH="${bin}:${PATH}" "${E[@]}" AR0X_CONFIRM_SIGNED_REPO=yes \
        "${SCRIPT_DIR}/bootstrap.sh" --stage --with-ar0x-repo --with-signed-packages \
        >/dev/null 2>&1; then
        fail "injection ACCEPTED PENDING-KEYGEN (RISK-051)"
    else
        ok "injection REFUSES PENDING-KEYGEN (RISK-051)"
    fi

    assert_clean
    ok "--self-test PASSED: no root, no network, no mkarchiso, NO ISO produced"
}

# ---------------------------------------------------------------------------
while (( $# > 0 )); do
    case "$1" in
        --check)      MODE='check' ;;
        --plan)       MODE='plan' ;;
        --preflight)  MODE='preflight' ;;
        --run)        MODE='run' ;;
        --self-test)  MODE='self-test' ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

case "$MODE" in
    check)      do_check ;;
    plan)       do_plan ;;
    preflight)  do_preflight ;;
    run)        do_run ;;
    self-test)  do_self_test ;;
esac
