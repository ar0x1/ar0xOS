#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/checksum.sh — Phase 11
# -----------------------------------------------------------------------------
# Release-artifact integrity: SHA256SUMS + detached GPG signatures.
#
#   --check      (default) READ-ONLY structural validation. No root, no writes.
#   --create     Write SHA256SUMS for the release artifact set in AR0X_OUT_DIR.
#   --verify     `sha256sum -c` + `gpg --verify SHA256SUMS.sig SHA256SUMS`
#                (GPG step is a MANUAL warning when gpg/signature are absent).
#   --sign       ⚠️ MANUAL: detached .sig for SHA256SUMS and the ISO. Requires
#                AR0X_CONFIRM_SIGN=yes, gpg, and a real 40-hex release FPR.
#   --self-test  REAL offline round-trip in a temp dir: create -> verify ->
#                tamper -> verify MUST fail -> restore -> verify. No root.
#
# Artifacts live in AR0X_OUT_DIR (default /opt/ar0x-build/out), NEVER in Git:
# SHA256SUMS / SHA256SUMS.sig / *.iso.sig are gitignored (see .gitignore).
#
# ⚠️ RISK-051/048: the offline release key is PENDING-KEYGEN, so --sign MUST
#    refuse. No signature and no signed [ar0x] db exist in this sandbox.
# ⚠️ RISK-053: no real ISO was built, hashed, signed or booted here.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=config/iso/build-options.conf
source "${AR0X_CONFIG_DIR}/iso/build-options.conf"

OUT="${AR0X_OUT_DIR}"
SUMS="${AR0X_ISO_SUMS_FILE}"
SIG="${SUMS}${AR0X_ISO_SIG_SUFFIX}"
ISO="${AR0X_ISO_NAME}"
MODE='check'

usage() {
    cat <<'USAGE'
ar0x Phase 11 — checksum.sh (SHA256SUMS + detached GPG signatures)

  --check      Read-only structural validation (default). No root, no writes.
  --create     Regenerate SHA256SUMS in AR0X_OUT_DIR.
  --verify     Verify SHA256SUMS (+ signature when present).
  --sign       MANUAL, needs gpg + AR0X_CONFIRM_SIGN=yes + real release FPR.
  --self-test  Real create/verify/tamper/verify round-trip in a temp dir.
  -h|--help    This help.

Override AR0X_OUT_DIR to work on a disposable directory (used by --self-test).
USAGE
}

# The release artifact set from PROJECT_PLAN.md §11. Only the ISO is mandatory;
# optional text artifacts are included when present in AR0X_OUT_DIR.
artifacts() {
    local list=("$ISO") f
    for f in CHANGELOG.md packages.lock README.md; do
        [[ -f "${OUT}/${f}" ]] && list+=("$f")
    done
    printf '%s\n' "${list[@]}"
}

release_fpr() {
    local fpr=''
    if [[ -r "${AR0X_CONFIG_DIR}/repo/RELEASE_KEY_FINGERPRINT" ]]; then
        fpr="$(grep -v '^[[:space:]]*#' \
                   "${AR0X_CONFIG_DIR}/repo/RELEASE_KEY_FINGERPRINT" | tr -d '[:space:]')"
    fi
    printf '%s' "${fpr:-PENDING-KEYGEN}"
}

do_check() {
    section "Phase 11 — checksum tool validation (read-only)"
    bash -n -- "$0" || fail "bash -n failed on checksum.sh"
    ok "bash -n: checksum.sh"
    [[ "${AR0X_ISO_HASH_ALGO}" == "sha256" ]] \
        || fail "hash algorithm must be sha256, got ${AR0X_ISO_HASH_ALGO}."
    [[ "${AR0X_ISO_SUMS_FILE}" == "SHA256SUMS" ]] \
        || fail "sums file must be SHA256SUMS."
    [[ "${AR0X_ISO_SIG_SUFFIX}" == ".sig" ]] \
        || fail "signature suffix must be .sig."
    have_command sha256sum || fail "sha256sum is required."
    ok "artifact contract: SHA256SUMS + .sig, sha256 only, sha256sum available"
    local fpr; fpr="$(release_fpr)"
    if [[ "$fpr" == "PENDING-KEYGEN" ]]; then
        warn "RISK-051: release key is PENDING-KEYGEN — --sign will REFUSE (MANUAL keygen)."
    else
        ok "release fingerprint present (${fpr:0:8}…)"
    fi
    if ! have_command gpg; then
        warn "gpg absent here — detached signatures are a MANUAL Phase 11 gate (RISK-048/051)."
    fi
    [[ ! -e "${AR0X_SOURCE_ROOT}/SHA256SUMS" && ! -e "${AR0X_SOURCE_ROOT}/SHA256SUMS.sig" ]] \
        || fail "derived SHA256SUMS artifacts leaked into the Git checkout."
    assert_clean
    ok "Phase 11 --check PASSED (no writes)"
}

do_create() {
    section "Phase 11 — generating SHA256SUMS"
    [[ -f "${OUT}/${ISO}" ]] || die "ISO not found: ${OUT}/${ISO} (build it first: tools/build-iso.sh --build)."
    mkdir -p -- "$OUT"
    local -a files; mapfile -t files < <(artifacts)
    ( cd -- "$OUT" && LC_ALL=C sha256sum -- "${files[@]}" > "$SUMS" )
    ok "wrote ${OUT}/${SUMS} (${#files[@]} artifact(s))"
    ( cd -- "$OUT" && sha256sum -c "$SUMS" ) || die "SHA256SUMS self-check failed."
    ok "sha256sum -c self-check PASSED"
}

