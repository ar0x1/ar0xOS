#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/setup-repo.sh
# -----------------------------------------------------------------------------
# PHASE 9 — driver for the signed [ar0x] package repository.
#
#   --check            (default) READ-ONLY structural validation. No root,
#                      no network, no writes. Runs tools/lib/ar0x_repo.py,
#                      `bash -n` on every shell source and Python AST checks.
#   --sync             Regenerate the 31 canonical -> package mirrors, derive
#                      ar0x-trusted from the release fingerprint, refresh REAL
#                      SHA-256 sums in ALL 8 PKGBUILDs, and stage a disposable
#                      build/repo-prefix for --self-test. No root, gitignored.
#   --self-test        Offline mock-repo tests + REAL runs of the 3
#                      ar0x-apply-* helpers + the 3 Phase 8 tools' self-tests.
#   --verify <DIR>     Validate a built repo tree (db/db.sig/files/files.sig,
#                      every .pkg.tar.zst has a .sig, SHA256SUMS + .sig).
#   --keygen           ⚠️ MANUAL + AIR-GAPPED: generate the OFFLINE GPG release
#                      key. Requires AR0X_CONFIRM_KEYGEN=yes and gpg/pinentry.
#   --build            ⚠️ MANUAL, REAL ARCH HOST: makepkg --nodeps for all 8.
#                      Requires AR0X_CONFIRM_BUILD=yes; refuses root.
#   --sign             ⚠️ MANUAL: detached-sign every package, `repo-add -s`,
#                      SHA256SUMS.sig. Requires AR0X_CONFIRM_SIGN=yes + key.
#   --publish          Stage build/repo-publish (NO UPLOAD EVER). Prints the
#                      exact MANUAL rsync / gh release command.
#
# ⚠️ RISK-051: the PRIVATE key NEVER enters this Git checkout. It lives in
#    ${AR0X_KEYS_DIR}/gnupg (mode 0700). CI signing uses release.yml with
#    GitHub Environment secrets, and that workflow NEVER runs on PRs.
# ⚠️ RISK-048/049: the signed db is NOT built here (no gpg/makepkg/repo-add
#    in the sandbox). Phase 9 ships the complete tooling + CI, not a published
#    repo. Acceptance criterion 7 remains a MANUAL/Phase 12 gate.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# Plain KEY="value" DATA FILE (not an executable script): no strict mode needed.
# shellcheck source=/dev/null
source "${AR0X_CONFIG_DIR}/repo/repo-options.conf"

LOG_FILE="${AR0X_LOG_DIR}/08-ar0x-repo.log"
ALL_PACKAGES=(ar0x-info ar0x-update ar0x-keyring ar0x-welcome ar0x-theme \
              ar0x-wallpapers ar0x-hypr-config ar0x-meta)
REPO_PACKAGES=(ar0x-theme ar0x-wallpapers ar0x-hypr-config ar0x-keyring ar0x-meta)
PUBLISH_DIR="${AR0X_SOURCE_ROOT}/build/repo-publish"
PREFIX="${AR0X_SOURCE_ROOT}/build/repo-prefix"
MODE='check'
VERIFY_DIR=''

usage() {
    cat <<'USAGE'
ar0x Phase 9 — setup-repo.sh

  --check             Read-only structural validation (default). No root/writes.
  --sync              Regenerate mirrors + trusted list + all 8 PKGBUILD sums.
  --self-test         Offline mock repo + real ar0x-apply-* helper runs.
  --verify <DIR>      Validate a built signed repo directory.
  --keygen            ⚠️ MANUAL, AIR-GAPPED: create the offline GPG release key.
  --build             ⚠️ MANUAL, Arch host: makepkg --nodeps x8.
  --sign              ⚠️ MANUAL: sign packages + `repo-add -s` + SHA256SUMS.sig.
  --publish           Stage a publish bundle; NEVER uploads. Prints MANUAL cmds.
  -h|--help           This help.

Typical offline order:
  ./tools/setup-repo.sh --check
  ./tools/setup-repo.sh --sync
  ./tools/setup-repo.sh --self-test
  ./tools/validate-versions.sh
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)      MODE='check' ;;
        --sync)       MODE='sync' ;;
        --self-test)  MODE='selftest' ;;
        --verify)
            MODE='verify'
            (( $# >= 2 )) || die "--verify requires a directory argument."
            VERIFY_DIR="$2"; shift ;;
        --keygen)     MODE='keygen' ;;
        --build)      MODE='build' ;;
        --sign)       MODE='sign' ;;
        --publish)    MODE='publish' ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 1: canonical Phase 9 file inventory -----------------------------
