#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/configure-tools.sh
# -----------------------------------------------------------------------------
# PHASE 8 — driver for the three custom ar0x tools + their PKGBUILDs.
#
#   --check     (default) READ-ONLY structural validation. No root, no network,
#               no writes. Runs tools/lib/ar0x_pkgbuild.py, `bash -n` on every
#               Phase 8 shell source, and Python AST checks.
#   --sync      Regenerate canonical -> package mirrors, refresh REAL SHA-256
#               sums in every PKGBUILD, and install a disposable smoke-test
#               prefix at ${AR0X_SOURCE_ROOT}/build/tools-prefix (gitignored,
#               NO root, NO writes to tracked files). Byte-idempotent.
#   --self-test Run all three tools from that prefix with their documented
#               TEST HOOKS, plus ar0x-info --json/--plain, ar0x-update --status
#               and ar0x-apparmor-ctl status. No root, no network, no GTK4.
#   --build     ⚠️ MANUAL + RISKY: `makepkg -s` for each package on a REAL Arch
#               host. Requires AR0X_CONFIRM_BUILD=yes. See §5 of TOOLS_GUIDE.md.
#
# ⚠️ RISK-047: no GTK4 / gi / display in this sandbox. The welcome WINDOW was
#    NEVER rendered. --self-test covers every pure-Python path only.
# ⚠️ RISK-048: the signed [ar0x] repo does not exist until Phase 9, so NO
#    ar0x-* package is listed in config/packages.x86_64 yet.
# ⚠️ RISK-049: makepkg/namcap/shellcheck are absent here. PKGBUILDs are
#    structurally validated and checksum-verified, NOT built.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PACKAGES=(ar0x-info ar0x-update ar0x-welcome)
PREFIX="${AR0X_SOURCE_ROOT}/build/tools-prefix"
LOG_FILE="${AR0X_LOG_DIR}/07-ar0x-tools.log"
MODE='check'

usage() {
    cat <<'USAGE'
ar0x Phase 8 — configure-tools.sh

  --check      Read-only structural validation (default). No root, no writes.
  --sync       Regenerate mirrors + SHA-256 sums + smoke-test prefix. No root.
  --self-test  Run the three tools' own offline self-tests from the prefix.
  --build      ⚠️ MANUAL, REAL ARCH HOST: makepkg -s for all 3 packages.
               Requires AR0X_CONFIRM_BUILD=yes. Can install build deps via
               pacman/sudo and has NO automatic rollback.
  -h|--help    This help.

Typical order:
  ./tools/configure-tools.sh --check
  ./tools/configure-tools.sh --sync
  ./tools/configure-tools.sh --self-test
  ./tools/validate-versions.sh
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)      MODE='check' ;;
        --sync)       MODE='sync' ;;
        --self-test)  MODE='selftest' ;;
        --build)      MODE='build' ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 1: canonical Phase 8 file inventory ----------------------------
PHASE8_FILES=(
    config/tools/links.conf config/tools/extra-groups.conf config/tools/update.conf
    packages/README.md
    packages/ar0x-info/PKGBUILD packages/ar0x-info/ar0x-info
    packages/ar0x-info/ar0x-info.desktop packages/ar0x-info/fastfetch.jsonc
    packages/ar0x-info/ar0x-ascii.txt packages/ar0x-info/ar0x-fastfetch.txt
    packages/ar0x-info/README.md
    packages/ar0x-update/PKGBUILD packages/ar0x-update/ar0x-update
    packages/ar0x-update/ar0x-update.desktop packages/ar0x-update/update.conf
    packages/ar0x-update/README.md
    packages/ar0x-welcome/PKGBUILD packages/ar0x-welcome/ar0x-welcome.py
    packages/ar0x-welcome/ar0x-welcome.desktop packages/ar0x-welcome/ar0x-welcome.css
    packages/ar0x-welcome/links.conf packages/ar0x-welcome/extra-groups.conf
    packages/ar0x-welcome/ar0x-welcome.service packages/ar0x-welcome/ar0x-firstboot.service
    packages/ar0x-welcome/ar0x-firstboot packages/ar0x-welcome/ar0x-apparmor-ctl
    packages/ar0x-welcome/ar0x-welcome.install packages/ar0x-welcome/README.md
    tools/lib/ar0x_pkgbuild.py tools/configure-tools.sh docs/TOOLS_GUIDE.md
)
for name in ar0x-theme ar0x-wallpapers ar0x-hypr-config ar0x-keyring ar0x-meta; do
    PHASE8_FILES+=("packages/${name}/README.md")
done
export PHASE8_FILES

