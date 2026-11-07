#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/configure-desktop.sh
# -----------------------------------------------------------------------------
# PHASE 6 — Hyprland / Wayland desktop + complete theme driver.
#
# Canonical sources live in config/desktop/** and assets/{sddm,wallpapers}/.
# This script has three modes (same contract as Phase 5's configure-system.sh):
#   --check   Read-only validation. NO root, NO writes. (default)
#   --sync    1) render canonical tool configs into config/desktop/skel/.config/**
#             2) mirror config/desktop/skel/** -> archiso/airootfs/etc/skel/**
#             3) mirror config/desktop/etc/**  -> archiso/airootfs/etc/**
#             4) mirror theme art -> archiso/airootfs/usr/share/**
#             NO root. All copies are deterministic and byte-idempotent.
#   --apply   ⚠️ MANUAL, ROOT: font/desktop caches + `systemctl preset-all`
#             + `Hyprland --verify-config` inside the airootfs chroot.
#
# ⚠️ RISK-002: Hyprland 0.57 REMOVED hyprland.conf. Lua is MANDATORY, there is
#    NO converter, and `hyprctl keyword` is disabled. --check fails on any file
#    named hyprland.conf anywhere in the source tree.
# ⚠️ RISK-040: Adwaita cursor + generated PNG wallpapers are PLACEHOLDERS.
#    Phase 7 replaces them with the official ar0x hyprcursor theme / final art.
# ⚠️ This sandbox has no Hyprland, SDDM greeter, QEMU/KVM, root or display, so
#    NO live desktop session was rendered here. See docs/DESKTOP_GUIDE.md §8.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DESK="${AR0X_CONFIG_DIR}/desktop"
SKEL="${DESK}/skel"
ETC="${DESK}/etc"
HYPR="${DESK}/hypr"
PROFILE="${AR0X_PROFILE}"
AIROOTFS="${AR0X_WORK_DIR}/x86_64/airootfs"
PRESET="${AR0X_CONFIG_DIR}/system/systemd/system-preset/50-ar0x.preset"
LOG_FILE="${AR0X_LOG_DIR}/05-desktop-config.log"

MODE="check"

