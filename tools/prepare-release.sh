#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/prepare-release.sh — Phase 12
# -----------------------------------------------------------------------------
# Release-engineering driver. It PREPARES and VALIDATES; it NEVER publishes.
#
#   --check       (default) READ-ONLY structural validation. No root/network/writes.
#   --sync        Stage build/release-prefix/ (gitignored) with the release
#                 documents + a rendered manifest + the 6-member artifact list.
#   --self-test   ar0x_release.py --self-test (9 negative mutations + REAL mock
#                 artifact-set assembly) + prefix parity + publish-refusal gate.
#   --preflight   MANUAL print-only: the 9 gates before a tag may be created.
#   --publish     MANUAL print-only. Requires AR0X_CONFIRM_PUBLISH=yes. Prints
#                 the exact gh/rsync commands and NEVER uploads anything.
#
# ⚠️ RISK-054: NO tag, GitHub Release, mirror upload, announcement or
#    DistroWatch submission happened. --publish is PRINT-ONLY and NEVER uploads.
# ⚠️ RISK-051: RELEASE_KEY_FINGERPRINT is PENDING-KEYGEN; never commit a private
#    key, *.gpg/*.asc/*.sig, SHA256SUMS or a *.iso. Artifacts live in out/.
# ⚠️ RISK-053/048: no ISO exists and the signed [ar0x] db is not published.
# ⚠️ RISK-050: repo.ar0x.dev and all 5 AR0X_URL_* endpoints are RESERVED.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=config/release/release-options.conf
source "${AR0X_CONFIG_DIR}/release/release-options.conf"

REL_DIR="${AR0X_CONFIG_DIR}/release"
PREFIX="${AR0X_SOURCE_ROOT}/build/release-prefix"
VALIDATOR="${SCRIPT_DIR}/lib/ar0x_release.py"
OUT="${AR0X_OUT_DIR}"
MODE='check'

usage() {
    cat <<'USAGE'
ar0x Phase 12 — prepare-release.sh (print-only release tooling)

  --check       Read-only structural validation (default).
  --sync        Stage the disposable build/release-prefix (gitignored).
  --self-test   Offline validator self-test + prefix parity + publish refusal.
  --preflight   MANUAL print-only pre-publication gates (never uploads).
  --publish     MANUAL print-only gh/rsync commands (NEVER uploads anything).
                Requires AR0X_CONFIRM_PUBLISH=yes.
  -h|--help     This help.

  --publish is deliberately NOT an uploader: this driver NEVER uploads.
  See docs/RELEASE_GUIDE.md section 4 for the real manual commands.
USAGE
}

# ---------------------------------------------------------------------------
stage_prefix() {
    log "Staging disposable release prefix: ${PREFIX}"
    rm -rf -- "$PREFIX"
    mkdir -p -- "${PREFIX}/docs"
    local f
    for f in README.md CHANGELOG.md; do
        install -m 0644 -- "${AR0X_SOURCE_ROOT}/${f}" "${PREFIX}/${f}"
    done
    for f in ANNOUNCEMENT.md DISTROWATCH.md ROADMAP.md RELEASE_GUIDE.md \
             TESTING_CHECKLIST.md; do
        install -m 0644 -- "${AR0X_DOCS_DIR}/${f}" "${PREFIX}/docs/${f}"
    done
    install -m 0644 -- "${REL_DIR}/README.md" "${PREFIX}/CONFIG_README.md"
    {
        printf 'ar0x %s (%s) release manifest  [DRAFT — NOT PUBLISHED]\n' \
            "$AR0X_VERSION" "$AR0X_CODENAME"
        printf 'tag=%s\n'            "$AR0X_RELEASE_TAG"
        printf 'title=%s\n'          "$AR0X_RELEASE_TITLE"
        printf 'series=%s\n'         "$AR0X_RELEASE_SERIES"
        printf 'iso=%s\n'            "$AR0X_RELEASE_ISO"
        printf 'primary_host=%s\n'   "$AR0X_RELEASE_PRIMARY_HOST"
        printf 'repo_slug=%s\n'      "$AR0X_RELEASE_REPO_SLUG"
        printf 'secondary_host=%s\n' "$AR0X_RELEASE_SECONDARY_HOST"
        printf 'eol_policy=%s\n'     "$AR0X_RELEASE_EOL_POLICY"
        printf 'fpr_file=%s\n'       "$AR0X_RELEASE_FPR_FILE"
        printf 'checklist_gate=%s%%\n' "$AR0X_RELEASE_MIN_CHECKLIST_GATE"
        printf 'artifact_count=%s\n' "$AR0X_RELEASE_ARTIFACT_COUNT"
    } > "${PREFIX}/RELEASE_MANIFEST.txt"
    tr ',' '\n' <<< "$AR0X_RELEASE_ARTIFACT_SET" > "${PREFIX}/ARTIFACT_SET.txt"
    ok "staged 5 docs + 2 root docs + manifest + 6-member artifact list (gitignored)"
}