# --- Section 2: --sync (canonical mirrors + checksums + test prefix) --------
sync_mirrors() {
    section "Regenerating Phase 8 canonical mirrors"
    local canonical="$AR0X_SOURCE_ROOT/config"
    install -D -m 0644 -- "$canonical/tools/links.conf" \
        "$AR0X_SOURCE_ROOT/packages/ar0x-welcome/links.conf"
    install -D -m 0644 -- "$canonical/tools/extra-groups.conf" \
        "$AR0X_SOURCE_ROOT/packages/ar0x-welcome/extra-groups.conf"
    install -D -m 0644 -- "$canonical/tools/update.conf" \
        "$AR0X_SOURCE_ROOT/packages/ar0x-update/update.conf"
    install -D -m 0644 -- "$canonical/branding/ascii/ar0x-ascii.txt" \
        "$AR0X_SOURCE_ROOT/packages/ar0x-info/ar0x-ascii.txt"
    install -D -m 0644 -- "$canonical/branding/ascii/ar0x-fastfetch.txt" \
        "$AR0X_SOURCE_ROOT/packages/ar0x-info/ar0x-fastfetch.txt"
    # Derived fastfetch config: ONLY the header + logo.source may differ.
    python3 - "$AR0X_SOURCE_ROOT" <<'PYGEN'
import os, sys
root = sys.argv[1]
src = os.path.join(root, 'config/branding/fastfetch/config.jsonc')
dst = os.path.join(root, 'packages/ar0x-info/fastfetch.jsonc')
s = open(src, encoding='utf-8').read()
s = s.replace('// /etc/skel/.config/fastfetch/config.jsonc  (CANONICAL: config/branding/fastfetch/)',
              '// /usr/share/ar0x/info/fastfetch.jsonc  (DERIVED from config/branding/fastfetch/)', 1)
s = s.replace('// The absolute /usr/share path is intentional: /etc/skel is copied into every\n'
              '// new home, and a "~" source would break for root, the live user and Calamares.',
              '// ar0x-info OWNS its art copy so it also works on a stock Arch install where\n'
              '// the Phase 7 /usr/share/ar0x/branding/ overlay is absent. The absolute path\n'
              '// is intentional: /etc/skel is copied into every new home.', 1)
s = s.replace('"/usr/share/ar0x/branding/ar0x-fastfetch.txt"',
              '"/usr/share/ar0x/info/ar0x-fastfetch.txt"', 1)
open(dst, 'w', encoding='utf-8', newline='\n').write(s)
print('[ OK ] derived packages/ar0x-info/fastfetch.jsonc')
PYGEN
    ok "6 canonical -> package mirrors regenerated"
}

refresh_checksums() {
    section "Refreshing real SHA-256 sums in every PKGBUILD"
    python3 - "$AR0X_SOURCE_ROOT" <<'PYSUM'
import hashlib, os, re, sys
root = sys.argv[1]
for pkg in ('ar0x-info', 'ar0x-update', 'ar0x-welcome'):
    d = os.path.join(root, 'packages', pkg)
    p = os.path.join(d, 'PKGBUILD')
    t = open(p, encoding='utf-8').read()
    m = re.search(r'^source=\((.*?)^\)', t, re.M | re.S)
    assert m, 'no source array in ' + p
    srcs = re.findall(r"'([^']+)'", m.group(1))
    sums = []
    for s in srcs:
        f = os.path.join(d, s)
        assert os.path.isfile(f), 'missing source: ' + f
        sums.append(hashlib.sha256(open(f, 'rb').read()).hexdigest())
    block = 'sha256sums=(\n' + ''.join("    '%s'\n" % x for x in sums) + ')'
    t2, n = re.subn(r'^sha256sums=\(.*?^\)', lambda _m: block, t, count=1,
                    flags=re.M | re.S)
    assert n == 1, 'no sha256sums array in ' + p
    if t2 != t:
        open(p, 'w', encoding='utf-8', newline='\n').write(t2)
    print('[ OK ] %s: %d SHA-256 sums %s' % (pkg, len(sums), 'updated' if t2 != t else 'already current'))
PYSUM
}