usage() {
    cat <<'USAGE'
ar0x Phase 6 — configure-desktop.sh

  --check   Read-only validation (default). No root, no writes.
  --sync    Regenerate config/desktop/skel/.config/** and the archiso/ profile
            copies from the canonical configs. No root.
  --apply   ⚠️ ROOT: font caches, desktop database, preset-all and
            `Hyprland --verify-config` inside the airootfs chroot.
  -h|--help This help.

Typical order on a real Arch host:
  ./tools/gen-desktop-assets.sh
  ./tools/configure-desktop.sh --check
  ./tools/configure-desktop.sh --sync
  sudo ./tools/bootstrap.sh --iso-only
  sudo ./tools/configure-desktop.sh --apply
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
# Every path is relative to config/desktop/ or assets/. These are the HUMAN-
# EDITED files. Anything under skel/.config/{hypr,waybar,gtk-*,qt*ct,...} is a
# GENERATED COPY and must never be edited by hand.
CANONICAL=(
    hypr/hyprland.lua
    hypr/lua/palette.lua hypr/lua/programs.lua hypr/lua/env.lua
    hypr/lua/monitors.lua hypr/lua/looknfeel.lua hypr/lua/animations.lua
    hypr/lua/input.lua hypr/lua/keybinds.lua hypr/lua/rules.lua
    hypr/lua/autostart.lua
    hypr/hyprpaper.conf hypr/hyprlock.conf hypr/hypridle.conf
    waybar/config.jsonc waybar/style.css
    gtk-3.0/settings.ini gtk-3.0/gtk.css
    gtk-4.0/settings.ini gtk-4.0/gtk.css
    qt5ct/qt5ct.conf qt6ct/qt6ct.conf
    fontconfig/conf.d/99-ar0x-fonts.conf
    kitty/kitty.conf wofi/config wofi/style.css mako/config
    xdg/mimeapps.list
    etc/sddm.conf.d/10-ar0x.conf
    etc/environment.d/20-ar0x-desktop.conf
    etc/xdg/user-dirs.defaults
    skel/.zshenv skel/.zshrc skel/.zprofile skel/.profile skel/.bashrc
    skel/.config/starship.toml skel/.config/git/config
    skel/.config/fastfetch/config.jsonc skel/.config/user-dirs.dirs
    skel/.config/xdg-desktop-portal/hyprland-portals.conf
    skel/.icons/default/index.theme
)
THEME_FILES=(
    assets/sddm/ar0x/metadata.desktop
    assets/sddm/ar0x/theme.conf
    assets/sddm/ar0x/Main.qml
    assets/sddm/ar0x/background.png
    assets/wallpapers/ar0x-neon-grid.png
    assets/wallpapers/ar0x-void.png
    assets/wallpapers/ar0x-circuit.png
    assets/wallpapers/PLACEHOLDERS.md
)

# source subdir -> generated destination under skel/.config/
RENDER_DIRS=(hypr waybar gtk-3.0 gtk-4.0 qt5ct qt6ct fontconfig kitty wofi mako)

pkg_in_list() {
    sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/packages.x86_64" \
        | grep -Fxq -- "$1"
}

# --- Section 2: --sync (no root) ---------------------------------------------
# tar is used instead of `cp -r` because it preserves symlinks and modes and
# because --exclude='.gitkeep' keeps Phase 1's tracked skeleton placeholders.
# A blanket `find ... -name .gitkeep -delete` would DELETE TRACKED FILES.
mirror() {
    local src="$1" dst="$2"
    install -d -m 0755 -- "$dst"
    tar -C "$src" --exclude='.gitkeep' -cf - . | tar -C "$dst" -xf -
}

render_skel_configs() {
    section "Rendering canonical tool configs into config/desktop/skel/.config/"
    local d
    for d in "${RENDER_DIRS[@]}"; do
        mirror "${DESK}/${d}" "${SKEL}/.config/${d}"
    done
    install -D -m 0644 -- "${DESK}/xdg/mimeapps.list" "${SKEL}/.config/mimeapps.list"
    ok "Rendered ${#RENDER_DIRS[@]} tool config dirs + mimeapps.list"
}

sync_profile() {
    section "Syncing Phase 6 desktop config into the archiso profile"
    render_skel_configs

    # 1:1 with /etc/skel (the same rule Phase 5 uses for config/system -> /etc).
    mirror "${SKEL}" "${PROFILE}/airootfs/etc/skel"
    # System-wide drop-ins that map 1:1 to /etc.
    mirror "${ETC}" "${PROFILE}/airootfs/etc"

    # SDDM theme (Main.qml, theme.conf, metadata.desktop, background.png).
    install -d -m 0755 -- "${PROFILE}/airootfs/usr/share/sddm/themes/ar0x"
    local f
    for f in metadata.desktop theme.conf Main.qml background.png; do
        install -m 0644 -- "${AR0X_ASSETS_DIR}/sddm/ar0x/${f}" \
            "${PROFILE}/airootfs/usr/share/sddm/themes/ar0x/${f}"
    done
    # Wallpapers: PNGs only. PLACEHOLDERS.md is a SOURCE-ROOT design note.
    install -d -m 0755 -- "${PROFILE}/airootfs/usr/share/backgrounds/ar0x"
    shopt -s nullglob
    local pngs=("${AR0X_ASSETS_DIR}"/wallpapers/*.png)
    shopt -u nullglob
    (( ${#pngs[@]} == 3 )) || die "Expected exactly 3 wallpaper PNGs; run tools/gen-desktop-assets.sh first."
    for f in "${pngs[@]}"; do
        install -m 0644 -- "$f" "${PROFILE}/airootfs/usr/share/backgrounds/ar0x/"
    done

    ok "Profile synced: /etc/skel, /etc/sddm.conf.d, SDDM theme, wallpapers"
    log "bootstrap.sh additionally overlays config/desktop/{skel,etc} into its disposable STAGE."
}

# --- Section 3: --check (read-only) ------------------------------------------
validate() {
    section "Validating Phase 6 desktop configuration"

    local f
    for f in "${CANONICAL[@]}"; do
        [[ -f "${DESK}/${f}" ]] && ok "config/desktop/${f}" \
                                 || fail "Missing config/desktop/${f}"
    done
    for f in "${THEME_FILES[@]}" tools/configure-desktop.sh \
             tools/gen-desktop-assets.sh docs/DESKTOP_GUIDE.md; do
        [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] && ok "$f" \
                                            || fail "Missing Phase 6 file: ${f}"
    done

    # RISK-002: Lua config is MANDATORY in Hyprland 0.57. A stray .conf file
    # (even a backup) will be picked up by users and break the session.
    local stray
    stray="$(find "${AR0X_SOURCE_ROOT}" -path "${AR0X_SOURCE_ROOT}/.git" -prune -o \
                  -type f -name 'hyprland.conf' -print 2>/dev/null)"
    if [[ -n "$stray" ]]; then
        fail "RISK-002: Hyprland 0.57 removed hyprland.conf. Found: ${stray}"
    else
        ok "RISK-002: zero hyprland.conf files (Lua config only)"
    fi
    grep -Fq 'require("lua.palette")' "${HYPR}/hyprland.lua" \
        || fail "hyprland.lua is not a Lua entry point (no require() calls)."
    [[ "${AR0X_HYPR_CONFIG_ENTRY}" == "hyprland.lua" ]] \
        || fail "AR0X_HYPR_CONFIG_ENTRY must be hyprland.lua."

    # Lua structural validation + require() target resolution.
    # `lua`/`luac` are not installed in this sandbox, so this is a real
    # string-aware structural check (balanced braces/parens, comments and
    # string literals removed FIRST) plus module path resolution.
    python3 - "${HYPR}" <<'PY' || fail "Lua structural validation failed."
import os
import re
import sys

root = sys.argv[1]

def strip(s):
    s = re.sub(r'--\[\[.*?\]\]', '', s, flags=re.S)
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
    s = re.sub(r'--[^\n]*', '', s)
    return s

bad = 0
for dirpath, _, names in os.walk(root):
    for name in sorted(names):
        if not name.endswith('.lua'):
            continue
        path = os.path.join(dirpath, name)
        code = strip(open(path, encoding='utf-8').read())
        if code.count('{') != code.count('}') or code.count('(') != code.count(')'):
            print('[FAIL] unbalanced Lua delimiters:', path)
            bad += 1
        for mod in re.findall(r'require\(\s*"([^"]+)"\s*\)', open(path, encoding='utf-8').read()):
            target = os.path.join(root, *mod.split('.')) + '.lua'
            if not os.path.isfile(target):
                print('[FAIL] require(%s) -> missing %s' % (mod, target))
                bad += 1
if bad:
    sys.exit(1)
print('[ OK ] Lua modules: delimiters balanced, every require() resolves')
PY

    # JSONC (Waybar + fastfetch) must parse after comment stripping.
    python3 - "${AR0X_SOURCE_ROOT}" <<'PY' || fail "JSONC validation failed."
import json, os, re, sys

def strip_jsonc(text):
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            if c == '\\':
                out.append(text[i:i+2]); i += 2; continue
            if c == '"': in_str = False
            out.append(c); i += 1; continue
        if c == '"': in_str = True; out.append(c); i += 1; continue
        if c == '/' and i+1 < n and text[i+1] == '/':
            j = text.find('\n', i)
            if j < 0: break
            i = j; continue
        if c == '/' and i+1 < n and text[i+1] == '*':
            j = text.find('*/', i+2); i = (j+2) if j >= 0 else n; continue
        out.append(c); i += 1
    return ''.join(out)

root = sys.argv[1]
for rel in ('config/desktop/waybar/config.jsonc',
            'config/desktop/skel/.config/fastfetch/config.jsonc'):
    obj = json.loads(strip_jsonc(open(os.path.join(root, rel), encoding='utf-8').read()))
    assert isinstance(obj, dict), rel
    print('[ OK ] JSONC parsed:', rel, '(%d keys)' % len(obj))
PY

    # fontconfig XML must be well-formed.
    python3 - "${AR0X_SOURCE_ROOT}" <<'PY' || fail "fontconfig XML is malformed."
import os, sys, xml.etree.ElementTree as ET
p = os.path.join(sys.argv[1], 'config/desktop/fontconfig/conf.d/99-ar0x-fonts.conf')
ET.parse(p)
print('[ OK ] fontconfig XML well-formed')
PY

    # QML / SDDM theme contract.
    grep -Fq 'import QtQuick' "${AR0X_ASSETS_DIR}/sddm/ar0x/Main.qml" \
        || fail "Main.qml missing QtQuick import."
    grep -Fq 'import SddmComponents 2.0' "${AR0X_ASSETS_DIR}/sddm/ar0x/Main.qml" \
        || fail "Main.qml missing SddmComponents 2.0 import."
    # Only real `import` lines matter: the file HEADER mentions Qt5Compat in a
    # comment explaining why it is NOT used (a plain grep -Fq would false-positive).
    if grep -Eq '^[[:space:]]*import[[:space:]]+(Qt5Compat|QtGraphicalEffects)' \
            "${AR0X_ASSETS_DIR}/sddm/ar0x/Main.qml"; then
        fail "Main.qml imports Qt5Compat/QtGraphicalEffects (Qt6 greeter incompatible)."
    fi
    grep -Fq 'Type=sddm-theme' "${AR0X_ASSETS_DIR}/sddm/ar0x/metadata.desktop" \
        || fail "metadata.desktop missing Type=sddm-theme."
    grep -Fq 'MainScript=Main.qml' "${AR0X_ASSETS_DIR}/sddm/ar0x/metadata.desktop" \
        || fail "metadata.desktop missing MainScript=Main.qml."
    grep -Fq 'QtVersion=6' "${AR0X_ASSETS_DIR}/sddm/ar0x/metadata.desktop" \
        || fail "SDDM 0.21 uses a Qt6 greeter; metadata.desktop must declare QtVersion=6."
    grep -Eq '^background=background\.png' "${AR0X_ASSETS_DIR}/sddm/ar0x/theme.conf" \
        || fail "theme.conf must point at background.png."
    grep -Eq '^Current=ar0x' "${ETC}/sddm.conf.d/10-ar0x.conf" \
        || fail "sddm.conf.d drop-in does not select the ar0x theme."
    python3 - "${AR0X_ASSETS_DIR}/sddm/ar0x/Main.qml" <<'PY' || fail "QML delimiters unbalanced."
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
s = re.sub(r'//[^\n]*', '', s)
assert s.count('{') == s.count('}'), 'braces'
assert s.count('(') == s.count(')'), 'parens'
print('[ OK ] QML delimiters balanced')
PY
    ok "SDDM Qt6 theme contract valid (imports, metadata, config, QML structure)"

    # Palette single source of truth (ADR-015).
    python3 - "${AR0X_SOURCE_ROOT}" <<'PY' || fail "Palette drift detected."
import os, re, sys
root = sys.argv[1]
env = open(os.path.join(root, 'config/versions.env'), encoding='utf-8').read()
pins = dict(re.findall(r'^AR0X_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
                       env, flags=re.M))
assert len(pins) == 8, 'expected 8 palette pins, got %r' % pins
palette = open(os.path.join(root, 'config/desktop/hypr/lua/palette.lua'), encoding='utf-8').read()
keys = {'VOID':'void','SURFACE':'surface','CYAN':'cyan','MAGENTA':'magenta',
        'LIME':'lime','TEXT':'text','MUTED':'muted','ALERT':'alert'}
for pin, val in pins.items():
    assert re.search(r'\b%s\s*=\s*"%s"' % (keys[pin], re.escape(val)), palette), \
        'palette.lua: %s != %s' % (keys[pin], val)
qml = open(os.path.join(root, 'assets/sddm/ar0x/Main.qml'), encoding='utf-8').read()
for pin in ('VOID','SURFACE','CYAN','MAGENTA','LIME','TEXT','MUTED','ALERT'):
    assert pins[pin] in qml, 'Main.qml missing palette pin %s=%s' % (pin, pins[pin])
print('[ OK ] 8 palette pins: versions.env == lua/palette.lua == Main.qml')
PY

    # Global GDK_BACKEND is FORBIDDEN (Phase 5 decision / RISK-039).
    if grep -v '^[[:space:]]*#' "${ETC}/environment.d/20-ar0x-desktop.conf" \
            | grep -Eq '^[[:space:]]*GDK_BACKEND[[:space:]]*='; then
        fail "Global GDK_BACKEND would break XWayland GTK apps (RISK-039)."
    fi
    if grep -v '^[[:space:]]*--' "${HYPR}/lua/env.lua" \
            | grep -Eq 'hl\.env\("GDK_BACKEND"'; then
        fail "lua/env.lua sets global GDK_BACKEND (RISK-039)."
    fi
    ok "No global GDK_BACKEND (XWayland GTK apps keep working)"

    # Qt platform theme: colon-separated list covers Qt5 AND Qt6 with one var.
    grep -Fq 'qt5ct:qt6ct' "${HYPR}/lua/env.lua" \
        || fail "lua/env.lua must set QT_QPA_PLATFORMTHEME=qt5ct:qt6ct."
    grep -Fq 'qt5ct:qt6ct' "${ETC}/environment.d/20-ar0x-desktop.conf" \
        || fail "environment.d drop-in must set QT_QPA_PLATFORMTHEME=qt5ct:qt6ct."
    ok "Qt5/Qt6 theming uses the single colon-separated platform theme"

    # SDDM must be enabled in the ONE preset file owned by Phase 5.
    grep -Fxq 'enable sddm.service' "$PRESET" \
        || fail "sddm.service is not enabled in config/system/systemd/system-preset/50-ar0x.preset."
    ok "sddm.service enabled in the single systemd preset owner"

    # Wallpaper references must resolve to real PNGs.
    local wp
    for wp in ar0x-neon-grid.png ar0x-circuit.png; do
        [[ -f "${AR0X_ASSETS_DIR}/wallpapers/${wp}" ]] \
            || fail "Missing wallpaper asset: assets/wallpapers/${wp}"
    done
    grep -Fq '/usr/share/backgrounds/ar0x/ar0x-neon-grid.png' "${HYPR}/hyprpaper.conf" \
        || fail "hyprpaper.conf does not reference the ar0x wallpaper."
    grep -Fq '/usr/share/backgrounds/ar0x/ar0x-circuit.png' "${HYPR}/hyprlock.conf" \
        || fail "hyprlock.conf does not reference the ar0x lock wallpaper."
    ok "hyprpaper/hyprlock reference existing wallpaper assets"

    # Required packages.
    local p
    local P6_PKGS=(
        hyprland hyprpaper hyprlock hypridle waybar sddm xorg-xwayland
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
        qt5-wayland qt6-wayland qt5ct qt6ct gtk3 gtk4 libadwaita
        papirus-icon-theme adwaita-icon-theme adwaita-cursors
        inter-font ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
        kitty wofi mako thunar gvfs grim slurp wl-clipboard
        brightnessctl playerctl network-manager-applet polkit-gnome
        xdg-user-dirs fastfetch
    )
    for p in "${P6_PKGS[@]}"; do
        pkg_in_list "$p" || fail "Required Phase 6 package missing from config/packages.x86_64: ${p}"
    done
    ok "All ${#P6_PKGS[@]} Phase 6 packages present in config/packages.x86_64"

    # Generated copies must match their canonical sources exactly.
    local d
    for d in "${RENDER_DIRS[@]}"; do
        diff -qr --exclude='.gitkeep' "${DESK}/${d}" "${SKEL}/.config/${d}" >/dev/null \
            || fail "config/desktop/skel/.config/${d} is stale — run --sync."
    done
    cmp -s "${DESK}/xdg/mimeapps.list" "${SKEL}/.config/mimeapps.list" \
        || fail "skel/.config/mimeapps.list is stale — run --sync."
    diff -qr --exclude='.gitkeep' "${SKEL}" "${PROFILE}/airootfs/etc/skel" >/dev/null \
        || fail "archiso/airootfs/etc/skel is stale — run --sync."
    for f in sddm.conf.d/10-ar0x.conf environment.d/20-ar0x-desktop.conf \
             xdg/user-dirs.defaults; do
        cmp -s "${ETC}/${f}" "${PROFILE}/airootfs/etc/${f}" \
            || fail "archiso/airootfs/etc/${f} is stale — run --sync."
    done
    ok "All generated copies byte-identical to canonical sources"

    # PNG signature + dimensions (no image library needed).
    python3 - "${AR0X_SOURCE_ROOT}" <<'PY' || fail "PNG asset validation failed."
import os, struct, sys
root = sys.argv[1]
expected = {
    'assets/wallpapers/ar0x-neon-grid.png': (3840, 2160),
    'assets/wallpapers/ar0x-void.png':      (3840, 2160),
    'assets/wallpapers/ar0x-circuit.png':   (3840, 2160),
    'assets/sddm/ar0x/background.png':      (1920, 1080),
}
for rel, dims in expected.items():
    p = os.path.join(root, rel)
    assert os.path.isfile(p), 'missing ' + rel
    with open(p, 'rb') as fh: head = fh.read(33)
    assert head[:8] == b'\x89PNG\r\n\x1a\n', 'bad signature ' + rel
    assert struct.unpack('>II', head[16:24]) == dims, 'bad dimensions ' + rel
print('[ OK ] 4 desktop PNG assets: signature + dimensions')
PY

    # Expected, non-fatal environment warnings.
    warn "Hyprland --verify-config, sddm-greeter --test-mode and a real Wayland session need an Arch host + display (MANUAL)."
    warn "RISK-040: Adwaita cursor and generated PNG wallpapers are placeholders; Phase 7 ships the final ar0x art."
}