do_sync() {
    section "Phase 12 — staging disposable release prefix"
    stage_prefix
    log "No root, no network, no writes to tracked files, NOTHING published."
}

# ---------------------------------------------------------------------------
check_mirror() {
    local canonical="$1" mirror="$2" label="$3"
    [[ -f "$mirror" ]] || { fail "missing staged mirror: ${mirror} (run --sync)"; return 0; }
    cmp -s -- "$canonical" "$mirror" \
        || { fail "${label} staged mirror is stale (run --sync)"; return 0; }
    ok "${label}: staged copy byte-identical"
}

do_check() {
    section "Phase 12 — read-only release validation"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" || fail "ar0x_release.py failed"
    bash -n -- "$0" || fail "bash -n failed on prepare-release.sh"
    ok "bash -n: prepare-release.sh"
    [[ -x "$0" ]] || fail "prepare-release.sh must be mode 0755"
    ok "driver mode 0755"

    # Derived release artifacts must NEVER be in the Git checkout.
    local f
    for f in "$AR0X_RELEASE_ISO" SHA256SUMS SHA256SUMS.sig \
             "${AR0X_RELEASE_ISO}.sig"; do
        if [[ -e "${AR0X_SOURCE_ROOT}/${f}" ]]; then
            fail "RISK-051: derived artifact leaked into the checkout: ${f}"
        fi
    done
    ok "no derived ISO/SHA256SUMS/*.sig in the tracked source root"

    "${SCRIPT_DIR}/checksum.sh" --check >/dev/null 2>&1 \
        || fail "checksum.sh --check disagrees on the artifact contract"
    ok "checksum.sh --check agrees on the sha256/signature contract"

    assert_clean
    ok "Phase 12 --check PASSED (no writes)"
}

# ---------------------------------------------------------------------------
do_self_test() {
    section "Phase 12 — offline release self-test"
    python3 "$VALIDATOR" "$AR0X_SOURCE_ROOT" --self-test \
        || fail "ar0x_release.py --self-test failed"

    if [[ ! -d "${PREFIX}/docs" ]]; then
        warn "prefix missing; restaging (no writes to tracked files)"
        stage_prefix
    fi
    check_mirror "${AR0X_SOURCE_ROOT}/README.md" "${PREFIX}/README.md" "README"
    check_mirror "${AR0X_SOURCE_ROOT}/CHANGELOG.md" "${PREFIX}/CHANGELOG.md" "CHANGELOG"
    for f in ANNOUNCEMENT.md DISTROWATCH.md ROADMAP.md RELEASE_GUIDE.md \
             TESTING_CHECKLIST.md; do
        check_mirror "${AR0X_DOCS_DIR}/${f}" "${PREFIX}/docs/${f}" "docs/${f}"
    done
    [[ "$(wc -l < "${PREFIX}/ARTIFACT_SET.txt")" -eq 6 ]] \
        || fail "staged ARTIFACT_SET.txt must have exactly 6 lines"
    ok "staged artifact list: exactly 6 members"

    # --publish MUST refuse without explicit confirmation, and MUST NOT upload.
    if AR0X_CONFIRM_PUBLISH=no "$0" --publish >/dev/null 2>&1; then
        fail "--publish succeeded WITHOUT AR0X_CONFIRM_PUBLISH=yes"
    else
        ok "--publish correctly REFUSES without explicit confirmation"
    fi
    AR0X_CONFIRM_PUBLISH=yes "$0" --publish >/dev/null \
        || fail "--publish failed in print-only mode"
    ok "--publish is print-only: NOTHING was published"

    assert_clean
    ok "Phase 12 --self-test PASSED (no root, no network, no gh, no gpg, no upload)"
}