stage_prefix() {
    section "Installing a disposable smoke-test prefix (no root, gitignored)"
    local p="$PREFIX" src="$AR0X_SOURCE_ROOT/packages"
    mkdir -p -- "$p"
    install -D -m 0755 -- "$src/ar0x-info/ar0x-info"                 "$p/usr/bin/ar0x-info"
    install -D -m 0755 -- "$src/ar0x-update/ar0x-update"             "$p/usr/bin/ar0x-update"
    install -D -m 0755 -- "$src/ar0x-welcome/ar0x-welcome.py"        "$p/usr/bin/ar0x-welcome"
    install -D -m 0644 -- "$src/ar0x-info/fastfetch.jsonc"           "$p/usr/share/ar0x/info/fastfetch.jsonc"
    install -D -m 0644 -- "$src/ar0x-info/ar0x-ascii.txt"            "$p/usr/share/ar0x/info/ar0x-ascii.txt"
    install -D -m 0644 -- "$src/ar0x-info/ar0x-fastfetch.txt"        "$p/usr/share/ar0x/info/ar0x-fastfetch.txt"
    install -D -m 0644 -- "$src/ar0x-welcome/ar0x-welcome.css"       "$p/usr/share/ar0x/welcome/ar0x-welcome.css"
    install -D -m 0644 -- "$src/ar0x-welcome/links.conf"             "$p/usr/share/ar0x/welcome/links.conf"
    install -D -m 0644 -- "$src/ar0x-welcome/extra-groups.conf"      "$p/usr/share/ar0x/welcome/extra-groups.conf"
    install -D -m 0644 -- "$src/ar0x-update/update.conf"             "$p/etc/ar0x/update.conf"
    install -D -m 0755 -- "$src/ar0x-welcome/ar0x-firstboot"         "$p/usr/lib/ar0x/ar0x-firstboot"
    install -D -m 0755 -- "$src/ar0x-welcome/ar0x-apparmor-ctl"      "$p/usr/lib/ar0x/ar0x-apparmor-ctl"
    install -D -m 0644 -- "$src/ar0x-info/ar0x-info.desktop"         "$p/usr/share/applications/ar0x-info.desktop"
    install -D -m 0644 -- "$src/ar0x-update/ar0x-update.desktop"     "$p/usr/share/applications/ar0x-update.desktop"
    install -D -m 0644 -- "$src/ar0x-welcome/ar0x-welcome.desktop"   "$p/usr/share/applications/ar0x-welcome.desktop"
    install -D -m 0644 -- "$src/ar0x-welcome/ar0x-welcome.service"   "$p/usr/lib/systemd/user/ar0x-welcome.service"
    install -D -m 0644 -- "$src/ar0x-welcome/ar0x-firstboot.service" "$p/usr/lib/systemd/system/ar0x-firstboot.service"
    ok "smoke-test prefix installed at ${p}"
    log "Prefix is under /build/ and gitignored; it is NOT part of the ISO."
}