# --- Section 4: --apply (root, manual) ---------------------------------------
apply_in_chroot() {
    section "Applying Phase 6 desktop config inside the airootfs chroot"
    require_root
    require_command arch-chroot
    [[ -d "$AIROOTFS" ]] || die "No airootfs at ${AIROOTFS}. Run 'sudo ./tools/bootstrap.sh --iso-only' first."
    if [[ ! -s "${AIROOTFS}/etc/resolv.conf" ]]; then
        cp -L -- /etc/resolv.conf "${AIROOTFS}/etc/resolv.conf"
    fi
    install -d -m 0755 -- "$(dirname -- "$LOG_FILE")"

    printf '%s⚠️ This does NOT start SDDM/Hyprland. It only refreshes caches,%s\n' \
        "$_AR0X_C_WARN" "$_AR0X_C_RST"
    printf '   re-applies systemd presets and VERIFIES the Lua config offline.\n\n'

    log "fc-cache -f (fontconfig cache for Inter / JetBrainsMono Nerd / Noto)"
    arch-chroot "$AIROOTFS" /usr/bin/fc-cache -f 2>&1 | tee -a "$LOG_FILE"
    log "update-desktop-database"
    arch-chroot "$AIROOTFS" /usr/bin/update-desktop-database /usr/share/applications 2>&1 | tee -a "$LOG_FILE"
    log "systemctl preset-all (enables sddm.service from 50-ar0x.preset)"
    arch-chroot "$AIROOTFS" /usr/bin/systemctl preset-all 2>&1 | tee -a "$LOG_FILE"
    log "Hyprland --verify-config -c /etc/skel/.config/hypr/hyprland.lua"
    arch-chroot "$AIROOTFS" /usr/bin/Hyprland --verify-config \
        -c /etc/skel/.config/hypr/hyprland.lua 2>&1 | tee -a "$LOG_FILE"
    ok "Phase 6 applied in chroot (log: ${LOG_FILE})"
}

# --- Section 5: dispatch -----------------------------------------------------
cd "$AR0X_SOURCE_ROOT"
warn "RISK-002: Hyprland 0.57 uses Lua config ONLY — no hyprland.conf, no converter."
case "$MODE" in
    check)
        validate
        assert_clean
        ok "Phase 6 --check PASSED (no root, no writes)"
        printf '\nNext steps on a real Arch host:\n'
        printf '  ./tools/gen-desktop-assets.sh\n'
        printf '  ./tools/configure-desktop.sh --sync\n'
        printf '  sudo ./tools/bootstrap.sh --iso-only\n'
        printf '  sudo ./tools/configure-desktop.sh --apply\n'
        ;;
    sync)
        sync_profile
        validate
        assert_clean
        ok "Phase 6 --sync complete"
        ;;
    apply)
        validate
        assert_clean
        apply_in_chroot
        ;;
esac
