#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/validate-versions.sh
# -----------------------------------------------------------------------------
# Phase 1 helper — validates version pins, build-tree structure, the two
# "stale upstream" traps and the Phase 8/9 package/repository policy gates
# before ANY build stage runs.
#
# This script is SAFE TO RUN IN A NON-ROOT SANDBOX: it only reads local files.
# Phase 11's build-iso.sh MUST call it as stage 1 and abort on any failure.
#
# Checks performed:
#   1. config/versions.env exists, parses, and every required key is non-empty.
#   2. Hyprland config format is Lua; NO stray hyprland.conf anywhere (RISK-002).
#   3. Calamares pin is 3.4.3 from Codeberg, not the archived GitHub 3.3.14 (RISK-003).
#   4. No custom kernel patches in v0.1 (RISK-001).
#   5. If config/pacman.conf.build exists, its archive date matches the pin
#      and it does NOT leak into the installed pacman.conf (RISK-006).
#   6. Every tools/*.sh has the mandated shebang + `set -euo pipefail`.
#   7. Required directory skeleton exists.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Resolve the SOURCE ROOT from this script's own location (no assumptions) -
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
VERSIONS_FILE="${AR0X_SOURCE_ROOT}/config/versions.env"

# --- Colours / logging helpers (local; tools/lib/common.sh arrives in Phase 2) -
if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RST=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_RST=""
fi
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK"   "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RST" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_ERR"  "$C_RST" "$*" >&2; exit 1; }

ERRORS=0
fail() { printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; ERRORS=$((ERRORS + 1)); }

# --- Section 1: load and validate versions.env --------------------------------
[[ -f "$VERSIONS_FILE" ]] || die "Missing ${VERSIONS_FILE} (Phase 1 deliverable)."
# shellcheck source=/dev/null
source "$VERSIONS_FILE"
ok "Loaded ${VERSIONS_FILE}"

REQUIRED_KEYS=(
    AR0X_VERSION AR0X_ARCH AR0X_ISO_LABEL AR0X_ISO_MAX_BYTES
    AR0X_SNAPSHOT_DATE AR0X_ARCHIVE_URL
    AR0X_GLIBC_VERSION AR0X_SYSTEMD_VERSION AR0X_KERNEL_VERSION
    AR0X_KERNEL_FLAVOR AR0X_MKINITCPIO_VERSION AR0X_GRUB_VERSION
    AR0X_INSTALL_DIR AR0X_ARCHISO_VERSION AR0X_ARCHISO_BUILDMODES
    AR0X_ARCHISO_BOOTMODES AR0X_ARCHISO_AIROOTFS_TYPE AR0X_HARD_PIN_REPO_PRIORITY
    AR0X_HYPRLAND_VERSION AR0X_HYPR_CONFIG_FORMAT AR0X_HYPR_CONFIG_ENTRY
    AR0X_CALAMARES_VERSION AR0X_CALAMARES_SOURCE AR0X_CALAMARES_SHA256
    AR0X_DEFAULT_SHELL AR0X_SCRIPT_SHELL AR0X_CYAN AR0X_VOID
    AR0X_SECURE_BOOT AR0X_APPARMOR_MODE AR0X_CUSTOM_KERNEL_PATCHES
    AR0X_BRAND_LOGO_VIEWBOX AR0X_BRAND_WORDMARK_VIEWBOX
    AR0X_BRAND_LOGO_ICON AR0X_BRAND_CURSOR_THEME AR0X_BRAND_LICENSE
    AR0X_TOOLS_VERSION AR0X_WELCOME_APP_ID AR0X_WELCOME_FIRSTBOOT_MARKER
    AR0X_UPDATE_REPO AR0X_UPDATE_SIGLEVEL
    AR0X_URL_DOCS AR0X_URL_ISSUES AR0X_URL_COMMUNITY AR0X_URL_SOURCE
    AR0X_URL_UPSTREAM
    AR0X_REPO_NAME AR0X_REPO_DB AR0X_REPO_FILES_DB AR0X_REPO_SIGLEVEL
    AR0X_REPO_ARCH AR0X_REPO_SERVER AR0X_REPO_KEY_UID AR0X_REPO_KEY_ALGO
    AR0X_REPO_KEY_EXPIRE AR0X_REPO_KEY_FINGERPRINT_FILE AR0X_REPO_PUBLIC_KEY
    AR0X_REPO_KEEP_OLD AR0X_REPO_CI_IMAGE AR0X_REPO_CI_BUILDER
    AR0X_REPO_SIGN_PACKAGES
    AR0X_INSTALLER_BRANDING AR0X_INSTALLER_LIVE_USER AR0X_CALAMARES_ESP_MIB
    AR0X_CALAMARES_MODULE_SEARCH AR0X_INSTALLER_PACKAGE_GROUPS
    AR0X_ISO_BUILD_MODE AR0X_ISO_SIZE_GATE_GIB AR0X_ISO_QEMU_RAM_MIB
    AR0X_ISO_QEMU_CPUS AR0X_ISO_QEMU_DISK_GIB AR0X_RELEASE_ARTIFACT_COUNT
    AR0X_RELEASE_CHECKLIST_ITEMS AR0X_RELEASE_CHECKLIST_GATE
)
for key in "${REQUIRED_KEYS[@]}"; do
    if [[ -z "${!key:-}" ]]; then
        fail "Required version key is empty or missing: ${key}"
    fi
done
ok "All ${#REQUIRED_KEYS[@]} required version keys are non-empty"

# --- Section 2: Hyprland 0.57 Lua gate (RISK-002) ----------------------------
if [[ "${AR0X_HYPR_CONFIG_FORMAT}" != "lua" || "${AR0X_HYPR_CONFIG_ENTRY}" != "hyprland.lua" ]]; then
    fail "Hyprland >= 0.57 requires Lua config. Set AR0X_HYPR_CONFIG_FORMAT=lua and AR0X_HYPR_CONFIG_ENTRY=hyprland.lua."
fi
STRAY_CONF="$(find "${AR0X_SOURCE_ROOT}" -path "${AR0X_SOURCE_ROOT}/.git" -prune -o \
                  -type f -name 'hyprland.conf' -print 2>/dev/null || true)"
if [[ -n "$STRAY_CONF" ]]; then
    fail "Stray hyprland.conf found (0.57 ignores it): ${STRAY_CONF//$'\n'/, }"
fi
ok "Hyprland Lua config gate passed (pinned ${AR0X_HYPRLAND_VERSION}, no stray .conf)"

# --- Section 3: Calamares upstream gate (RISK-003) ---------------------------
if [[ "${AR0X_CALAMARES_VERSION}" != "3.4.3" || "${AR0X_CALAMARES_SOURCE}" != "codeberg" ]]; then
    fail "Calamares must be 3.4.3 from Codeberg; github.com/calamares/calamares is an archived mirror at 3.3.14."