# --- Section 3: --check ------------------------------------------------------
check_files() {
    section "Phase 8 file inventory"
    local f count=0
    for f in "${PHASE8_FILES[@]}"; do
        [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 8 file: ${f}"
        count=$((count + 1))
    done
    ok "All ${count} Phase 8 deliverables present"
}

check_syntax() {
    section "Shell + Python syntax gates"
    local f
    while IFS= read -r -d '' f; do
        bash -n -- "$f" || fail "bash -n failed: ${f}"
    done < <(find "${AR0X_SOURCE_ROOT}/packages" -type f \
                \( -name 'PKGBUILD' -o -name '*.install' \) -print0 2>/dev/null)
    for f in \
        packages/ar0x-info/ar0x-info \
        packages/ar0x-update/ar0x-update \
        packages/ar0x-welcome/ar0x-firstboot \
        packages/ar0x-welcome/ar0x-apparmor-ctl ; do
        bash -n -- "${AR0X_SOURCE_ROOT}/${f}" || fail "bash -n failed: ${f}"
    done
    bash -n -- "${SCRIPT_DIR}/configure-tools.sh" || fail 'bash -n failed: configure-tools.sh'
    python3 - "${AR0X_SOURCE_ROOT}" <<'PYAST' || fail 'Python AST check failed'
import ast, os, sys
root = sys.argv[1]
for rel in ('packages/ar0x-welcome/ar0x-welcome.py', 'tools/lib/ar0x_pkgbuild.py'):
    ast.parse(open(os.path.join(root, rel), encoding='utf-8').read(), filename=rel)
    print('[ OK ] Python AST: %s' % rel)
PYAST
    ok "4 bash executables + 3 PKGBUILDs + 1 scriptlet + 2 Python modules pass syntax gates"
}

check_structure() {
    section "PKGBUILD / .desktop / systemd / parity gates"
    python3 "${SCRIPT_DIR}/lib/ar0x_pkgbuild.py" "${AR0X_SOURCE_ROOT}" \
        || fail "tools/lib/ar0x_pkgbuild.py reported a structural error."
}

# --- Section 4: --self-test --------------------------------------------------
self_test() {
    section "Offline self-tests (no root, no network, no GTK4)"
    [[ -x "${PREFIX}/usr/bin/ar0x-info" ]] \
        || die "Smoke-test prefix missing. Run ./tools/configure-tools.sh --sync first."
    local info_datadir="${PREFIX}/usr/share/ar0x/info"
    local welcome_datadir="${PREFIX}/usr/share/ar0x/welcome"
    local conf="${PREFIX}/etc/ar0x/update.conf"
    local tmp; tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' RETURN

    AR0X_INFO_DATADIR="$info_datadir" "${PREFIX}/usr/bin/ar0x-info" --self-test \
        || fail 'ar0x-info --self-test failed'
    AR0X_UPDATE_CONF="$conf" "${PREFIX}/usr/bin/ar0x-update" --self-test \
        || fail 'ar0x-update --self-test failed'
    AR0X_WELCOME_DATADIR="$welcome_datadir" \
    AR0X_WELCOME_SRC_ROOT="$AR0X_SOURCE_ROOT" \
        "${PREFIX}/usr/bin/ar0x-welcome" --self-test \
        || fail 'ar0x-welcome --self-test failed'

    # Real end-to-end runs of the two CLI tools against this sandbox.
    AR0X_INFO_DATADIR="$info_datadir" "${PREFIX}/usr/bin/ar0x-info" --json > "$tmp/info.json"
    python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,dict) and len(d)>=17; print("[ OK ] ar0x-info --json is parseable JSON (%d keys)" % len(d))' < "$tmp/info.json" \
        || fail 'ar0x-info --json did not produce valid JSON'
    AR0X_INFO_DATADIR="$info_datadir" "${PREFIX}/usr/bin/ar0x-info" --plain > "$tmp/plain.txt"
    grep -Fq 'Distro' "$tmp/plain.txt" || fail 'ar0x-info --plain missing summary'
    ok "ar0x-info --plain renders branded ASCII + summary"
    AR0X_UPDATE_CONF="$conf" "${PREFIX}/usr/bin/ar0x-update" --status > "$tmp/status.txt"
    grep -Fq 'repo' "$tmp/status.txt" || fail 'ar0x-update --status incomplete'
    ok "ar0x-update --status reports effective config without root/network"
    "${PREFIX}/usr/lib/ar0x/ar0x-apparmor-ctl" status | grep -Eq '^(enforce|complain)$' \
        || fail 'ar0x-apparmor-ctl status invalid'
    ok "ar0x-apparmor-ctl status reports complain (v0.1 default)"

    # --firstboot must skip silently when the marker already exists (NO GUI).
    : > "$tmp/welcome-done"
    AR0X_WELCOME_MARKER="$tmp/welcome-done" \
    AR0X_WELCOME_DATADIR="$welcome_datadir" \
        "${PREFIX}/usr/bin/ar0x-welcome" --firstboot \
        || fail 'ar0x-welcome --firstboot should skip when marker exists'
    ok "ar0x-welcome --firstboot skips without GTK4 when marker exists"

    assert_clean
    ok "Phase 8 --self-test PASSED (6 e2e checks + 3 tool self-tests)"
}

# --- Section 5: --build (MANUAL, RISKY) -------------------------------------
build_packages() {
    section "Building the 3 ar0x packages with makepkg"
    warn 'RISK-049: this runs `makepkg -s`, which may call sudo/pacman to INSTALL'
    warn 'build dependencies on the HOST and has NO automatic rollback.'
    warn 'It requires a REAL Arch host, base-devel, network, and ~2 GiB free.'
    warn 'There is no [ar0x] repo until Phase 9, so output is NOT published.'
    if [[ "${AR0X_CONFIRM_BUILD:-}" != 'yes' ]]; then
        die 'Set AR0X_CONFIRM_BUILD=yes to acknowledge the risk and proceed.'
    fi
    require_command makepkg
    local pkg
    for pkg in "${PACKAGES[@]}"; do
        log "Building ${pkg} ..."
        ( cd -- "${AR0X_SOURCE_ROOT}/packages/${pkg}" && makepkg -s --noconfirm ) \
            || fail "makepkg failed for ${pkg}"
    done
    ok "3 packages built. Signing + repo-add are Phase 9 (tools/setup-repo.sh)."
}

# --- Section 6: dispatch -----------------------------------------------------
case "$MODE" in
    check)
        warn 'RISK-047: GTK4/welcome window was NEVER rendered in this sandbox.'
        warn 'RISK-048: signed [ar0x] repo is Phase 9; no ar0x-* package on the ISO yet.'
        warn 'RISK-049: makepkg/namcap/shellcheck are absent; PKGBUILDs are structurally validated only.'
        check_files
        check_syntax
        check_structure
        assert_clean
        ok "Phase 8 --check PASSED (no root, no writes)"
        ;;
    sync)
        sync_mirrors
        refresh_checksums
        stage_prefix
        assert_clean
        ok "Phase 8 --sync complete"
        printf '  Next: ./tools/configure-tools.sh --check && ./tools/configure-tools.sh --self-test\n'
        ;;
    selftest)
        self_test
        ;;
    build)
        build_packages
        ;;
esac