PHASE9_FILES=(
    config/repo/repo-options.conf config/repo/README.md
    config/repo/RELEASE_KEY_FINGERPRINT config/repo/pacman.conf.ar0x-entry
    packages/README.md
    packages/ar0x-theme/PKGBUILD packages/ar0x-theme/README.md
    packages/ar0x-theme/ar0x-apply-theme
    packages/ar0x-wallpapers/PKGBUILD packages/ar0x-wallpapers/README.md
    packages/ar0x-wallpapers/ar0x-apply-wallpapers
    packages/ar0x-hypr-config/PKGBUILD packages/ar0x-hypr-config/README.md
    packages/ar0x-hypr-config/ar0x-apply-hypr-config
    packages/ar0x-keyring/PKGBUILD packages/ar0x-keyring/README.md
    packages/ar0x-keyring/ar0x-trusted packages/ar0x-keyring/ar0x-revoked
    packages/ar0x-keyring/ar0x-keyring.install
    packages/ar0x-keyring/pacman.conf.ar0x-entry
    packages/ar0x-meta/PKGBUILD packages/ar0x-meta/README.md
    packages/ar0x-meta/RELEASE
    tools/lib/ar0x_repo.py tools/setup-repo.sh docs/REPO_GUIDE.md
    ci/workflows/validate-packages.yml ci/workflows/build-packages.yml
    ci/workflows/release.yml ci/workflows/README.md
)