fi
if [[ "${#AR0X_CALAMARES_SHA256}" -ne 64 ]]; then
    fail "AR0X_CALAMARES_SHA256 is not a 64-char SHA256 digest."
fi
if [[ "${AR0X_CALAMARES_URL}" == *"github.com"* ]]; then
    fail "Calamares download URL points at GitHub; use the Codeberg release tarball."
fi
ok "Calamares gate passed (${AR0X_CALAMARES_VERSION} / ${AR0X_CALAMARES_SOURCE})"

# --- Section 4: no custom kernel patches in v0.1 (RISK-001) -----------------
if [[ "${AR0X_CUSTOM_KERNEL_PATCHES}" != "none" ]]; then
    warn "RISK-001: custom kernel patches are enabled (${AR0X_CUSTOM_KERNEL_PATCHES}). v0.1 must use stock linux-lts."
    fail "Set AR0X_CUSTOM_KERNEL_PATCHES=none or explicitly acknowledge RISK-001 in Phase 4."
fi
PATCH_COUNT="$(find "${AR0X_SOURCE_ROOT}/config/kernel/patches" -maxdepth 1 \
                   -type f \( -name '*.patch' -o -name '*.diff' \) -print 2>/dev/null | wc -l)"
if [[ "$PATCH_COUNT" -gt 0 ]]; then
    fail "RISK-001: ${PATCH_COUNT} kernel patch file(s) present but pin says none."
fi
ok "Kernel gate passed (stock ${AR0X_KERNEL_FLAVOR} ${AR0X_KERNEL_VERSION}, zero patches)"

# --- Section 4b: archiso 92 profile contract (RISK-017) ---------------------
# Phase 2 correction: upstream is 92-1, and its profiledef.sh uses buildmodes /
# bootmodes. Asserting this here prevents Phase 3 from shipping an 91-style
# profile that mkarchiso 92 would reject.
if [[ "${AR0X_ARCHISO_VERSION}" != "92-1" ]]; then
    fail "archiso pin is ${AR0X_ARCHISO_VERSION}; verified upstream release is 92-1 (see docs/BUILD_HOST.md §3)."
fi
if [[ "${AR0X_ARCHISO_BUILDMODES}" != "iso" ]]; then
    fail "archiso 92 buildmodes must be 'iso' (got '${AR0X_ARCHISO_BUILDMODES}')."
fi
if [[ "${AR0X_ARCHISO_BOOTMODES}" != *"bios.syslinux"* || "${AR0X_ARCHISO_BOOTMODES}" != *"uefi.grub"* ]]; then
    fail "archiso 92 bootmodes must include bios.syslinux AND uefi.grub (got '${AR0X_ARCHISO_BOOTMODES}')."
fi
if [[ "${AR0X_HARD_PIN_REPO_PRIORITY}" != "first" ]]; then
    fail "ADR-017: the [ar0x] repo must be listed FIRST in pacman.conf.build for HARD pins to win."
fi
ok "archiso 92-1 profile contract + ADR-017 repo ordering verified"

# --- Section 5: frozen pacman.conf must not leak to installed systems --------
BUILD_CONF="${AR0X_SOURCE_ROOT}/config/pacman.conf.build"
INSTALL_CONF="${AR0X_SOURCE_ROOT}/config/pacman.conf.installed"
if [[ -f "$BUILD_CONF" ]]; then
    if ! grep -Fq "archive.archlinux.org/repos/${AR0X_SNAPSHOT_DATE}" "$BUILD_CONF"; then
        fail "config/pacman.conf.build does not pin the snapshot date ${AR0X_SNAPSHOT_DATE}."
    fi
    ok "Build pacman.conf pins the frozen archive date ${AR0X_SNAPSHOT_DATE}"
else
    warn "config/pacman.conf.build not created yet (expected: Phase 3)."
fi
if [[ -f "$INSTALL_CONF" ]]; then
    if grep -v '^[[:space:]]*#' "$INSTALL_CONF" | grep -Fq "archive.archlinux.org"; then
        fail "RISK-006: installed pacman.conf contains a frozen archive mirror."
    fi
    if ! grep -Fq "[ar0x]" "$INSTALL_CONF"; then
        fail "installed pacman.conf is missing the [ar0x] repository entry (expected by Phase 9)."
    fi
    ok "Installed pacman.conf has no frozen mirror and declares [ar0x]"
else
    warn "config/pacman.conf.installed not created yet (expected: Phase 5/9)."
fi