# ---------------------------------------------------------------------------
do_preflight() {
    section "Phase 12 — MANUAL pre-publication gates (print only, NEVER publishes)"
    printf '  1. Air-gapped --keygen; commit + publish the 40-hex FPR OUT OF BAND (RISK-051).\n'
    printf '  2. Build, sign and publish the signed [ar0x] db; DNS + TLS for repo.ar0x.dev.\n'
    printf '  3. build-release.sh --run stages the profile + injects calamares/ar0x-meta (ADR-029).\n'
    printf '  4. sudo AR0X_CONFIRM_BUILD=yes ./tools/build-iso.sh --build (<= 2362232012 bytes).\n'
    printf '  5. ./tools/checksum.sh --create -> --sign -> --verify (RISK-015).\n'
    printf '  6. docs/TESTING_CHECKLIST.md 40/40 PASS (100%%), QEMU BIOS+UEFI, real hardware QA.\n'
    printf '  7. curl -IL all 5 AR0X_URL_* endpoints + the reserved mirror host (RISK-050).\n'
    printf '  8. gpg --verify SHA256SUMS.sig SHA256SUMS && sha256sum -c SHA256SUMS on a FRESH download.\n'
    printf '  9. Replace every {{PLACEHOLDER}}; remove DRAFT/UNRELEASED banners; date CHANGELOG.md.\n\n'
    warn "RISK-054: NOTHING was tagged, uploaded, announced or submitted by --preflight."
    ok "MANUAL preflight checklist printed"
}

# ---------------------------------------------------------------------------
do_publish() {
    section "Phase 12 — MANUAL publish commands (PRINT ONLY — NEVER uploads)"
    if [[ "${AR0X_CONFIRM_PUBLISH:-no}" != "yes" ]]; then
        die "Set AR0X_CONFIRM_PUBLISH=yes after reading docs/RELEASE_GUIDE.md section 2."
    fi
    local fpr
    fpr="$(grep -v '^[[:space:]]*#' \
           "${AR0X_SOURCE_ROOT}/${AR0X_RELEASE_FPR_FILE}" | tr -d '[:space:]')"
    if [[ "$fpr" == "PENDING-KEYGEN" ]]; then
        warn "RISK-051/054: PENDING-KEYGEN — DO NOT TAG OR PUBLISH. The commands below are documentation only."
    fi
    warn "RISK-054: docs/TESTING_CHECKLIST.md is 0/40 here. Run --preflight gate 6 on the real host."
    printf '\n# 1. Annotated, signed tag FIRST (--verify-tag then checks it):\n'
    printf 'git tag -s %s -m %q -u <RELEASE_FINGERPRINT_40HEX>\n' \
        "$AR0X_RELEASE_TAG" "$AR0X_RELEASE_TITLE"
    printf 'git push origin %s\n\n' "$AR0X_RELEASE_TAG"
    printf '# 2. GitHub Releases (primary host) with an EXPLICIT 6-asset list:\n'
    printf 'gh release create %s \\\n' "$AR0X_RELEASE_TAG"
    printf '    --repo %s --title %q \\\n' "$AR0X_RELEASE_REPO_SLUG" "$AR0X_RELEASE_TITLE"
    printf '    --verify-tag --notes-file %s/CHANGELOG.md \\\n' "$OUT"
    local name
    for name in ${AR0X_RELEASE_ARTIFACT_SET//,/ }; do
        printf '    %s/%s \\\n' "$OUT" "$name"
    done
    printf '\n# 3. Secondary mirror, then SourceForge / OSDN:\n'
    printf 'rsync -av --checksum --partial %s/ %s\n' "$OUT" "$AR0X_RELEASE_RSYNC_TARGET"
    printf '\n# 4. AFTER upload: re-download and verify\n'
    printf 'gpg --verify SHA256SUMS.sig SHA256SUMS\n'
    printf 'sha256sum -c SHA256SUMS\n'
    printf 'gpg --verify %s.sig %s\n\n' "$AR0X_RELEASE_ISO" "$AR0X_RELEASE_ISO"
    warn "RISK-054: NOTHING was published. This driver NEVER uploads — run the printed commands MANUALLY."
    ok "print-only publish checklist emitted (NEVER uploads)"
}

# ---------------------------------------------------------------------------
case "${1:-}" in
    '')           MODE='check' ;;
    --check)      MODE='check' ;;
    --sync)       MODE='sync' ;;
    --self-test)  MODE='self-test' ;;
    --preflight)  MODE='preflight' ;;
    --publish)    MODE='publish' ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage >&2; die "unknown option: ${1:-}" ;;
esac
shift || true
(( $# == 0 )) || die "unexpected extra arguments: $*"

case "$MODE" in
    check)      do_check ;;
    sync)       do_sync ;;
    self-test)  do_self_test ;;
    preflight)  do_preflight ;;
    publish)    do_publish ;;
esac