check_files() {
    section "Phase 9 file inventory"
    local f count=0
    for f in "${PHASE9_FILES[@]}"; do
        [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 9 deliverable: ${f}"
        count=$((count + 1))
    done
    ok "All ${count} Phase 9 deliverables present"
}

# --- Section 2: --sync -------------------------------------------------------
sync_all() {
    section "Delegating Phase 8 mirrors + PKGBUILD sums"
    "${SCRIPT_DIR}/configure-tools.sh" --sync >/dev/null \
        || fail "configure-tools.sh --sync failed"
    ok "Phase 8: 6 mirrors + 3 PKGBUILD checksums refreshed"

    section "Regenerating 31 Phase 9 canonical mirrors"
    python3 - "${AR0X_SOURCE_ROOT}" <<'PYMIRROR'
import os, shutil, sys
root = sys.argv[1]
pairs = []
for rel in ('gtk-3.0/settings.ini','gtk-3.0/gtk.css','gtk-4.0/settings.ini',
            'gtk-4.0/gtk.css','qt5ct/qt5ct.conf','qt6ct/qt6ct.conf'):
    pairs.append(('config/desktop/'+rel, 'packages/ar0x-theme/'+rel))
pairs.append(('config/desktop/fontconfig/conf.d/99-ar0x-fonts.conf',
              'packages/ar0x-theme/fontconfig/99-ar0x-fonts.conf'))
for rel in ('hyprland.lua','hyprpaper.conf','hyprlock.conf','hypridle.conf'):
    pairs.append(('config/desktop/hypr/'+rel, 'packages/ar0x-hypr-config/'+rel))
for n in ('animations','autostart','env','input','keybinds','looknfeel',
          'monitors','palette','programs','rules'):
    pairs.append(('config/desktop/hypr/lua/%s.lua'%n,
                  'packages/ar0x-hypr-config/lua/%s.lua'%n))
for f in ('ar0x-neon-grid.png','ar0x-void.png','ar0x-circuit.png'):
    pairs.append(('assets/wallpapers/'+f, 'packages/ar0x-wallpapers/'+f))
for f in ('ar0x-logo.svg','ar0x-logo-mono.svg','ar0x-wordmark.svg','LICENSE'):
    pairs.append(('assets/logo/'+f, 'packages/ar0x-wallpapers/'+f))
pairs.append(('assets/grub-theme/ar0x/theme.txt','packages/ar0x-wallpapers/theme.txt'))
pairs.append(('assets/sddm/ar0x/Main.qml','packages/ar0x-wallpapers/Main.qml'))
pairs.append(('config/repo/pacman.conf.ar0x-entry',
              'packages/ar0x-keyring/pacman.conf.ar0x-entry'))
for a, b in pairs:
    s, d = os.path.join(root, a), os.path.join(root, b)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    shutil.copyfile(s, d)
    os.chmod(d, 0o644)
print('[ OK ] %d byte-identical mirrors' % len(pairs))
PYMIRROR

    section "Deriving ar0x-trusted from the release fingerprint"
    python3 - "${AR0X_SOURCE_ROOT}" <<'PYTRUST'
import os, re, sys
root = sys.argv[1]
f = os.path.join(root, 'config/repo/RELEASE_KEY_FINGERPRINT')
lines = [l.strip() for l in open(f, encoding='utf-8').read().splitlines()
         if l.strip() and not l.strip().startswith('#')]
fpr = lines[0] if len(lines) == 1 else ''
header = '''# /usr/share/pacman/keyrings/ar0x-trusted
# -----------------------------------------------------------------------------
# Ownertrust dump consumed by `pacman-key --populate ar0x`. Format is exactly
# `gpg --export-ownertrust`: <40-HEX-FINGERPRINT>:6:   (6 = ultimate trust).
# pacman-key lsigned each listed key and imports these ownertrust values.
#
# ⚠️ MANUAL: regenerated by `sudo ./tools/setup-repo.sh --keygen` followed by
# `./tools/setup-repo.sh --sync`. Until then this file has ZERO entries, so
# `SigLevel = Required` correctly REFUSES an unsigned/untrusted [ar0x] repo.
# NEVER fabricate a fingerprint. Publish the real one out of band (RISK-051).
# -----------------------------------------------------------------------------
'''
if fpr == 'PENDING-KEYGEN':
    body = ''
    state = 'PENDING (no entries; signed repo correctly refused)'
else:
    assert re.fullmatch(r'[0-9A-F]{40}', fpr), 'invalid fingerprint: %r' % fpr
    body = '%s:6:\n' % fpr
    state = 'ownertrust entry written for %s' % fpr
open(os.path.join(root, 'packages/ar0x-keyring/ar0x-trusted'), 'w',
     encoding='utf-8', newline='\n').write(header + body)
print('[ OK ] ar0x-trusted: %s' % state)
PYTRUST

    section "Refreshing REAL SHA-256 sums in all 8 PKGBUILDs"
    python3 - "${AR0X_SOURCE_ROOT}" <<'PYSUMS'
import hashlib, os, re, sys
root = sys.argv[1]
pkgs = ('ar0x-info','ar0x-update','ar0x-welcome','ar0x-theme',
        'ar0x-wallpapers','ar0x-hypr-config','ar0x-keyring','ar0x-meta')
total = 0
for pkg in pkgs:
    d = os.path.join(root, 'packages', pkg)
    f = os.path.join(d, 'PKGBUILD')
    t = open(f, encoding='utf-8').read()
    m = re.search(r'^source=\((.*?)^\)', t, re.M | re.S)
    assert m, 'no source array in ' + f
    srcs = re.findall(r"'([^']+)'", m.group(1))
    sums = []
    for src in srcs:
        path = os.path.join(d, src)
        if pkg == 'ar0x-keyring' and src == 'ar0x-public-key.asc':
            # MANUAL keygen artifact. Use a real sum once it exists, else SKIP.
            sums.append(hashlib.sha256(open(path, 'rb').read()).hexdigest()
                        if os.path.isfile(path) else 'SKIP')
            continue
        assert os.path.isfile(path), 'missing source: ' + path
        sums.append(hashlib.sha256(open(path, 'rb').read()).hexdigest())
    block = 'sha256sums=(\n' + ''.join("    '%s'\n" % x for x in sums) + ')'
    t2, n = re.subn(r'^sha256sums=\(.*?^\)', lambda _m: block, t, count=1,
                    flags=re.M | re.S)
    assert n == 1, 'no sha256sums array in ' + f
    if t2 != t:
        open(f, 'w', encoding='utf-8', newline='\n').write(t2)
    total += len(sums)
    print('[ OK ] %-20s %2d sums %s' % (pkg, len(sums), 'updated' if t2 != t else 'current'))
print('[ OK ] %d total sums across 8 PKGBUILDs' % total)
PYSUMS

    section "Staging a disposable test prefix (no root, gitignored)"
    local p="$PREFIX"
    install -D -m 0755 -- "${AR0X_PACKAGES_DIR}/ar0x-theme/ar0x-apply-theme" \
        "$p/usr/bin/ar0x-apply-theme"
    install -D -m 0755 -- "${AR0X_PACKAGES_DIR}/ar0x-hypr-config/ar0x-apply-hypr-config" \
        "$p/usr/bin/ar0x-apply-hypr-config"
    install -D -m 0755 -- "${AR0X_PACKAGES_DIR}/ar0x-wallpapers/ar0x-apply-wallpapers" \
        "$p/usr/bin/ar0x-apply-wallpapers"
    for rel in gtk-3.0/settings.ini gtk-3.0/gtk.css gtk-4.0/settings.ini \
               gtk-4.0/gtk.css qt5ct/qt5ct.conf qt6ct/qt6ct.conf \
               fontconfig/99-ar0x-fonts.conf; do
        install -D -m 0644 -- "${AR0X_PACKAGES_DIR}/ar0x-theme/$rel" \
            "$p/usr/share/ar0x/theme/$rel"
    done
    for rel in hyprland.lua hyprpaper.conf hyprlock.conf hypridle.conf; do
        install -D -m 0644 -- "${AR0X_PACKAGES_DIR}/ar0x-hypr-config/$rel" \
            "$p/usr/share/ar0x/hypr-config/$rel"
    done
    for n in animations autostart env input keybinds looknfeel monitors palette programs rules; do
        install -D -m 0644 -- "${AR0X_PACKAGES_DIR}/ar0x-hypr-config/lua/$n.lua" \
            "$p/usr/share/ar0x/hypr-config/lua/$n.lua"
    done
    for n in ar0x-neon-grid.png ar0x-void.png ar0x-circuit.png; do
        install -D -m 0644 -- "${AR0X_PACKAGES_DIR}/ar0x-wallpapers/$n" \
            "$p/usr/share/ar0x/wallpapers/$n"
    done
    ok "test prefix at ${p} (under /build/, gitignored)"
    assert_clean
    ok "Phase 9 --sync complete"
}

# --- Section 3: --check ------------------------------------------------------
check_syntax() {
    section "Shell + Python syntax gates"
    local f
    while IFS= read -r -d '' f; do
        bash -n -- "$f" || fail "bash -n failed: ${f}"
    done < <(find "${AR0X_SOURCE_ROOT}/packages" -type f \
                \( -name 'PKGBUILD' -o -name '*.install' \) -print0 2>/dev/null)
    for f in packages/ar0x-info/ar0x-info packages/ar0x-update/ar0x-update \
             packages/ar0x-welcome/ar0x-firstboot \
             packages/ar0x-welcome/ar0x-apparmor-ctl \
             packages/ar0x-theme/ar0x-apply-theme \
             packages/ar0x-wallpapers/ar0x-apply-wallpapers \
             packages/ar0x-hypr-config/ar0x-apply-hypr-config ; do
        bash -n -- "${AR0X_SOURCE_ROOT}/${f}" || fail "bash -n failed: ${f}"
    done
    bash -n -- "${SCRIPT_DIR}/setup-repo.sh" || fail 'bash -n failed: setup-repo.sh'
    python3 - "${AR0X_SOURCE_ROOT}" <<'PYAST' || fail 'Python AST check failed'
import ast, os, sys
root = sys.argv[1]
for rel in ('tools/lib/ar0x_pkgbuild.py', 'tools/lib/ar0x_repo.py',
            'packages/ar0x-welcome/ar0x-welcome.py'):
    ast.parse(open(os.path.join(root, rel), encoding='utf-8').read(), filename=rel)
    print('[ OK ] Python AST: %s' % rel)
PYAST
    ok "8 bash executables + 8 PKGBUILDs + 2 scriptlets + 3 Python modules pass syntax gates"
}

check_ignores() {
    section "Derived key artifacts must stay OUT of Git"
    local f
    for f in packages/ar0x-keyring/ar0x-public-key.asc \
             packages/ar0x-keyring/ar0x.gpg \
             repo/x86_64/ar0x.db.tar.zst \
             build/repo-publish/x86_64/ar0x.db.tar.zst.sig ; do
        git -C "${AR0X_SOURCE_ROOT}" check-ignore --no-index -q -- "$f" \
            || fail "${f} is NOT gitignored — a key/db could be committed."
    done
    ok "4 derived key/db paths are gitignored (RISK-051)"
}

check_structure() {
    section "Phase 9 repository policy gates"
    python3 "${SCRIPT_DIR}/lib/ar0x_repo.py" "${AR0X_SOURCE_ROOT}" \
        || fail "tools/lib/ar0x_repo.py reported a structural error."
}

# --- Section 4: --self-test --------------------------------------------------
self_test() {
    section "Phase 9 offline self-test (mock signed repo)"
    python3 "${SCRIPT_DIR}/lib/ar0x_repo.py" "${AR0X_SOURCE_ROOT}" --self-test \
        || fail "ar0x_repo.py --self-test failed"
    [[ -x "${PREFIX}/usr/bin/ar0x-apply-theme" ]] \
        || die "Test prefix missing. Run ./tools/setup-repo.sh --sync first."
    local tmp; tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' RETURN

    # --list must be read-only and report the exact manifest counts.
    local n
    n="$(AR0X_THEME_REFDIR="${PREFIX}/usr/share/ar0x/theme" \
        "${PREFIX}/usr/bin/ar0x-apply-theme" --list | wc -l)"
    [[ "$n" == '7' ]] || fail "ar0x-apply-theme --list expected 7 files, got ${n}"
    n="$(AR0X_HYPR_REFDIR="${PREFIX}/usr/share/ar0x/hypr-config" \
        "${PREFIX}/usr/bin/ar0x-apply-hypr-config" --list | wc -l)"
    [[ "$n" == '14' ]] || fail "ar0x-apply-hypr-config --list expected 14, got ${n}"
    n="$(AR0X_WALL_REFDIR="${PREFIX}/usr/share/ar0x/wallpapers" \
        "${PREFIX}/usr/bin/ar0x-apply-wallpapers" --list | wc -l)"
    [[ "$n" == '3' ]] || fail "ar0x-apply-wallpapers --list expected 3, got ${n}"
    ok "3 ar0x-apply-* helpers: --list manifests 7 / 14 / 3 files (no writes)"

    # REAL applies into a throwaway HOME: assert ALL files land and are byte-equal.
    AR0X_THEME_REFDIR="${PREFIX}/usr/share/ar0x/theme" \
    AR0X_THEME_DESTDIR="${tmp}/config" "${PREFIX}/usr/bin/ar0x-apply-theme" >/dev/null
    AR0X_HYPR_REFDIR="${PREFIX}/usr/share/ar0x/hypr-config" \
    AR0X_HYPR_DESTDIR="${tmp}/config/hypr" "${PREFIX}/usr/bin/ar0x-apply-hypr-config" >/dev/null
    AR0X_WALL_REFDIR="${PREFIX}/usr/share/ar0x/wallpapers" \
    AR0X_WALL_DESTDIR="${tmp}/Pictures/ar0x" "${PREFIX}/usr/bin/ar0x-apply-wallpapers" >/dev/null
    [[ -f "${tmp}/config/gtk-4.0/gtk.css" ]] || fail 'theme applier did not install gtk-4.0/gtk.css'
    [[ -f "${tmp}/config/hypr/hyprland.lua" ]] || fail 'hypr applier did not install hyprland.lua'
    [[ -f "${tmp}/config/hypr/lua/keybinds.lua" ]] || fail 'hypr applier missed lua/keybinds.lua'
    cmp -s -- "${PREFIX}/usr/share/ar0x/wallpapers/ar0x-void.png" \
              "${tmp}/Pictures/ar0x/ar0x-void.png" || fail 'wallpaper copy not byte-identical'
    ok "3 appliers really copied 7 theme + 14 Lua + 3 wallpaper files into a temp HOME"

    # Backup-on-overwrite is a safety contract: change a dest, re-apply, check backup.
    printf 'local-edit\n' > "${tmp}/config/gtk-4.0/gtk.css"
    AR0X_THEME_REFDIR="${PREFIX}/usr/share/ar0x/theme" \
    AR0X_THEME_DESTDIR="${tmp}/config" "${PREFIX}/usr/bin/ar0x-apply-theme" >/dev/null
    find "${tmp}/config/ar0x-backups" -type f -name 'gtk.css' | grep -q . \
        || fail 'applier overwrote a local edit WITHOUT a backup'
    ok "applier created a timestamped backup before overwriting a local edit"

    "${SCRIPT_DIR}/configure-tools.sh" --self-test >/dev/null \
        || fail 'Phase 8 configure-tools.sh --self-test failed'
    ok "Phase 8 three-tool self-test chain still passes"
    assert_clean
    ok "Phase 9 --self-test PASSED (mock repo + 8 real helper runs + P8 chain)"
}

# --- Section 5: --verify -----------------------------------------------------
verify_repo() {
    section "Verifying repo tree: ${VERIFY_DIR}"
    python3 - "${VERIFY_DIR}" "${AR0X_SOURCE_ROOT}" <<'PYVERIFY' || fail "repo verification failed"
import os, sys
sys.path.insert(0, os.path.join(sys.argv[2], 'tools', 'lib'))
import ar0x_repo
d = sys.argv[1]
probs = ar0x_repo.repo_problems(d)
if probs:
    for problem in probs:
        sys.stderr.write("  - %s\n" % problem)
    sys.stderr.write("[FAIL] repo verification failed: %d problem(s)\n" % len(probs))
    sys.exit(1)
man = ar0x_repo.build_manifest(d)
print("[ OK ] %d files structurally verified (db + db.sig + packages + SHA256SUMS.sig)" % len(man))
PYVERIFY
}

# --- Section 6: MANUAL / root modes ------------------------------------------
keygen() {
    section "OFFLINE GPG RELEASE KEY GENERATION"
    warn '⚠️ This is PERMANENT: the fingerprint will be published and trusted by users.'
    warn '⚠️ Do this on an AIR-GAPPED host. Back up the private key OFFLINE.'
    warn '⚠️ NEVER commit the private key. It stays in ${AR0X_KEYS_DIR}/gnupg (0700).'
    if [[ "${AR0X_CONFIRM_KEYGEN:-}" != 'yes' ]]; then
        die 'Set AR0X_CONFIRM_KEYGEN=yes to acknowledge the risk and proceed.'
    fi
    require_command gpg
    export GNUPGHOME="${AR0X_KEYS_DIR}/gnupg"
    install -dm 0700 -- "$GNUPGHOME"
    if gpg --batch --with-colons --list-keys "$AR0X_REPO_KEY_UID" 2>/dev/null | grep -q '^pub:'; then
        die "A key for ${AR0X_REPO_KEY_UID} already exists in ${GNUPGHOME}. Refusing to overwrite."
    fi
    # NO --batch / --passphrase: gpg-agent prompts for a STRONG passphrase via
    # pinentry. An unprotected offline master key is a critical security bug.
    gpg --quick-generate-key "$AR0X_REPO_KEY_UID" \
        "$AR0X_REPO_KEY_ALGO" sign "$AR0X_REPO_KEY_EXPIRE"
    local fpr
    fpr="$(gpg --batch --with-colons --fingerprint "$AR0X_REPO_KEY_UID" \
           | awk -F: '$1=="fpr" {print $10; exit}')"
    [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || die "Could not read a 40-hex fingerprint (got '${fpr}')."
    printf '# Written by tools/setup-repo.sh --keygen on %s.\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT"
    printf '# ⚠️ Publish this fingerprint OUT OF BAND (README, website, keyserver).\n' \
        >> "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT"
    printf '%s\n' "$fpr" >> "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT"
    gpg --armor --export "$fpr" \
        > "${AR0X_SOURCE_ROOT}/packages/ar0x-keyring/ar0x-public-key.asc"
    chmod 0644 -- "${AR0X_SOURCE_ROOT}/packages/ar0x-keyring/ar0x-public-key.asc"
    ok "Key ${fpr} generated; public armored key written (gitignored *.asc)"
    warn 'MANUAL: review + COMMIT config/repo/RELEASE_KEY_FINGERPRINT, then run --sync.'
    warn 'MANUAL: publish the fingerprint out of band; keep the private key offline.'
}

build_packages() {
    section "Building all 8 ar0x packages with makepkg"
    warn '⚠️ Needs a REAL Arch host / archlinux:base-devel container, network, ~2 GiB.'
    warn '⚠️ makepkg --nodeps is REQUIRED (intra-repo depends do not exist yet).'
    warn '⚠️ NO automatic rollback. Output is UNSIGNED until --sign / release.yml.'
    if [[ "${AR0X_CONFIRM_BUILD:-}" != 'yes' ]]; then
        die 'Set AR0X_CONFIRM_BUILD=yes to acknowledge the risk and proceed.'
    fi
    require_command makepkg
    (( EUID != 0 )) || die 'makepkg refuses root. Run as a normal user (builder).'
    local pkg
    for pkg in "${ALL_PACKAGES[@]}"; do
        if [[ "$pkg" == 'ar0x-keyring' && \
              ! -f "${AR0X_PACKAGES_DIR}/ar0x-keyring/ar0x-public-key.asc" ]]; then
            die 'ar0x-public-key.asc missing: run --keygen first (MANUAL).'
        fi
        log "Building ${pkg} ..."
        ( cd -- "${AR0X_PACKAGES_DIR}/${pkg}" && \
            makepkg --nodeps --noconfirm --force ) || fail "makepkg failed: ${pkg}"
        if have_command namcap; then
            namcap "${AR0X_PACKAGES_DIR}/${pkg}/PKGBUILD" || warn "namcap advisories for ${pkg}"
        else
            warn "namcap absent; skipping advisory check for ${pkg}"
        fi
    done
    install -dm 0755 -- "$AR0X_REPO_DIR"
    cp -a -- "${AR0X_PACKAGES_DIR}"/*/*.pkg.tar.zst "$AR0X_REPO_DIR/"
    assert_clean
    ok "8 unsigned packages staged in ${AR0X_REPO_DIR}"
    printf '  Next: sudo ./tools/setup-repo.sh --sign   (⚠️ MANUAL, needs the private key)\n'
}

sign_repo() {
    section "Signing packages + repository database"
    warn '⚠️ Requires the OFFLINE private key in ${AR0X_KEYS_DIR}/gnupg and gpg-agent.'
    warn '⚠️ A bad signature published to users is a SECURITY INCIDENT. Verify first.'
    if [[ "${AR0X_CONFIRM_SIGN:-}" != 'yes' ]]; then
        die 'Set AR0X_CONFIRM_SIGN=yes to acknowledge the risk and proceed.'
    fi
    require_command gpg
    require_command repo-add
    export GNUPGHOME="${AR0X_KEYS_DIR}/gnupg"
    local fpr
    fpr="$(tail -1 "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT")"
    [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || die 'Run --keygen first (fingerprint is PENDING-KEYGEN).'
    local p
    for p in "$AR0X_REPO_DIR"/*.pkg.tar.zst; do
        [[ -f "$p" ]] || die "No packages in ${AR0X_REPO_DIR}; run --build first."
        gpg --yes --local-user "$fpr" --output "${p}.sig" --detach-sign "$p" \
            || fail "signature failed: ${p}"
    done
    # -s signs the db; -v verifies an existing db.sig before rewriting;
    # --include-sigs embeds the package signatures in the database.
    GPGKEY="$fpr" repo-add -s -v --include-sigs \
        "${AR0X_REPO_DIR}/${AR0X_REPO_DB}" "$AR0X_REPO_DIR"/*.pkg.tar.zst \
        || fail 'repo-add -s failed'
    ( cd -- "$AR0X_REPO_DIR" && sha256sum -- ./* > SHA256SUMS )
    gpg --yes --local-user "$fpr" --output "${AR0X_REPO_DIR}/SHA256SUMS.sig" \
        --detach-sign "${AR0X_REPO_DIR}/SHA256SUMS" || fail 'SHA256SUMS signature failed'
    assert_clean
    ok "Signed db + all packages + SHA256SUMS in ${AR0X_REPO_DIR}"
    printf '  Next: ./tools/setup-repo.sh --verify %s\n' "$AR0X_REPO_DIR"
}

publish_bundle() {
    section "Staging a publish bundle (NO UPLOAD)"
    install -dm 0755 -- "${PUBLISH_DIR}/x86_64"
    if ! compgen -G "${AR0X_REPO_DIR}/*.pkg.tar.zst" > /dev/null; then
        warn "No signed repo at ${AR0X_REPO_DIR}; nothing to stage."
        warn 'MANUAL: --keygen → --sync → --build → --sign → --publish.'
        printf '\n  rsync -av --delete %s/x86_64/ user@mirror:/srv/repo/x86_64/\n' "$PUBLISH_DIR"
        printf '  gh release create v0.1.0 %s/x86_64/* --generate-notes\n' "$PUBLISH_DIR"
        ok "Phase 9 --publish printed the MANUAL commands (no upload performed)"
        return 0
    fi
    cp -a -- "${AR0X_REPO_DIR}"/. "${PUBLISH_DIR}/x86_64/"
    python3 - "${PUBLISH_DIR}/x86_64" "${AR0X_SOURCE_ROOT}" <<'PYPUB' || fail 'publish bundle invalid'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[2], 'tools', 'lib'))
import ar0x_repo
d = sys.argv[1]
probs = ar0x_repo.repo_problems(d)
assert not probs, 'invalid publish bundle: %r' % probs
man = ar0x_repo.build_manifest(d)
print('[ OK ] publish bundle: %d files, all signatures present' % len(man))
PYPUB
    python3 - "${PUBLISH_DIR}/x86_64" "${AR0X_SOURCE_ROOT}" <<'PYMAN' || fail 'manifest generation failed'
import os, sys
sys.path.insert(0, os.path.join(sys.argv[2], 'tools', 'lib'))
import ar0x_repo
d = sys.argv[1]
man = ar0x_repo.build_manifest(d)
out = os.path.join(os.path.dirname(d), 'PUBLISH-MANIFEST.md')
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('# ar0x publish manifest (GENERATED, gitignored under /build/)\n\n')
    f.write('NEVER uploaded by setup-repo.sh. Publish manually after verifying fingerprints.\n\n')
    for name, digest in sorted(man.items()):
        f.write('%s  %s\n' % (digest, name))
print('[ OK ] %s' % out)
PYMAN
    warn '⚠️ MANUAL UPLOAD (Phase 12): DNS + TLS for repo.ar0x.dev must be live.'
    printf '\n  rsync -av --delete %s/x86_64/ user@mirror:/srv/repo/x86_64/\n' "$PUBLISH_DIR"
    printf '  gh release create v0.1.0 %s/x86_64/* --generate-notes\n' "$PUBLISH_DIR"
    printf '  # then verify: ./tools/setup-repo.sh --verify %s/x86_64\n' "$PUBLISH_DIR"
    ok "Phase 9 --publish staged ${PUBLISH_DIR} (NO upload performed)"
}

# --- Section 7: dispatch -----------------------------------------------------
case "$MODE" in
    check)
        warn 'RISK-051: private release key is MANUAL/offline; never in Git or PR CI.'
        warn 'RISK-048: signed [ar0x] db is NOT built here; publication is MANUAL.'
        warn 'RISK-049: makepkg/namcap/shellcheck/gpg/repo-add are absent in this sandbox.'
        check_files
        check_syntax
        check_ignores
        check_structure
        assert_clean
        ok "Phase 9 --check PASSED (no root, no writes)"
        ;;
    sync)       sync_all ;;
    selftest)   self_test ;;
    verify)     verify_repo ;;
    keygen)     keygen ;;
    build)      build_packages ;;
    sign)       sign_repo ;;
    publish)    publish_bundle ;;
esac

# FINAL GATE: `fail()` only increments AR0X_FAILURES. Every mode — including
# --verify and --publish, which delegate to Python — must return a NON-ZERO
# exit code if any check failed. Without this, CI would silently pass a broken
# repo tree.
assert_clean