do_verify() {
    section "Phase 11 — verifying release artifacts"
    [[ -f "${OUT}/${SUMS}" ]] || die "missing ${OUT}/${SUMS} (run --create)."
    ( cd -- "$OUT" && LC_ALL=C sha256sum -c "$SUMS" ) \
        || die "SHA256 verification FAILED — DO NOT PUBLISH THIS ISO."
    ok "sha256sum -c SHA256SUMS PASSED"
    if [[ -f "${OUT}/${SIG}" ]]; then
        if have_command gpg; then
            gpg --verify "${OUT}/${SIG}" "${OUT}/${SUMS}" \
                || die "GPG signature verification FAILED — DO NOT PUBLISH."
            ok "gpg --verify SHA256SUMS.sig SHA256SUMS PASSED"
        else
            warn "gpg absent here — signature verification is a MANUAL Phase 11 gate."
        fi
    else
        warn "${SIG} absent — MANUAL --sign required before release (RISK-051)."
    fi
}

do_sign() {
    section "Phase 11 — MANUAL detached signatures"
    [[ "${AR0X_CONFIRM_SIGN:-no}" == "yes" ]] \
        || die "Set AR0X_CONFIRM_SIGN=yes after reading docs/REPO_GUIDE.md §3."
    # Fingerprint gate FIRST: PENDING-KEYGEN must be the reason --sign refuses,
    # not merely "gpg is missing" on this sandbox.
    local fpr; fpr="$(release_fpr)"
    [[ "$fpr" != "PENDING-KEYGEN" && "$fpr" =~ ^[0-9A-Fa-f]{40}$ ]] \
        || die "RISK-051: no valid release fingerprint (found '${fpr}'); run the air-gapped --keygen first."
    have_command gpg || die "gpg is required for --sign (unavailable in this sandbox)."
    [[ -f "${OUT}/${SUMS}" ]] || die "run --create first."
    [[ -f "${OUT}/${ISO}" ]]  || die "ISO not found: ${OUT}/${ISO}."
    gpg --batch --yes --armor --detach-sign --local-user "$fpr" \
        --output "${OUT}/${SIG}" "${OUT}/${SUMS}"
    gpg --batch --yes --armor --detach-sign --local-user "$fpr" \
        --output "${OUT}/${ISO}.sig" "${OUT}/${ISO}"
    ok "wrote ${OUT}/${SIG} and ${OUT}/${ISO}.sig with key ${fpr}"
    warn "Publish the fingerprint OUT OF BAND; never commit *.sig or *.gpg to Git."
}

do_self_test() {
    section "Phase 11 — checksum round-trip self-test (REAL, offline)"
    local tmp; tmp="$(mktemp -d -t ar0x-checksum-XXXXXXXX)"
    trap 'rm -rf -- "$tmp"' RETURN
    export AR0X_OUT_DIR="$tmp"
    OUT="$tmp"
    printf 'ar0x phase 11 self-test ISO payload\n' > "${tmp}/${ISO}"
    printf 'ar0x 0.1.0 changelog\n' > "${tmp}/CHANGELOG.md"
    cp -- "${tmp}/${ISO}" "${tmp}/.iso.pristine"

    "$0" --create >/dev/null || fail "--create failed"
    ok "--create: SHA256SUMS generated for 2 artifacts"
    "$0" --verify >/dev/null 2>&1 || fail "--verify rejected a clean tree"
    ok "--verify: clean tree PASSED"

    printf 'TAMPERED\n' >> "${tmp}/${ISO}"
    if "$0" --verify >/dev/null 2>&1; then
        fail "--verify ACCEPTED a tampered ISO (integrity gate is broken)"
    else
        ok "--verify: tampered ISO correctly REJECTED"
    fi
    cp -- "${tmp}/.iso.pristine" "${tmp}/${ISO}"
    "$0" --create >/dev/null
    "$0" --verify >/dev/null 2>&1 || fail "--verify failed after restore"
    ok "--verify: restored tree PASSED (idempotent)"

    if AR0X_CONFIRM_SIGN=yes "$0" --sign >/dev/null 2>&1; then
        fail "--sign SUCCEEDED while the release key is PENDING-KEYGEN (RISK-051)"
    else
        ok "--sign: correctly REFUSED with PENDING-KEYGEN (RISK-051)"
    fi
    [[ -f "${tmp}/${SUMS}" ]] || fail "SHA256SUMS not created in the temp out dir"
    [[ ! -e "${AR0X_SOURCE_ROOT}/SHA256SUMS" ]] \
        || fail "derived checksum leaked into the Git checkout"
    assert_clean
    ok "Phase 11 --self-test PASSED (no root, no network, no gpg, no ISO)"
}

case "${1:-}" in
    '')          MODE='check' ;;
    --check)     MODE='check' ;;
    --create)    MODE='create' ;;
    --verify)    MODE='verify' ;;
    --sign)      MODE='sign' ;;
    --self-test) MODE='self-test' ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown option: ${1:-}" ;;
esac
shift || true
(( $# == 0 )) || die "unexpected extra arguments: $*"

case "$MODE" in
    check)     do_check ;;
    create)    do_create ;;
    verify)    do_verify ;;
    sign)      do_sign ;;
    self-test) do_self_test ;;
esac
