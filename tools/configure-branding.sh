#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/configure-branding.sh
# -----------------------------------------------------------------------------
# PHASE 7 — distribution identity + brand asset driver.
#
# Canonical sources (HUMAN-EDITED):
#   config/branding/**          /etc identity, palette.conf, ASCII, fetch cfgs
#   assets/logo/**              SVG masters (authoritative geometry) + LICENSE
#   assets/icons/**             icon-theme variant (LOGO=ar0x-logo)
#   assets/cursors/**           XCursor theme metadata
#   assets/grub-theme/**, assets/plymouth/**, assets/syslinux/**  boot art
# Generated mirrors (NEVER EDIT BY HAND):
#   archiso/airootfs/etc/{os-release,lsb-release,issue,issue.net,motd}
#   archiso/airootfs/usr/lib/os-release
#   archiso/airootfs/etc/skel/.config/{fastfetch,neofetch}/**
#   config/desktop/skel/.config/{fastfetch,neofetch}/**   (Phase 6 tree)
#   archiso/airootfs/usr/share/ar0x/{branding,logo}/**
#   archiso/airootfs/usr/share/icons/**
#   archiso/airootfs/usr/local/bin/ar0x-screenfetch
#
# Modes (same contract as configure-system.sh / configure-desktop.sh):
#   --check   Read-only validation. NO root, NO writes. (default)
#   --sync    Install canonical -> generated mirrors. NO root, byte-idempotent.
#   --apply   ⚠️ MANUAL, ROOT, FINISHED AIROOTFS ONLY: icon cache, Plymouth
#             theme selection (REBUILDS INITRAMFS), grub-mkconfig, fetch smoke
#             tests. Never run this in a build sandbox.
#
# ⚠️ RISK-010: neofetch was REMOVED from Arch [extra] and is AUR-only. Its
#    config IS shipped, but the package is NOT on the ISO. screenfetch 3.9.9-1
#    IS in [extra] and IS on the ISO.
# ⚠️ RISK-044: no Wayland compositor, X server, Plymouth, GRUB gfxmenu or
#    live session was rendered in this sandbox. All validation here is
#    structural + format-level (we parse every SVG, PNG and Xcursor back).
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BRAND="${AR0X_CONFIG_DIR}/branding"
SKEL="${AR0X_CONFIG_DIR}/desktop/skel"
PROFILE="${AR0X_PROFILE}"
AIROOTFS="${PROFILE}/airootfs"
BRAND_SHARE="${AIROOTFS}/usr/share/ar0x/branding"
BRAND_LOGO="${AIROOTFS}/usr/share/ar0x/logo"
ICON_APPS="${AIROOTFS}/usr/share/icons/hicolor/scalable/apps"
CURSOR_THEME="${AIROOTFS}/usr/share/icons/ar0x-cursors"
LOG_FILE="${AR0X_LOG_DIR}/06-branding-config.log"

MODE="check"