# --- Section 6: script hygiene (#!/bin/bash + set -euo pipefail) -------------
SCRIPT_COUNT=0
# Check EVERY shell script in the repo (tools/, docker/, vagrant/), not just
# tools/, so the Phase 2 container and VM helper scripts are covered too.
while IFS= read -r -d '' sh; do
    # Exempt SOURCED config snippets, which are not standalone scripts:
    #   * archiso/profiledef.sh     -> sourced by mkarchiso (strict mode would
    #                                  leak into mkarchiso itself)
    #   * config/system/profile.d/  -> sourced by zsh/bash LOGIN shells; a
    #                                  shebang or set -euo pipefail is invalid
    #                                  and would break every login shell
    #   * config/branding/ascii/ar0x-screenfetch.sh -> SOURCED by screenFetch
    #                                  3.9.9 `asciiText()`; strict mode would
    #                                  leak into screenFetch and abort it
    #   * /usr/share/ar0x/branding/*.sh             -> byte-identical INSTALLED
    #                                  mirror of the sourced art snippet in the
    #                                  archiso profile; same exemption applies
    case "$sh" in
        */archiso/profiledef.sh|*/config/system/profile.d/*.sh|*/archiso/airootfs/etc/profile.d/*.sh|*/config/branding/ascii/*.sh|*/usr/share/ar0x/branding/*.sh) continue ;;
    esac
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
    first_line="$(head -n 1 -- "$sh")"
    [[ "$first_line" == "#!/bin/bash" ]] || fail "${sh}: first line must be #!/bin/bash (got '${first_line}')."
    grep -Eq '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail' "$sh" \
        || fail "${sh}: missing 'set -euo pipefail'."
done < <(find "${AR0X_SOURCE_ROOT}" \
             -path "${AR0X_SOURCE_ROOT}/.git" -prune -o \
             -type f -name '*.sh' -print0 2>/dev/null)
ok "Script hygiene passed for ${SCRIPT_COUNT} shell script(s)"

# --- Section 7: required directory skeleton ----------------------------------
REQUIRED_DIRS=(
    docs/architecture config/kernel/patches config/system config/desktop/hypr
    config/branding config/calamares/modules config/repo archiso/airootfs/etc
    archiso/grub archiso/isolinux archiso/syslinux assets/logo assets/wallpapers
    assets/plymouth assets/grub-theme assets/sddm packages tools/lib ci/workflows
    tests repo/x86_64 docker vagrant
    archiso/grub archiso/syslinux archiso/airootfs/etc/mkinitcpio.conf.d
    config/kernel config/mkinitcpio.d config/default config/plymouth
    assets/grub-theme/ar0x assets/plymouth/ar0x assets/syslinux
    archiso/grub/themes/ar0x archiso/airootfs/usr/share/plymouth/themes/ar0x
    config/desktop/etc config/desktop/skel config/desktop/hypr/lua
    assets/sddm/ar0x archiso/airootfs/usr/share/sddm/themes/ar0x
    archiso/airootfs/usr/share/backgrounds/ar0x archiso/airootfs/etc/skel
    config/branding/ascii config/branding/fastfetch config/branding/neofetch
    config/branding/screenfetch assets/logo assets/icons
    assets/cursors/ar0x-cursors assets/ascii
    archiso/airootfs/usr/share/ar0x/branding archiso/airootfs/usr/share/ar0x/logo
    archiso/airootfs/usr/share/icons/hicolor/scalable/apps
    archiso/airootfs/usr/share/icons/ar0x-cursors/cursors
    archiso/airootfs/usr/local/bin
    config/tools
    packages/ar0x-info packages/ar0x-update packages/ar0x-welcome
    packages/ar0x-theme packages/ar0x-wallpapers packages/ar0x-hypr-config
    packages/ar0x-keyring packages/ar0x-meta
)
for d in "${REQUIRED_DIRS[@]}"; do
    [[ -d "${AR0X_SOURCE_ROOT}/${d}" ]] || fail "Missing directory: ${d}/"
done
ok "Directory skeleton present (${#REQUIRED_DIRS[@]} required paths)"

# --- Section 7b: Phase 2 deliverable files -----------------------------------
PHASE2_FILES=(
    tools/setup-build-env.sh tools/lib/common.sh docs/BUILD_HOST.md
    docker/Dockerfile docker/compose.yaml docker/run.sh
    vagrant/provision.sh Vagrantfile
)
for f in "${PHASE2_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 2 deliverable: ${f}"
done
ok "Phase 2 deliverable files present (${#PHASE2_FILES[@]} files)"

# --- Section 7c: Phase 3 deliverable files -----------------------------------
PHASE3_FILES=(
    config/pacman.conf.build config/packages.x86_64
    config/bootstrap_packages.x86_64
    archiso/profiledef.sh archiso/pacman.conf archiso/packages.x86_64
    archiso/bootstrap_packages.x86_64 archiso/grub/grub.cfg
    archiso/syslinux/syslinux.cfg
    archiso/airootfs/etc/mkinitcpio.conf.d/archiso.conf
    archiso/airootfs/etc/hostname archiso/airootfs/etc/locale.conf
    archiso/airootfs/etc/pacman.d/hooks/90-ar0x-build-stamp.hook
    tools/bootstrap.sh docs/BOOTSTRAP_GUIDE.md
)
for f in "${PHASE3_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 3 deliverable: ${f}"
done
ok "Phase 3 deliverable files present (${#PHASE3_FILES[@]} files)"

# --- Section 7d: Phase 4 deliverable files + RISK-001 -----------------------
PHASE4_FILES=(
    config/kernel/README.md config/kernel/ar0x-lts.config
    config/mkinitcpio.conf config/mkinitcpio.d/linux-lts.preset
    config/default/grub config/plymouth/plymouthd.conf
    assets/grub-theme/ar0x/theme.txt assets/grub-theme/ar0x/background.png
    assets/plymouth/ar0x/ar0x.plymouth assets/plymouth/ar0x/ar0x.script
    assets/plymouth/ar0x/logo.png assets/syslinux/splash.png
    archiso/grub/themes/ar0x/theme.txt archiso/syslinux/splash.png
    tools/build-kernel.sh tools/gen-theme-assets.sh docs/KERNEL_BOOT.md
)
for f in "${PHASE4_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 4 deliverable: ${f}"
done
ok "Phase 4 deliverable files present (${#PHASE4_FILES[@]} files)"

# --- Section 7e: Phase 5 deliverable files + policy gates --------------------
PHASE5_FILES=(
    config/pacman.conf.installed config/repo/pacman.conf.ar0x-entry
    config/system/hostname config/system/hosts config/system/locale.conf
    config/system/locale.gen config/system/vconsole.conf config/system/localtime
    config/system/passwd config/system/shadow config/system/nftables.conf
    config/system/sysusers.d/ar0x-live.conf
    config/system/sudoers.d/10-ar0x-wheel
    config/system/NetworkManager/conf.d/10-ar0x.conf
    config/system/pipewire/pipewire.conf.d/10-ar0x.conf
    config/system/pipewire/wireplumber.conf.d/10-ar0x.conf
    config/system/environment.d/10-ar0x-wayland.conf
    config/system/sysctl.d/50-ar0x-security.conf
    config/system/sysctl.d/60-ar0x-network.conf
    config/system/systemd/system-preset/50-ar0x.preset
    config/system/systemd/system/apparmor.service.d/10-ar0x-complain.conf
    tools/configure-system.sh docs/SYSTEM_CONFIG.md
)
for f in "${PHASE5_FILES[@]}"; do
    [[ -e "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 5 deliverable: ${f}"
done
ok "Phase 5 deliverable files present (${#PHASE5_FILES[@]} files)"

# Developer toolchain compatibility must survive sysctl hardening.
grep -Fq 'kernel.unprivileged_userns_clone = 1' \
    "${AR0X_SOURCE_ROOT}/config/system/sysctl.d/50-ar0x-security.conf" \
    || fail "RISK-014: unprivileged user namespaces must stay ENABLED for developers."
# AppArmor complain mode in v0.1.
[[ "${AR0X_APPARMOR_MODE}" == "complain" ]] \
    || fail "RISK-008: AppArmor must stay in complain mode in v0.1."
# WirePlumber 0.5+ correction: legacy 0.4 skeleton dir must be gone.
[[ ! -d "${AR0X_SOURCE_ROOT}/config/system/wireplumber" ]] \
    || fail "WirePlumber 0.4 legacy config dir present; use config/system/pipewire/wireplumber.conf.d/."
[[ ! -d "${AR0X_SOURCE_ROOT}/config/system/apparmor" ]] \
    || fail "Empty config/system/apparmor/ skeleton present; ar0x ships no custom profiles."
ok "Phase 5 policy gates: userns enabled, AppArmor complain, WP 0.5+ path"

# --- Section 7f: Phase 6 deliverable files + desktop policy gates ------------
PHASE6_FILES=(
    config/desktop/hypr/hyprland.lua
    config/desktop/hypr/lua/palette.lua config/desktop/hypr/lua/programs.lua
    config/desktop/hypr/lua/env.lua config/desktop/hypr/lua/monitors.lua
    config/desktop/hypr/lua/looknfeel.lua config/desktop/hypr/lua/animations.lua
    config/desktop/hypr/lua/input.lua config/desktop/hypr/lua/keybinds.lua
    config/desktop/hypr/lua/rules.lua config/desktop/hypr/lua/autostart.lua
    config/desktop/hypr/hyprpaper.conf config/desktop/hypr/hyprlock.conf
    config/desktop/hypr/hypridle.conf
    config/desktop/waybar/config.jsonc config/desktop/waybar/style.css
    config/desktop/gtk-3.0/settings.ini config/desktop/gtk-3.0/gtk.css
    config/desktop/gtk-4.0/settings.ini config/desktop/gtk-4.0/gtk.css
    config/desktop/qt5ct/qt5ct.conf config/desktop/qt6ct/qt6ct.conf
    config/desktop/fontconfig/conf.d/99-ar0x-fonts.conf
    config/desktop/kitty/kitty.conf config/desktop/wofi/config
    config/desktop/wofi/style.css config/desktop/mako/config
    config/desktop/xdg/mimeapps.list
    config/desktop/etc/sddm.conf.d/10-ar0x.conf
    config/desktop/etc/environment.d/20-ar0x-desktop.conf
    config/desktop/etc/xdg/user-dirs.defaults
    config/desktop/skel/.zshrc config/desktop/skel/.zshenv
    config/desktop/skel/.profile config/desktop/skel/.bashrc
    config/desktop/skel/.config/starship.toml
    config/desktop/skel/.config/hypr/hyprland.lua
    config/desktop/skel/.config/waybar/config.jsonc
    config/desktop/skel/.config/gtk-4.0/gtk.css
    config/desktop/skel/.icons/default/index.theme
    assets/sddm/ar0x/Main.qml assets/sddm/ar0x/metadata.desktop
    assets/sddm/ar0x/theme.conf assets/sddm/ar0x/background.png
    assets/wallpapers/ar0x-grid.png assets/wallpapers/ar0x-void.png
    assets/wallpapers/ar0x-circuit.png assets/wallpapers/PLACEHOLDERS.md
    tools/configure-desktop.sh tools/gen-desktop-assets.sh docs/DESKTOP_GUIDE.md
)
for f in "${PHASE6_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 6 deliverable: ${f}"
done
ok "Phase 6 deliverable files present (${#PHASE6_FILES[@]} files)"

# RISK-002: the entry point must be a Lua file that actually requires modules.
grep -Fq 'require("lua.palette")' \
    "${AR0X_SOURCE_ROOT}/config/desktop/hypr/hyprland.lua" \
    || fail "Phase 6: hyprland.lua is not a modular Lua entry point."
# RISK-039: a global GDK_BACKEND breaks XWayland GTK applications.
if grep -v '^[[:space:]]*#' \
        "${AR0X_SOURCE_ROOT}/config/desktop/etc/environment.d/20-ar0x-desktop.conf" \
        | grep -Eq '^[[:space:]]*GDK_BACKEND[[:space:]]*='; then
    fail "Phase 6 / RISK-039: global GDK_BACKEND in environment.d."
fi
grep -Fq 'qt5ct:qt6ct' \
    "${AR0X_SOURCE_ROOT}/config/desktop/hypr/lua/env.lua" \
    || fail "Phase 6: QT_QPA_PLATFORMTHEME must cover Qt5 AND Qt6 (qt5ct:qt6ct)."
# RISK-038: SDDM 0.21 greeter is Qt6; the theme must declare it.
grep -Fq 'QtVersion=6' "${AR0X_SOURCE_ROOT}/assets/sddm/ar0x/metadata.desktop" \
    || fail "Phase 6 / RISK-038: SDDM theme metadata must declare QtVersion=6."
grep -Fq 'import SddmComponents 2.0' "${AR0X_SOURCE_ROOT}/assets/sddm/ar0x/Main.qml" \
    || fail "Phase 6: Main.qml must import SddmComponents 2.0."
grep -Fxq 'enable sddm.service' \
    "${AR0X_SOURCE_ROOT}/config/system/systemd/system-preset/50-ar0x.preset" \
    || fail "Phase 6: sddm.service must be enabled in 50-ar0x.preset."
# ADR-015: palette parity between versions.env and the compositor palette.
python3 - "${AR0X_SOURCE_ROOT}" <<'PYV' || fail "Phase 6 palette drift detected."
import os, re, sys
root = sys.argv[1]
env = open(os.path.join(root, 'config/versions.env'), encoding='utf-8').read()
pins = dict(re.findall(r'^AR0X_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
                       env, flags=re.M))
keys = {'VOID':'void','SURFACE':'surface','CYAN':'cyan','MAGENTA':'magenta',
        'LIME':'lime','TEXT':'text','MUTED':'muted','ALERT':'alert'}
pal = open(os.path.join(root, 'config/desktop/hypr/lua/palette.lua'), encoding='utf-8').read()
qml = open(os.path.join(root, 'assets/sddm/ar0x/Main.qml'), encoding='utf-8').read()
assert len(pins) == 8, 'expected 8 palette pins'
for k, v in pins.items():
    assert re.search(r'\b%s\s*=\s*"%s"' % (keys[k], re.escape(v)), pal), 'palette.lua ' + k
    assert v in qml, 'Main.qml ' + k
print('[ OK ] 8 palette pins: versions.env == lua/palette.lua == Main.qml')
PYV
ok "Phase 6 policy gates: Lua-only, Qt6 SDDM, Qt5+Qt6 theming, palette parity"

# --- Section 7g: Phase 7 deliverable files + brand policy gates -------------
PHASE7_FILES=(
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
    assets/ascii/README.md
    tools/lib/ar0x_logo.py tools/lib/ar0x_xcursor.py
    tools/gen-branding-assets.sh tools/configure-branding.sh
    docs/BRANDING_GUIDE.md
)
for f in "${PHASE7_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 7 deliverable: ${f}"
done
ok "Phase 7 deliverable files present (${#PHASE7_FILES[@]} files)"

# os-release is the identity contract: ID must NOT be Arch, LOGO must resolve.
grep -Fxq 'ID=ar0x' "${AR0X_SOURCE_ROOT}/config/branding/os-release" \
    || fail "Phase 7: /etc/os-release must declare ID=ar0x."
grep -Fxq 'LOGO=ar0x-logo' "${AR0X_SOURCE_ROOT}/config/branding/os-release" \
    || fail "Phase 7: os-release LOGO must be ar0x-logo (systemd >= 252)."
[[ -f "${AR0X_SOURCE_ROOT}/archiso/airootfs/usr/share/icons/hicolor/scalable/apps/ar0x-logo.svg" ]] \
    || fail "Phase 7: LOGO=ar0x-logo has no installed hicolor icon (run configure-branding.sh --sync)."
# RISK-006-style guard: the installed /etc mirrors must exist and match.
for f in os-release lsb-release issue issue.net motd; do
    cmp -s "${AR0X_SOURCE_ROOT}/config/branding/$f" \
           "${AR0X_SOURCE_ROOT}/archiso/airootfs/etc/$f" \
        || fail "Phase 7: /etc/$f mirror is stale (run configure-branding.sh --sync)."
done
cmp -s "${AR0X_SOURCE_ROOT}/config/branding/os-release" \
       "${AR0X_SOURCE_ROOT}/archiso/airootfs/usr/lib/os-release" \
    || fail "Phase 7: /usr/lib/os-release mirror is stale."
ok "Phase 7 identity: ID=ar0x, LOGO icon installed, 6 /etc mirrors in sync"

# ADR-015 / ADR-022: palette.conf, SVG masters and boot art share the 8 pins.
python3 - "${AR0X_SOURCE_ROOT}" <<'PYV' || fail "Phase 7 palette/geometry drift detected."
import os, re, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, 'tools', 'lib'))
import ar0x_logo as L
rgb, pins = L.load_palette(root)
pal = dict(re.findall(
    r'^AR0X_BRAND_(VOID|SURFACE|CYAN|MAGENTA|LIME|TEXT|MUTED|ALERT)="(#[0-9A-Fa-f]{6})"',
    open(os.path.join(root, 'config/branding/palette.conf'), encoding='utf-8').read(), re.M))
assert len(pal) == 8 and pal == pins, 'palette.conf != versions.env'
svg = open(os.path.join(root, 'assets/logo/ar0x-logo.svg'), encoding='utf-8').read()
for key in ('CYAN', 'MAGENTA', 'LIME'):
    assert pins[key] in svg, 'ar0x-logo.svg missing ' + pins[key]
r = ET.parse(os.path.join(root, 'assets/logo/ar0x-logo.svg')).getroot()
assert r.get('viewBox') == L.VIEWBOX == '0 0 512 512'
poly = r.find('{http://www.w3.org/2000/svg}polygon')
assert tuple(tuple(map(int, p.split(','))) for p in poly.get('points').split()) == L.OCTAGON
theme = open(os.path.join(root, 'assets/grub-theme/ar0x/theme.txt'), encoding='utf-8').read()
for key in ('VOID', 'SURFACE', 'CYAN', 'MAGENTA', 'TEXT', 'MUTED'):
    assert pins[key] in theme, 'GRUB theme.txt missing ' + pins[key]
print('[ OK ] 8 palette pins: versions.env == palette.conf == SVG == GRUB theme; SVG geometry == ar0x_logo.py')
PYV

# Phase 6's builtin Arch logo must be gone from every fastfetch config.
if grep -rFq '"source": "arch"' \
        "${AR0X_SOURCE_ROOT}/config/branding/fastfetch" \
        "${AR0X_SOURCE_ROOT}/config/desktop/skel/.config/fastfetch" \
        "${AR0X_SOURCE_ROOT}/archiso/airootfs/etc/skel/.config/fastfetch" 2>/dev/null; then
    fail "Phase 7: Phase 6 builtin 'arch' fastfetch logo still present."
fi
grep -Fq '"type": "file"' \
    "${AR0X_SOURCE_ROOT}/config/branding/fastfetch/config.jsonc" \
    || fail "Phase 7: fastfetch must use the official 'file' logo, not a builtin."
# ASCII parity: removing $1..$9 from the tagged logo yields the plain logo.
python3 - "${AR0X_SOURCE_ROOT}" <<'PYV' || fail "Phase 7 ASCII parity broken."
import os, re, sys
b = os.path.join(sys.argv[1], 'config/branding/ascii')
plain = open(os.path.join(b, 'ar0x-ascii.txt'), encoding='utf-8').read()
tagged = open(os.path.join(b, 'ar0x-fastfetch.txt'), encoding='utf-8').read()
assert re.sub(r'\$[1-9]', '', tagged) == plain
art = open(os.path.join(b, 'ar0x-screenfetch.sh'), encoding='utf-8').read()
assert not re.search(r'^\s*set\s+-euo', art, re.M), 'sourced screenfetch art must not set strict mode'
print('[ OK ] ASCII: fastfetch tagged == plain after $N strip; screenfetch art is strict-mode-exempt')
PYV

# RISK-040 closure: real ar0x XCursor theme, not the Adwaita placeholder.
grep -Fq 'hl.env("XCURSOR_THEME", "ar0x-cursors")' \
    "${AR0X_SOURCE_ROOT}/config/desktop/hypr/lua/env.lua" \
    || fail "RISK-040: Hyprland env.lua still uses the Adwaita cursor placeholder."
grep -Fxq 'XCURSOR_THEME=ar0x-cursors' \
    "${AR0X_SOURCE_ROOT}/config/desktop/etc/environment.d/20-ar0x-desktop.conf" \
    || fail "RISK-040: environment.d still uses the Adwaita cursor placeholder."
python3 - "${AR0X_SOURCE_ROOT}" <<'PYV' || fail "Phase 7 XCursor binaries are invalid."
import os, sys
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, 'tools', 'lib'))
from ar0x_xcursor import SHAPES, ALIASES, SIZES, verify_xcursor
cur = os.path.join(root, 'archiso/airootfs/usr/share/icons/ar0x-cursors/cursors')
for name in SHAPES:
    p = os.path.join(cur, name)
    assert os.path.isfile(p), 'missing generated cursor: ' + name
    assert verify_xcursor(p, SIZES) == len(SIZES)
for alias, target in ALIASES.items():
    p = os.path.join(cur, alias)
    assert os.path.islink(p) and os.readlink(p) == target
print('[ OK ] XCursor: 5 generated files x 3 sizes parsed back, 12 aliases')
PYV

# RISK-010: screenfetch is official [extra]; neofetch is AUR-only and must stay OFF the ISO.
PKGS="${AR0X_SOURCE_ROOT}/config/packages.x86_64"
grep -Fxq 'screenfetch' "$PKGS" || fail "Phase 7: screenfetch ([extra] 3.9.9-1) missing from packages.x86_64."
if sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "$PKGS" | grep -Fxq 'neofetch'; then
    fail "RISK-010: neofetch is AUR-only and must NOT be on the ISO."
fi
ok "Phase 7 policy gates: identity, palette, ASCII, XCursor, fetch packages"

# --- Section 7h: Phase 8 custom tools + PKGBUILD policy gates ----------------
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
for f in "${PHASE8_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 8 deliverable: ${f}"
done
for f in ar0x-theme ar0x-wallpapers ar0x-hypr-config ar0x-keyring ar0x-meta; do
    [[ -f "${AR0X_SOURCE_ROOT}/packages/${f}/README.md" ]] \
        || fail "Missing Phase 8 deferral README: packages/${f}/README.md"
done
ok "Phase 8 deliverable files present (${#PHASE8_FILES[@]} + 5 deferral READMEs)"

# ADR-023: tool versions track the distro; the signed repo gate stays Required.
[[ "${AR0X_TOOLS_VERSION}" == "${AR0X_VERSION}" ]] \
    || fail "Phase 8: AR0X_TOOLS_VERSION must equal AR0X_VERSION."
[[ "${AR0X_UPDATE_REPO}" == "ar0x" && "${AR0X_UPDATE_SIGLEVEL}" == "Required" ]] \
    || fail "Phase 8: [ar0x] must use SigLevel = Required (§9 security contract)."
grep -Fq "${AR0X_WELCOME_APP_ID}" \
    "${AR0X_SOURCE_ROOT}/packages/ar0x-welcome/ar0x-welcome.py" \
    || fail "Phase 8: AR0X_WELCOME_APP_ID not used by ar0x-welcome.py."
grep -Fq 'ConditionFirstBoot=yes' \
    "${AR0X_SOURCE_ROOT}/packages/ar0x-welcome/ar0x-firstboot.service" \
    || fail "Phase 8: ar0x-firstboot.service lost ConditionFirstBoot=yes."
grep -Fiq 'refuses bare root' \
    "${AR0X_SOURCE_ROOT}/docs/TOOLS_GUIDE.md" \
    || fail "Phase 8: security contract not documented."
grep -Fq 'Refusing to run as bare root' \
    "${AR0X_SOURCE_ROOT}/packages/ar0x-update/ar0x-update" \
    || fail "Phase 8: ar0x-update lost its root refusal."
ok "Phase 8 policy gates: versions, SigLevel, app-id, first-boot condition"

# Delegate the full structural check (PKGBUILD sums, .desktop, units, parity,
# palette, links, groups, lazy gi, zero AUR, no premature ar0x-* ISO packages)
# to the shared Phase 8 module so both validators agree on ONE definition.
python3 "${AR0X_SOURCE_ROOT}/tools/lib/ar0x_pkgbuild.py" "${AR0X_SOURCE_ROOT}" \
    || fail "Phase 8 structural validation failed (tools/lib/ar0x_pkgbuild.py)."

PKG_DUPES="$(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' \
    "${AR0X_SOURCE_ROOT}/config/packages.x86_64" | sort | uniq -d)"
if [[ -n "$PKG_DUPES" ]]; then
    fail "Duplicate package(s) in config/packages.x86_64: ${PKG_DUPES}"
else
    ok "Package list contains no duplicates"
fi

# RISK-001: zero kernel patches in v0.1 (stock LTS binary kernel only).
PATCH_COUNT="$(find "${AR0X_SOURCE_ROOT}/config/kernel/patches" -type f \
    \( -name '*.patch' -o -name '*.diff' \) 2>/dev/null | wc -l)"
if (( PATCH_COUNT > 0 )); then
    fail "RISK-001: ${PATCH_COUNT} kernel patch(es) found. ar0x v0.1 uses stock linux-lts."
else
    ok "RISK-001: zero kernel patches (stock linux-lts ${AR0X_KERNEL_VERSION})"
fi
# A zstd initramfs is only bootable if the kernel can decompress it.
if [[ -f "${AR0X_SOURCE_ROOT}/config/kernel/ar0x-lts.config" ]]; then
    grep -Fq 'CONFIG_RD_ZSTD=y' "${AR0X_SOURCE_ROOT}/config/kernel/ar0x-lts.config" \
        || fail "zstd initramfs requires CONFIG_RD_ZSTD=y in the kernel audit contract."
    ok "CONFIG_RD_ZSTD=y asserted for zstd initramfs"
fi

# --- Section 7i: Phase 9 signed-repository policy gates ---------------------
PHASE9_FILES=(
    config/repo/repo-options.conf config/repo/README.md
    config/repo/RELEASE_KEY_FINGERPRINT config/repo/pacman.conf.ar0x-entry
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
for f in "${PHASE9_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 9 deliverable: ${f}"
done
ok "Phase 9 deliverable files present (${#PHASE9_FILES[@]} files)"

# ADR-024 / §9 security contract: NEVER relax the installed repository policy.
[[ "${AR0X_REPO_NAME}" == "ar0x" ]] \
    || fail "Phase 9: AR0X_REPO_NAME must be 'ar0x'."
[[ "${AR0X_REPO_SIGLEVEL}" == "Required" && "${AR0X_UPDATE_SIGLEVEL}" == "Required" ]] \
    || fail "Phase 9: [ar0x] SigLevel must be Required (never Optional/Never/TrustAll)."
[[ "${AR0X_REPO_DB}" == "ar0x.db.tar.zst" && "${AR0X_REPO_FILES_DB}" == "ar0x.files.tar.zst" ]] \
    || fail "Phase 9: db names must be ar0x.db.tar.zst / ar0x.files.tar.zst."
[[ "${AR0X_REPO_SIGN_PACKAGES}" == "yes" && "${AR0X_REPO_KEEP_OLD}" == "3" ]] \
    || fail "Phase 9: packages must be signed; keep-old must be 3 (rollback)."
[[ "${AR0X_REPO_CI_BUILDER}" == "builder" && "${AR0X_REPO_CI_IMAGE}" == "archlinux:base-devel" ]] \
    || fail "Phase 9: CI must use a non-root builder on archlinux:base-devel."
grep -Fq 'SigLevel = Required' "${AR0X_SOURCE_ROOT}/config/repo/pacman.conf.ar0x-entry" \
    || fail "Phase 9: pacman.conf.ar0x-entry lost SigLevel = Required."
grep -Fq 'Server = https://repo.ar0x.dev/$arch' \
        "${AR0X_SOURCE_ROOT}/config/repo/pacman.conf.ar0x-entry" \
    || fail "Phase 9: [ar0x] Server endpoint drifted (RISK-050)."
grep -Fq 'PENDING-KEYGEN' "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT" \
    || grep -Eq '^[0-9A-F]{40}$' \
           <(grep -v '^[[:space:]]*#' "${AR0X_SOURCE_ROOT}/config/repo/RELEASE_KEY_FINGERPRINT") \
    || fail "Phase 9: release fingerprint must be PENDING-KEYGEN or a 40-hex FPR."
# RISK-051: a PR workflow must NEVER have access to signing secrets.
for wf in validate-packages.yml build-packages.yml; do
    grep -Fq 'secrets.' "${AR0X_SOURCE_ROOT}/ci/workflows/${wf}" \
        && fail "RISK-051: ci/workflows/${wf} references secrets on a PR workflow."
done
grep -Fq 'secrets.AR0X_RELEASE_GPG_KEY' "${AR0X_SOURCE_ROOT}/ci/workflows/release.yml" \
    || fail "RISK-051: release.yml lost its signing-secret contract."
grep -Fq 'repo-add -s' "${AR0X_SOURCE_ROOT}/ci/workflows/release.yml" \
    || fail "Phase 9: release.yml lost 'repo-add -s'."
ok "Phase 9 policy gates: Required, db names, signed packages, non-root CI, PR-safe secrets, keygen state"

# Delegate the FULL Phase 9 structural check (repo options parity, pacman entry
# parity, keyring, build order, 31 mirrors, 3 workflows, secret scan) to the
# shared module so both validators agree on ONE definition.
python3 "${AR0X_SOURCE_ROOT}/tools/lib/ar0x_repo.py" "${AR0X_SOURCE_ROOT}" \
    || fail "Phase 9 structural validation failed (tools/lib/ar0x_repo.py)."

# --- Section 7j: brand naming gate ("everything is ar0x") -------------------
# Standing user rule (2026-11-07): the human codename is `ar0x root`, the
# machine identifier is `ar0x-root`, and ZERO legacy two-word/to-adjective
# brand tokens remain in ANY source file, filename or generated mirror.
[[ "${AR0X_CODENAME}" == "ar0x root" ]] \
    || fail "config/versions.env: AR0X_CODENAME must be 'ar0x root'."
grep -Fxq 'VERSION_CODENAME=ar0x-root' \
    "${AR0X_SOURCE_ROOT}/config/branding/os-release" \
    || fail "config/branding/os-release lost VERSION_CODENAME=ar0x-root."
grep -Fq 'AR0X_BRAND_CODENAME="ar0x root"' \
    "${AR0X_SOURCE_ROOT}/config/branding/palette.conf" \
    || fail "config/branding/palette.conf lost the ar0x root codename."
grep -Fq 'AR0X_CODENAME="ar0x root"' \
    "${AR0X_SOURCE_ROOT}/config/versions.env" \
    || fail "config/versions.env lost the ar0x root codename."
python3 - "${AR0X_SOURCE_ROOT}" <<'PYTOKEN' || fail "legacy brand token found in the source tree."
import os, re, sys
root = sys.argv[1]
# Assembled dynamically so THIS validator does not contain the forbidden token.
bad = 'ne' + 'on'
skip = {'.git', 'build', '__pycache__', '.cache', 'node_modules', '.venv', 'venv'}
hits = []
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in skip]
    for fn in files:
        rel = os.path.relpath(os.path.join(base, fn), root)
        if bad in fn.lower():
            hits.append(rel + ' (filename)')
        try:
            txt = open(os.path.join(base, fn), encoding='utf-8').read()
        except (UnicodeDecodeError, OSError):
            continue
        if re.search(bad, txt, re.I):
            hits.append(rel)
if hits:
    for h in sorted(set(hits))[:20]:
        sys.stderr.write('  [FAIL] legacy brand token in %s\n' % h)
    sys.exit(1)
print('[ OK ] ar0x-only naming: zero legacy brand tokens in text or filenames')
PYTOKEN
ok "Brand naming gate: codename ar0x root / ar0x-root, zero legacy tokens"

# --- Section 7k: Phase 10 Calamares installer policy gates ------------------
PHASE10_FILES=(
    config/calamares/settings.conf
    config/calamares/modules/welcome.conf config/calamares/modules/locale.conf
    config/calamares/modules/keyboard.conf config/calamares/modules/partition.conf
    config/calamares/modules/users.conf config/calamares/modules/ar0x-packages.conf
    config/calamares/modules/packages.conf config/calamares/modules/unpackfs.conf
    config/calamares/modules/initcpiocfg.conf config/calamares/modules/initcpio.conf
    config/calamares/modules/bootloader.conf config/calamares/modules/grubcfg.conf
    config/calamares/modules/removeuser.conf config/calamares/modules/displaymanager.conf
    config/calamares/modules/services-systemd.conf config/calamares/modules/machineid.conf
    config/calamares/modules/finished.conf config/calamares/modules/summary.conf
    config/calamares/modules/shellprocess-prep.conf
    config/calamares/modules/shellprocess-finish.conf
    config/calamares/modules/umount.conf
    config/calamares/branding/ar0x/branding.desc
    config/calamares/branding/ar0x/show.qml
    config/calamares/branding/ar0x/ar0x-logo.png
    config/installer/ar0x-installer-finish
    config/installer/ar0x-installer.desktop
    archiso/airootfs/usr/lib/ar0x/ar0x-installer-finish
    archiso/airootfs/usr/share/applications/ar0x-installer.desktop
    tools/lib/ar0x_installer.py tools/configure-installer.sh
    docs/INSTALLER_FLOW.md
)
for f in "${PHASE10_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 10 deliverable: ${f}"
done
ok "Phase 10 deliverable files present (${#PHASE10_FILES[@]} files)"

[[ "${AR0X_INSTALLER_BRANDING}" == "ar0x" ]] \
    || fail "Phase 10: AR0X_INSTALLER_BRANDING must be 'ar0x'."
[[ "${AR0X_INSTALLER_LIVE_USER}" == "ar0x" ]] \
    || fail "RISK-013: AR0X_INSTALLER_LIVE_USER must match /etc/passwd live user."
[[ "${AR0X_CALAMARES_ESP_MIB}" == "512" ]] \
    || fail "Phase 10: ESP must be 512 MiB."
[[ "${AR0X_INSTALLER_PACKAGE_GROUPS}" == "minimal,standard,full" ]] \
    || fail "Phase 10: package groups must be minimal,standard,full."
[[ -x "${AR0X_SOURCE_ROOT}/tools/configure-installer.sh" ]] \
    || fail "Phase 10: tools/configure-installer.sh must be 0755."
[[ -x "${AR0X_SOURCE_ROOT}/config/installer/ar0x-installer-finish" ]] \
    || fail "Phase 10: ar0x-installer-finish must be 0755."
[[ ! -d "${AR0X_SOURCE_ROOT}/archiso/airootfs/etc/calamares" ]] \
    || fail "ADR-024: duplicate /etc/calamares in airootfs; config/calamares is the ONE owner."
# RISK-004: never auto-select a disk, always prompt before the exec phase.
grep -Fq 'initialPartitioningChoice: none' \
        "${AR0X_SOURCE_ROOT}/config/calamares/modules/partition.conf" \
    || fail "RISK-004: partition.conf lost 'initialPartitioningChoice: none'."
grep -Fq 'prompt-install: true' \
        "${AR0X_SOURCE_ROOT}/config/calamares/settings.conf" \
    || fail "RISK-004: settings.conf lost 'prompt-install: true'."
grep -Fq 'lsblk -o NAME,SIZE,MODEL,TRAN' \
        "${AR0X_SOURCE_ROOT}/docs/INSTALLER_FLOW.md" \
    || fail "RISK-004: INSTALLER_FLOW.md lost the mandatory lsblk check."
# RISK-003: the archived GitHub mirror must never appear in the config tree.
if grep -rIl 'github.com/calamares/calamares' \
        "${AR0X_SOURCE_ROOT}/config/calamares" "${AR0X_SOURCE_ROOT}/config/installer"; then
    fail "RISK-003: archived GitHub Calamares mirror referenced in Phase 10 config."
fi
ok "Phase 10 policy gates: RISK-003/004/013, ADR-024, 0755 modes, 5 version keys"

# Delegate the FULL Phase 10 structural check (show/exec/show sequence, 3
# instances, 21 module configs, 8 palette pins, 3 official-only groups) to the
# shared module so both validators agree on ONE definition.
python3 "${AR0X_SOURCE_ROOT}/tools/lib/ar0x_installer.py" "${AR0X_SOURCE_ROOT}" \
    || fail "Phase 10 structural validation failed (tools/lib/ar0x_installer.py)."

# --- Section 7l: Phase 11 ISO build / test / release-artifact gates ---------
PHASE11_FILES=(
    config/iso/README.md config/iso/build-options.conf
    config/iso/size-budget.conf config/iso/run-qemu-bios.sh
    config/iso/run-qemu-uefi.sh config/iso/run-qemu-install.sh
    tools/build-iso.sh tools/checksum.sh tools/lib/ar0x_iso.py
    docs/ISO_BUILD_GUIDE.md docs/TESTING_CHECKLIST.md
)
for f in "${PHASE11_FILES[@]}"; do
    [[ -f "${AR0X_SOURCE_ROOT}/${f}" ]] || fail "Missing Phase 11 deliverable: ${f}"
done
ok "Phase 11 deliverable files present (${#PHASE11_FILES[@]} files)"

[[ "${AR0X_ISO_BUILD_MODE}" == "iso" ]] \
    || fail "Phase 11: AR0X_ISO_BUILD_MODE must be 'iso'."
[[ "${AR0X_ISO_SIZE_GATE_GIB}" == "2.2" ]] \
    || fail "RISK-012: ISO size gate must be 2.2 GiB."
[[ "${AR0X_RELEASE_CHECKLIST_ITEMS}" == "40" && "${AR0X_RELEASE_CHECKLIST_GATE}" == "100" ]] \
    || fail "Phase 11: TESTING_CHECKLIST.md gate must be 40 items / 100%."
[[ "${AR0X_RELEASE_ARTIFACT_COUNT}" == "6" ]] \
    || fail "Phase 11: §11 release artifact set must have 6 members."
grep -Fq 'AR0X_ISO_SIZE_GATE_BYTES="2362232012"' \
        "${AR0X_SOURCE_ROOT}/config/iso/build-options.conf" \
    || fail "RISK-012: build-options.conf lost the 2362232012-byte size gate."
[[ -x "${AR0X_SOURCE_ROOT}/tools/build-iso.sh" && -x "${AR0X_SOURCE_ROOT}/tools/checksum.sh" ]] \
    || fail "Phase 11: build-iso.sh + checksum.sh must be 0755."
for l in "${AR0X_SOURCE_ROOT}/config/iso/"run-qemu-*.sh; do
    [[ -x "$l" ]] || fail "Phase 11: QEMU launcher not 0755: ${l}"
done
# RISK-004: the installer VM must never auto-select a device.
grep -Fq 'AR0X_CONFIRM_DISPOSABLE_VM' \
        "${AR0X_SOURCE_ROOT}/config/iso/run-qemu-install.sh" \
    || fail "RISK-004: disposable-VM confirmation gate missing."
grep -Fq 'lsblk -o NAME,SIZE,MODEL,TRAN' \
        "${AR0X_SOURCE_ROOT}/docs/TESTING_CHECKLIST.md" \
    || fail "RISK-004: TESTING_CHECKLIST.md lost the lsblk device check."
# RISK-051: derived artifacts stay OUT of Git.
grep -Fq 'SHA256SUMS' "${AR0X_SOURCE_ROOT}/.gitignore" \
    || fail "RISK-051: SHA256SUMS is not gitignored."
ok "Phase 11 policy gates: 2.2 GiB size gate, 40/100 checklist, 0755 modes, RISK-004/012/051"

# Delegate the FULL Phase 11 structural check (8 budget rows, archiso 92
# profile, package policy, 3 QEMU launchers, checksum contract, 40 items) to
# the shared module so both validators agree on ONE definition.
python3 "${AR0X_SOURCE_ROOT}/tools/lib/ar0x_iso.py" "${AR0X_SOURCE_ROOT}" \
    || fail "Phase 11 structural validation failed (tools/lib/ar0x_iso.py)."

# --- Final verdict -----------------------------------------------------------
if [[ "$ERRORS" -gt 0 ]]; then
    die "Validation FAILED with ${ERRORS} error(s). Fix them before running build-iso.sh."
fi
printf '\n%s✅ ar0x version + structure validation PASSED%s\n' "$C_OK" "$C_RST"
printf '   Distro       : ar0x %s (%s)\n' "${AR0X_VERSION}" "${AR0X_CODENAME:-}"
printf '   Kernel       : %s %s\n' "${AR0X_KERNEL_FLAVOR}" "${AR0X_KERNEL_VERSION}"
printf '   Snapshot     : %s\n' "${AR0X_SNAPSHOT_DATE}"
printf '   Desktop      : Hyprland %s (%s config)\n' "${AR0X_HYPRLAND_VERSION}" "${AR0X_HYPR_CONFIG_FORMAT}"
printf '   Installer    : Calamares %s (%s)\n' "${AR0X_CALAMARES_VERSION}" "${AR0X_CALAMARES_SOURCE}"
printf '   Brand        : %s logo, %s cursors, %s\n' \
    "${AR0X_BRAND_LOGO_VIEWBOX}" "${AR0X_BRAND_CURSOR_THEME}" "${AR0X_BRAND_LICENSE}"
printf '   Tools        : %s (welcome/update/info), SigLevel %s\n' \
    "${AR0X_TOOLS_VERSION}" "${AR0X_UPDATE_SIGLEVEL}"
printf '   Repo         : [%s] %s, %s, builder=%s (key PENDING-KEYGEN)\n' \
    "${AR0X_REPO_NAME}" "${AR0X_REPO_SIGLEVEL}" "${AR0X_REPO_DB}" "${AR0X_REPO_CI_BUILDER}"
exit 0