usage() {
    cat <<'USAGE'
ar0x Phase 7 — configure-branding.sh

  --check   Read-only validation (default). No root, no writes.
  --sync    Install canonical branding into config/desktop/skel/.config/ and
            the archiso/airootfs profile. No root, byte-idempotent.
  --apply   ⚠️ ROOT + FINISHED AIROOTFS: icon cache, Plymouth theme (rebuilds
            initramfs), grub-mkconfig and fetch smoke tests.
  -h|--help This help.

Typical order on a real Arch host:
  ./tools/gen-branding-assets.sh
  ./tools/gen-theme-assets.sh
  ./tools/configure-branding.sh --check
  ./tools/configure-branding.sh --sync
  ./tools/build-kernel.sh --sync
  ./tools/configure-desktop.sh --sync
  ./tools/bootstrap.sh --check
  sudo ./tools/bootstrap.sh --iso-only
  sudo ./tools/configure-branding.sh --apply
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

# --- Section 1: canonical inventory ------------------------------------------
IDENTITY=(os-release lsb-release issue issue.net motd)
CANONICAL=(
    config/branding/os-release config/branding/lsb-release
    config/branding/issue config/branding/issue.net config/branding/motd
    config/branding/palette.conf
    config/branding/ascii/ar0x-ascii.txt
    config/branding/ascii/ar0x-fastfetch.txt
    config/branding/ascii/ar0x-screenfetch.sh
    config/branding/fastfetch/config.jsonc
    config/branding/neofetch/config.conf
    config/branding/screenfetch/ar0x-screenfetch.sh
    assets/logo/ar0x-logo.svg assets/logo/ar0x-logo-mono.svg
    assets/logo/ar0x-wordmark.svg assets/logo/LICENSE
    assets/logo/ar0x-logo-256.png assets/logo/ar0x-logo-512.png
    assets/icons/ar0x-logo.svg assets/icons/README.md
    assets/cursors/ar0x-cursors/index.theme
    assets/cursors/ar0x-cursors/cursor.theme
    assets/cursors/ar0x-cursors/README.md
    assets/ascii/README.md
    assets/grub-theme/ar0x/theme.txt assets/grub-theme/ar0x/background.png
    assets/plymouth/ar0x/ar0x.plymouth assets/plymouth/ar0x/ar0x.script
    assets/plymouth/ar0x/logo.png assets/syslinux/splash.png
    tools/lib/ar0x_logo.py tools/lib/ar0x_xcursor.py
    tools/gen-branding-assets.sh tools/gen-theme-assets.sh
    tools/configure-branding.sh docs/BRANDING_GUIDE.md
)

pkg_in_list() {
    sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' \
        "${AR0X_CONFIG_DIR}/packages.x86_64" | grep -Fxq -- "$1"
}

# --- Section 2: --sync (no root) ---------------------------------------------
# `install -D -m` creates parents and sets an explicit mode; no `cp -r` on
# directories, so this is deterministic and byte-idempotent across runs.
sync_profile() {
    section "Installing Phase 7 branding into the archiso profile"

    # 2a. /etc identity. /usr/lib/os-release is written too: Arch's `filesystem`
    # package makes /etc/os-release a SYMLINK to it. Writing both avoids a
    # package upgrade silently reverting the identity to "Arch Linux".
    local f
    for f in "${IDENTITY[@]}"; do
        install -D -m 0644 -- "${BRAND}/${f}" "${AIROOTFS}/etc/${f}"
    done
    install -D -m 0644 -- "${BRAND}/os-release" "${AIROOTFS}/usr/lib/os-release"
    ok "5 /etc identity files + /usr/lib/os-release"

    # 2b. Fetch configs: canonical -> Phase 6 skel tree -> /etc/skel.
    # Both copies are written so configure-desktop.sh --check (diff -qr) and
    # configure-branding.sh --check (cmp -s) agree regardless of run order.
    install -D -m 0644 -- "${BRAND}/fastfetch/config.jsonc" \
        "${SKEL}/.config/fastfetch/config.jsonc"
    install -D -m 0644 -- "${BRAND}/fastfetch/config.jsonc" \
        "${AIROOTFS}/etc/skel/.config/fastfetch/config.jsonc"
    install -D -m 0644 -- "${BRAND}/neofetch/config.conf" \
        "${SKEL}/.config/neofetch/config.conf"
    install -D -m 0644 -- "${BRAND}/neofetch/config.conf" \
        "${AIROOTFS}/etc/skel/.config/neofetch/config.conf"
    ok "fastfetch + neofetch configs (canonical, skel, /etc/skel)"

    # 2c. System-wide brand assets. Absolute /usr/share paths are intentional:
    # /etc/skel is copied into every home, so a relative source would break.
    for f in ar0x-ascii.txt ar0x-fastfetch.txt ar0x-screenfetch.sh; do
        install -D -m 0644 -- "${BRAND}/ascii/${f}" "${BRAND_SHARE}/${f}"
    done
    install -D -m 0644 -- "${BRAND}/palette.conf" \
        "${AIROOTFS}/usr/share/ar0x/palette.conf"
    for f in ar0x-logo.svg ar0x-logo-mono.svg ar0x-wordmark.svg LICENSE; do
        install -D -m 0644 -- "${AR0X_ASSETS_DIR}/logo/${f}" "${BRAND_LOGO}/${f}"
    done
    install -D -m 0644 -- "${AR0X_ASSETS_DIR}/icons/ar0x-logo.svg" \
        "${ICON_APPS}/ar0x-logo.svg"
    install -D -m 0644 -- "${BRAND}/screenfetch/ar0x-screenfetch.sh" \
        "${AIROOTFS}/usr/local/bin/ar0x-screenfetch"
    chmod 0755 -- "${AIROOTFS}/usr/local/bin/ar0x-screenfetch"
    ok "branding share, SVG masters, LOGO icon, ar0x-screenfetch wrapper"

    # 2d. XCursor theme metadata. The binary cursors/ tree is generated by
    # tools/gen-branding-assets.sh, NOT by --sync.
    for f in index.theme cursor.theme; do
        install -D -m 0644 -- "${AR0X_ASSETS_DIR}/cursors/ar0x-cursors/${f}" \
            "${CURSOR_THEME}/${f}"
    done
    ok "ar0x-cursors index.theme + cursor.theme"

    log "Boot art (GRUB/Plymouth/syslinux) is propagated by tools/build-kernel.sh --sync."
    log "bootstrap.sh additionally overlays config/branding/* into its disposable STAGE."
}

# --- Section 3: --check (read-only) ------------------------------------------
assert_pair() {
    local a="$1" b="$2" label="$3"
    [[ -f "$a" && -f "$b" ]] || { fail "Missing generated pair: ${label}"; return 0; }
    cmp -s -- "$a" "$b" || fail "Stale generated copy: ${label} — run --sync."
}

validate() {
    section "Validating Phase 7 branding (read-only)"

    # 3a. Canonical inventory.
    local f
    for f in "${CANONICAL[@]}"; do
        [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] && ok "$f" \
            || fail "Missing Phase 7 deliverable: ${f}"
    done

    # 3b. Generated mirrors (byte-identical, not just present).
    for f in "${IDENTITY[@]}"; do
        assert_pair "${BRAND}/${f}" "${AIROOTFS}/etc/${f}" "etc/${f}"
    done
    assert_pair "${BRAND}/os-release" "${AIROOTFS}/usr/lib/os-release" \
                "usr/lib/os-release"
    assert_pair "${BRAND}/fastfetch/config.jsonc" \
                "${SKEL}/.config/fastfetch/config.jsonc" "skel fastfetch"
    assert_pair "${BRAND}/fastfetch/config.jsonc" \
                "${AIROOTFS}/etc/skel/.config/fastfetch/config.jsonc" "/etc/skel fastfetch"
    assert_pair "${BRAND}/neofetch/config.conf" \
                "${SKEL}/.config/neofetch/config.conf" "skel neofetch"
    assert_pair "${BRAND}/neofetch/config.conf" \
                "${AIROOTFS}/etc/skel/.config/neofetch/config.conf" "/etc/skel neofetch"
    for f in ar0x-ascii.txt ar0x-fastfetch.txt ar0x-screenfetch.sh; do
        assert_pair "${BRAND}/ascii/${f}" "${BRAND_SHARE}/${f}" "branding/${f}"
    done
    assert_pair "${BRAND}/palette.conf" \
                "${AIROOTFS}/usr/share/ar0x/palette.conf" "usr/share/ar0x/palette.conf"
    assert_pair "${AR0X_ASSETS_DIR}/icons/ar0x-logo.svg" \
                "${ICON_APPS}/ar0x-logo.svg" "LOGO icon"
    for f in ar0x-logo.svg ar0x-logo-mono.svg ar0x-wordmark.svg LICENSE; do
        assert_pair "${AR0X_ASSETS_DIR}/logo/${f}" "${BRAND_LOGO}/${f}" "logo/${f}"
    done
    for f in index.theme cursor.theme; do
        assert_pair "${AR0X_ASSETS_DIR}/cursors/ar0x-cursors/${f}" \
                    "${CURSOR_THEME}/${f}" "ar0x-cursors/${f}"
    done
    assert_pair "${BRAND}/screenfetch/ar0x-screenfetch.sh" \
                "${AIROOTFS}/usr/local/bin/ar0x-screenfetch" "ar0x-screenfetch"
    ok "All generated branding mirrors are byte-identical"

    # 3c. os-release / lsb-release / issue / motd contracts.
    python3 - "$BRAND" "$AR0X_SOURCE_ROOT" <<'PY' || fail "Identity file validation failed."
import os, re, sys
brand, root = sys.argv[1], sys.argv[2]

def kv(path):
    out = {}
    for line in open(path, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition('=')
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out

osr = kv(os.path.join(brand, 'os-release'))
required = ('NAME', 'PRETTY_NAME', 'ID', 'ID_LIKE', 'VERSION', 'VERSION_ID',
            'VERSION_CODENAME', 'ANSI_COLOR', 'LOGO', 'HOME_URL',
            'BUG_REPORT_URL')
for k in required:
    assert k in osr and osr[k], 'os-release missing ' + k
assert osr['ID'] == 'ar0x', 'ID must be ar0x, got ' + osr['ID']
assert osr['ID_LIKE'] == 'arch', 'ID_LIKE must be arch'
env = open(os.path.join(root, 'config/versions.env'), encoding='utf-8').read()
ver = re.search(r'^AR0X_VERSION="([^"]+)"', env, re.M).group(1)
assert osr['VERSION_ID'] == ver, 'VERSION_ID != AR0X_VERSION'
assert osr['LOGO'] == 'ar0x-logo', 'LOGO must name the shipped icon'
assert re.fullmatch(r'[a-z0-9-]+', osr['VERSION_CODENAME']), \
    'VERSION_CODENAME must be a lowercase identifier without spaces'
assert osr['PRETTY_NAME'].startswith('ar0x '), 'PRETTY_NAME must start with ar0x'
assert not re.search(r'\$\{?\w+\}?', open(os.path.join(brand, 'os-release')).read()), \
    'os-release must not contain variable expansion'
print('[ OK ] os-release: 11 required keys, ID=ar0x, LOGO=ar0x-logo, version parity')

lsb = kv(os.path.join(brand, 'lsb-release'))
assert lsb.get('DISTRIB_ID') == 'ar0x'
assert lsb.get('DISTRIB_RELEASE') == ver
print('[ OK ] lsb-release: DISTRIB_ID/RELEASE agree with versions.env')

# agetty(8) escape whitelist. Anything else is printed literally or stripped
# depending on the util-linux build, so /etc/issue must use ONLY these.
allowed = set('smrnldtvbouU')
issue = open(os.path.join(brand, 'issue'), encoding='utf-8').read()
escapes = set(re.findall(r'\\([A-Za-z0-9])', issue))
bad = escapes - allowed
assert not bad, 'unsupported /etc/issue escape(s): ' + ', '.join(sorted(bad))
assert escapes, '/etc/issue has no agetty escapes'
issuenet = open(os.path.join(brand, 'issue.net'), encoding='utf-8').read()
assert '\\' not in issuenet, 'issue.net is NOT expanded by agetty: keep it plain'
motd = open(os.path.join(brand, 'motd'), encoding='utf-8').read()
assert 'ar0x' in motd and 'github.com/ar0x1/ar0xOS' in motd
print('[ OK ] issue escapes %s / issue.net plain / motd branded' %
      ''.join(sorted(escapes)))

# palette.conf <-> versions.env parity (ADR-015), all 8 pins.
pal = dict(re.findall(r'^AR0X_BRAND_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
                      open(os.path.join(brand, 'palette.conf'), encoding='utf-8').read(), re.M))
pins = dict(re.findall(r'^AR0X_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
                       env, re.M))
assert len(pal) == 8 and pal == pins, 'palette.conf drift: %r != %r' % (pal, pins)
print('[ OK ] palette.conf: 8/8 hex pins match config/versions.env')
PY

    # 3d. ASCII art parity + fetch config contracts.
    python3 - "$BRAND" "$AR0X_SOURCE_ROOT" <<'PY' || fail "ASCII / fetch config validation failed."
import json, os, re, sys
brand, root = sys.argv[1], sys.argv[2]
plain = open(os.path.join(brand, 'ascii/ar0x-ascii.txt'), encoding='utf-8').read()
tagged = open(os.path.join(brand, 'ascii/ar0x-fastfetch.txt'), encoding='utf-8').read()
assert re.sub(r'\$[1-9]', '', tagged) == plain, \
    'fastfetch art must equal the plain art after removing $1..$9'
lines = plain.rstrip('\n').splitlines()
assert len(lines) == 8, 'ASCII art must be 8 lines'
assert max(map(len, lines)) <= 48, 'ASCII art exceeds 48 columns'
assert all('\t' not in l for l in lines), 'tabs are not allowed in ASCII art'
ph = set(re.findall(r'\$([1-9])', tagged))
assert ph and ph <= {'1', '2', '3'}, 'unexpected colour placeholders: %r' % ph
print('[ OK ] ASCII: 8 lines, <=48 cols, $%s placeholders, tagged/plain byte-parity' %
      ','.join(sorted(ph)))

def strip_jsonc(s):
    out, in_str, esc, i = [], False, False, 0
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == '/' and i + 1 < len(s) and s[i+1] == '/':
            i += 2
            while i < len(s) and s[i] != '\n': i += 1
            continue
        if c == '/' and i + 1 < len(s) and s[i+1] == '*':
            i += 2
            while i + 1 < len(s) and not (s[i] == '*' and s[i+1] == '/'): i += 1
            i += 2; continue
        out.append(c); i += 1
    return ''.join(out)

ff = json.loads(strip_jsonc(open(os.path.join(brand, 'fastfetch/config.jsonc'),
                                encoding='utf-8').read()))
logo = ff['logo']
assert logo['type'] == 'file', 'logo.type must be "file" for $1..$9 expansion'
assert logo['source'] == '/usr/share/ar0x/branding/ar0x-fastfetch.txt', \
    'logo.source must be the installed absolute path'
assert set(logo['color']) >= ph, 'logo.color does not cover every placeholder'
assert 'builtin' not in json.dumps(ff), 'Phase 6 builtin logo still present'
assert '"arch"' not in json.dumps(ff), 'Phase 6 "arch" logo still present'
assert isinstance(ff.get('modules'), list) and 'os' in ff['modules']
print('[ OK ] fastfetch JSONC parses: type=file, source absolute, colours %s' %
      ','.join(sorted(logo['color'])))

neo = open(os.path.join(brand, 'neofetch/config.conf'), encoding='utf-8').read()
assert re.search(r'^image_backend="ascii"$', neo, re.M)
assert '/usr/share/ar0x/branding/ar0x-ascii.txt' in neo
assert not re.search(r'^\s*set\s+-euo', neo, re.M), 'neofetch config is SOURCED: no strict mode'
print('[ OK ] neofetch config: ascii backend + official plain art')

# Default theme must no longer be the Phase 6 placeholder.
envlua = open(os.path.join(root, 'config/desktop/hypr/lua/env.lua'), encoding='utf-8').read()
envd = open(os.path.join(root, 'config/desktop/etc/environment.d/20-ar0x-desktop.conf'),
            encoding='utf-8').read()
idx = open(os.path.join(root, 'config/desktop/skel/.icons/default/index.theme'),
           encoding='utf-8').read()
assert 'hl.env("XCURSOR_THEME", "ar0x-cursors")' in envlua, 'RISK-040 not closed in env.lua'
assert re.search(r'^XCURSOR_THEME=ar0x-cursors$', envd, re.M), 'RISK-040 not closed in environment.d'
assert re.search(r'^Inherits=ar0x-cursors$', idx, re.M), 'RISK-040 not closed in .icons/default'
print('[ OK ] RISK-040: XCURSOR_THEME=ar0x-cursors in Lua, environment.d and skel')
PY

    # 3e. screenfetch sourced art: syntax + exactly one %s per fulloutput line.
    bash -n "${BRAND}/ascii/ar0x-screenfetch.sh" \
        || fail "ar0x-screenfetch.sh has a bash syntax error."
    grep -Eq '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail' \
        "${BRAND}/ascii/ar0x-screenfetch.sh" \
        && fail "ar0x-screenfetch.sh is SOURCED by screenfetch; strict mode would break it." \
        || ok "ar0x-screenfetch.sh is a strict-mode-exempt sourced snippet"
    bash -c '
        source "$1" || exit 1
        [[ "${startline}" == "0" && -n "${logowidth}" ]] || exit 2
        (( ${#fulloutput[@]} == 8 )) || exit 3
        for line in "${fulloutput[@]}"; do
            n="$(printf "%s" "$line" | tr -cd "%" | wc -c)"
            [[ "$n" -eq 1 ]] || exit 4
            [[ "$line" == *"%s" ]] || exit 5
        done
        [[ -n "${c1}" && -n "${c2}" && -n "${c3}" ]] || exit 6
    ' _ "${BRAND}/ascii/ar0x-screenfetch.sh" \
        || fail "screenfetch fulloutput contract violated (8 lines, one %s each)."
    ok "screenfetch art: 8 printf lines, exactly one %s each, 3 brand colours"

    # 3f. SVG geometry == tools/lib/ar0x_logo.py == palette; XML well-formed.
    python3 - "$AR0X_SOURCE_ROOT" <<'PY' || fail "SVG / PNG validation failed."
import os, re, struct, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, 'tools', 'lib'))
import ar0x_logo as L

rgb, pins = L.load_palette(root)
SVG = '{http://www.w3.org/2000/svg}'
def load(rel):
    return ET.parse(os.path.join(root, rel)).getroot()

master = load('assets/logo/ar0x-logo.svg')
assert master.get('viewBox') == L.VIEWBOX == '0 0 512 512'
poly = master.find(SVG + 'polygon')
assert poly is not None and poly.get('stroke-width') == str(L.OCTAGON_STROKE)
pts = [tuple(map(int, p.split(','))) for p in poly.get('points').split()]
assert tuple(pts) == L.OCTAGON, 'SVG octagon != ar0x_logo.OCTAGON'
pline = master.find(SVG + 'polyline')
assert tuple(tuple(map(int, p.split(','))) for p in pline.get('points').split()) == L.CHEVRON
assert pline.get('stroke-width') == str(L.GLYPH_STROKE)
line = master.find(SVG + 'line')
assert (int(line.get('x1')), int(line.get('y1')),
        int(line.get('x2')), int(line.get('y2'))) == (
        L.UNDERSCORE[0][0], L.UNDERSCORE[0][1],
        L.UNDERSCORE[1][0], L.UNDERSCORE[1][1])
rect = master.find(SVG + 'rect')
assert (int(rect.get('x')), int(rect.get('y')),
        int(rect.get('width')), int(rect.get('height'))) == L.NODE_RECT
text = open(os.path.join(root, 'assets/logo/ar0x-logo.svg'), encoding='utf-8').read()
for key in ('CYAN', 'MAGENTA', 'LIME'):
    assert pins[key] in text, 'master SVG missing ' + pins[key]
print('[ OK ] ar0x-logo.svg: XML valid, viewBox 0 0 512 512, geometry == ar0x_logo.py')

mono = load('assets/logo/ar0x-logo-mono.svg')
assert mono.get('viewBox') == L.VIEWBOX
monotext = open(os.path.join(root, 'assets/logo/ar0x-logo-mono.svg'), encoding='utf-8').read()
assert 'currentColor' in monotext and '#00E5FF' not in monotext, \
    'mono variant must be single-colour'
wordmark = load('assets/logo/ar0x-wordmark.svg')
assert wordmark.get('viewBox') == L.WORDMARK_VIEWBOX == '0 0 1024 256'
icon = load('assets/icons/ar0x-logo.svg')
assert icon.get('viewBox') == L.VIEWBOX
print('[ OK ] mono / wordmark / icon SVGs: XML valid, exact viewBoxes')

for size in (256, 512):
    p = os.path.join(root, 'assets/logo/ar0x-logo-%d.png' % size)
    with open(p, 'rb') as fh: head = fh.read(24)
    assert head[:8] == b'\x89PNG\r\n\x1a\n', 'bad PNG signature'
    assert struct.unpack('>II', head[16:24]) == (size, size), 'bad PNG IHDR'
print('[ OK ] 2 logo PNGs: signature + IHDR 256x256 / 512x512')
PY

    # 3g. XCursor binaries parsed back + alias symlinks.
    python3 - "$CURSOR_THEME" "$AR0X_SOURCE_ROOT" <<'PY' || fail "XCursor theme validation failed."
import os, sys
theme, root = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, 'tools', 'lib'))
from ar0x_xcursor import SHAPES, ALIASES, SIZES, verify_xcursor
cur = os.path.join(theme, 'cursors')
for name in sorted(SHAPES):
    p = os.path.join(cur, name)
    assert os.path.isfile(p), 'missing authored cursor: ' + name
    assert verify_xcursor(p, SIZES) == len(SIZES), 'bad Xcursor: ' + name
for alias, target in sorted(ALIASES.items()):
    p = os.path.join(cur, alias)
    assert os.path.islink(p) and os.readlink(p) == target, 'bad alias: ' + alias
print('[ OK ] XCursor: %d files x %d sizes parsed back, %d aliases' %
      (len(SHAPES), len(SIZES), len(ALIASES)))
PY

    # 3h. Boot art finalisation + package gates.
    grep -Fq 'PHASE 7' "${AR0X_ASSETS_DIR}/grub-theme/ar0x/theme.txt" \
        || fail "GRUB theme.txt was not finalised by Phase 7."
    grep -Fq 'top = 34%' "${AR0X_ASSETS_DIR}/grub-theme/ar0x/theme.txt" \
        || fail "GRUB boot_menu layout collides with the Phase 7 logomark."
    grep -Fq 'desktop-image:' "${AR0X_ASSETS_DIR}/grub-theme/ar0x/theme.txt" \
        || fail "GRUB theme.txt lost desktop-image."
    grep -Fq 'PHASE 7' "${AR0X_ASSETS_DIR}/plymouth/ar0x/ar0x.script" \
        || fail "Plymouth script was not finalised by Phase 7."
    ok "Phase 7 finalised GRUB theme, Plymouth splash and syslinux splash"

    pkg_in_list screenfetch || fail "screenfetch (Arch [extra] 3.9.9-1) missing from config/packages.x86_64."
    pkg_in_list neofetch \
        && fail "RISK-010: neofetch is AUR-only; it must NOT be in the ISO package list." \
        || ok "Package gate: screenfetch present, neofetch absent (RISK-010)"
    pkg_in_list fastfetch || fail "fastfetch missing from config/packages.x86_64."

    # No stale Phase 6 builtin arch logo anywhere in the fetch configs.
    if grep -rFq '"source": "arch"' \
            "${BRAND}/fastfetch" "${SKEL}/.config/fastfetch" \
            "${AIROOTFS}/etc/skel/.config/fastfetch" 2>/dev/null; then
        fail "Phase 6 builtin 'arch' fastfetch logo is still present."
    else
        ok "Zero stale Phase 6 builtin 'arch' logos"
    fi

    # The screenfetch wrapper must be executable and strict-mode compliant.
    [[ -x "${AIROOTFS}/usr/local/bin/ar0x-screenfetch" ]] \
        || fail "ar0x-screenfetch wrapper is not executable in the profile."
    head -n 1 "${BRAND}/screenfetch/ar0x-screenfetch.sh" | grep -Fxq '#!/bin/bash' \
        || fail "ar0x-screenfetch wrapper missing #!/bin/bash."
    grep -Eq '^set -euo pipefail$' "${BRAND}/screenfetch/ar0x-screenfetch.sh" \
        || fail "ar0x-screenfetch wrapper missing strict mode."
    ok "ar0x-screenfetch wrapper: strict mode + executable"
}

# --- Section 4: --apply (ROOT, manual) ---------------------------------------
# ⚠️ RISKY STEP: `plymouth-set-default-theme -R ar0x` REBUILDS the initramfs,
#    and `grub-mkconfig` REWRITES /boot/grub/grub.cfg. Both require a finished
#    airootfs with a real linux-lts kernel and mounted /boot. Never run in the
#    source checkout or a build sandbox. There is NO automatic rollback.
apply_in_chroot() {
    section "Applying Phase 7 branding inside ${AIROOTFS} (MANUAL, ROOT)"
    require_root
    require_command arch-chroot
    [[ -d "$AIROOTFS" ]] || die "airootfs not found: ${AIROOTFS}"

    warn "⚠️  MANUAL INTERVENTION REQUIRED — read docs/BRANDING_GUIDE.md §7 first."
    warn "⚠️  This rebuilds the initramfs AND rewrites /boot/grub/grub.cfg."
    warn "⚠️  Ensure /boot is mounted and linux-lts ${AR0X_KERNEL_VERSION} is installed."

    install -d -m 0755 -- "$AR0X_LOG_DIR"

    log "gtk-update-icon-cache (makes LOGO=ar0x-logo resolvable)"
    arch-chroot "$AIROOTFS" /usr/bin/gtk-update-icon-cache -f -t \
        /usr/share/icons/hicolor 2>&1 | tee -a "$LOG_FILE"

    log "plymouth-set-default-theme -R ar0x (⚠️ runs mkinitcpio -P)"
    arch-chroot "$AIROOTFS" /usr/bin/plymouth-set-default-theme -R ar0x \
        2>&1 | tee -a "$LOG_FILE"

    log "grub-mkconfig (regenerates /boot/grub/grub.cfg with GRUB_THEME)"
    arch-chroot "$AIROOTFS" /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg \
        2>&1 | tee -a "$LOG_FILE"

    log "Identity smoke tests"
    arch-chroot "$AIROOTFS" /usr/bin/bash -c \
        '. /etc/os-release; printf "%s %s %s\n" "$NAME" "$VERSION_ID" "$LOGO"' \
        2>&1 | tee -a "$LOG_FILE"
    arch-chroot "$AIROOTFS" /usr/bin/fastfetch --show-errors \
        2>&1 | tee -a "$LOG_FILE"
    arch-chroot "$AIROOTFS" /usr/bin/screenfetch \
        -a /usr/share/ar0x/branding/ar0x-screenfetch.sh 2>&1 | tee -a "$LOG_FILE"

    ok "Phase 7 applied in chroot (log: ${LOG_FILE})"
}

# --- Section 5: dispatch -----------------------------------------------------
cd "$AR0X_SOURCE_ROOT"
warn "RISK-044: no live Wayland/GRUB/Plymouth session was rendered in this sandbox."
case "$MODE" in
    check)
        validate
        assert_clean
        ok "Phase 7 --check PASSED (no root, no writes)"
        printf '\nNext steps on a real Arch host:\n'
        printf '  ./tools/gen-branding-assets.sh\n'
        printf '  ./tools/gen-theme-assets.sh\n'
        printf '  ./tools/configure-branding.sh --sync\n'
        printf '  ./tools/build-kernel.sh --sync\n'
        printf '  ./tools/configure-desktop.sh --sync\n'
        ;;
    sync)
        sync_profile
        validate
        assert_clean
        ok "Phase 7 --sync PASSED (profile mirrors installed)"
        ;;
    apply)
        apply_in_chroot
        ;;
esac
