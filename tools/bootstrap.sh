#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/bootstrap.sh
# -----------------------------------------------------------------------------
# PHASE 3 — ar0x base system bootstrap (Arch / archiso 92).
#
# What it does:
#   1. Validates the canonical files in config/ and the archiso/ profile.
#   2. Stages a DISPOSABLE profile at /opt/ar0x-build/profile/ so mkarchiso
#      never writes generated files back into the Git checkout.
#   3. Renders config/pacman.conf.build -> <stage>/pacman.conf, substituting
#      the local [ar0x] repo path and dropping the [ar0x] repo block when that
#      repo database does not exist yet (Phase 3 has no HARD-pinned packages).
#   4. Overlays config/system/** -> <stage>/airootfs/etc/** (1:1 rule,
#      BUILD_LAYOUT.md §4) and config/desktop/skel/** -> /etc/skel/**.
#   5. Runs mkarchiso as root with a fixed SOURCE_DATE_EPOCH derived from the
#      frozen snapshot date, producing:
#        /opt/ar0x-build/work/x86_64/airootfs        (the chroot-able base root)
#        /opt/ar0x-build/out/ar0x-bootstrap-0.1.0-x86_64.tar.zst
#        /opt/ar0x-build/out/ar0x-0.1.0-x86_64.iso
#   6. Writes /opt/ar0x-build/out/packages.lock from `pacman -Q --sysroot`.
#
# Subcommands / flags:
#   --check                 Read-only validation; NO root, NO writes.
#   --sync                  Regenerate archiso/{pacman.conf,packages.x86_64,
#                           bootstrap_packages.x86_64} from config/ (no root).
#   --clean                 ⚠️ Delete the whole work/ dir (destructive, asks first).
#   --base-only             mkarchiso -m bootstrap (tarball only)
#   --iso-only              mkarchiso -m iso (ISO + airootfs only)
#   --with-ar0x-repo        Force-keep the [ar0x] repo block
#   --no-ar0x-repo          Force-drop the [ar0x] repo block
#   chroot [CMD...]         arch-chroot into work/x86_64/airootfs (root needed)
#   (default)               Run stages 1-6 with both build modes.
#
# ⚠️ MANUAL: the default run needs ROOT, `mkarchiso`, loop devices and ~40 GiB.
# It CANNOT execute in the Arena sandbox. `--check` and `--sync` can.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Section 0: shared library + canonical paths -----------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${SCRIPT_DIR}/.." && pwd -P)}"
export AR0X_SOURCE_ROOT
# shellcheck source=tools/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Disposable staged profile. mkarchiso writes into work/, not into the checkout.
export AR0X_PROFILE_STAGE="${AR0X_PROFILE_STAGE:-${AR0X_BUILD_ROOT}/profile}"

PROFILE="${AR0X_PROFILE}"
STAGE="${AR0X_PROFILE_STAGE}"
AIROOTFS="${AR0X_WORK_DIR}/x86_64/airootfs"
BUILD_CONF="${AR0X_CONFIG_DIR}/pacman.conf.build"
INSTALL_CONF="${AR0X_CONFIG_DIR}/pacman.conf.installed"
LOG_FILE="${AR0X_LOG_DIR}/02-bootstrap.log"

# --- Section 1: CLI parsing ---------------------------------------------------
MODE="build"
MKISO_MODES="bootstrap iso"
FORCE_REPO=""
CHROOT_CMD=()

usage() {
    cat <<'USAGE'
ar0x Phase 3 — bootstrap.sh

  (no args)            Full base bootstrap: stage profile + mkarchiso + lockfile.
  --check              Read-only validation. No root, no writes.
  --sync               Regenerate the 3 generated files in archiso/ from config/.
  --clean              ⚠️ Delete /opt/ar0x-build/work (asks for confirmation).
  --base-only          mkarchiso -m bootstrap (minimal root tarball only).
  --iso-only           mkarchiso -m iso (ISO + chroot-able airootfs).
  --with-ar0x-repo     Keep the [ar0x] repo block even if its db is missing.
  --no-ar0x-repo       Drop the [ar0x] repo block even if its db exists.
  chroot [CMD...]      arch-chroot into work/x86_64/airootfs. Without CMD an
                       interactive /bin/bash is started. Needs root.
  -h | --help          Show this help.

Examples:
  ./tools/bootstrap.sh --check
  ./tools/bootstrap.sh --sync
  sudo ./tools/bootstrap.sh
  sudo ./tools/bootstrap.sh chroot pacman -Q | wc -l
USAGE
}

while (( $# > 0 )); do
    case "$1" in
        --check)           MODE="check" ;;
        --sync)            MODE="sync" ;;
        --clean)           MODE="clean" ;;
        --base-only)       MKISO_MODES="bootstrap" ;;
        --iso-only)        MKISO_MODES="iso" ;;
        --with-ar0x-repo)  FORCE_REPO="yes" ;;
        --no-ar0x-repo)    FORCE_REPO="no" ;;
        chroot)            MODE="chroot"; shift; CHROOT_CMD=("$@"); break ;;
        -h|--help)         usage; exit 0 ;;
        *)                 die "Unknown option: $1 (try --help)." ;;
    esac
    shift
done

# --- Section 2: small helpers -------------------------------------------------
# pkg_in_list <file> <name> — exact-line match on the stripped package list.
pkg_in_list() {
    sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "$1" | grep -Fxq -- "$2"
}

# overlay <src> <dst> — copy a config subtree, dropping skeleton placeholders.
overlay() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    install -d -m 0755 "$dst"
    cp -af -- "$src/." "$dst/"
    find "$dst" -type f -name '.gitkeep' -delete 2>/dev/null || true
}

# ar0x_repo_db_present — the [ar0x] db is created by repo-add in Phase 9.
ar0x_repo_db_present() {
    [[ -f "${AR0X_REPO_DIR}/ar0x.db" || -f "${AR0X_REPO_DIR}/ar0x.db.tar.zst" ]]
}

# --- Section 3: static validation (used by --check AND every build) ----------
validate_static() {
    section "Validating canonical Phase 3 files"

    local required=(
        "${AR0X_CONFIG_DIR}/versions.env"
        "${BUILD_CONF}"
        "${AR0X_CONFIG_DIR}/packages.x86_64"
        "${AR0X_CONFIG_DIR}/bootstrap_packages.x86_64"
        "${PROFILE}/profiledef.sh"
        "${PROFILE}/pacman.conf"
        "${PROFILE}/packages.x86_64"
        "${PROFILE}/bootstrap_packages.x86_64"
        "${PROFILE}/grub/grub.cfg"
        "${PROFILE}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
    )
    for f in "${required[@]}"; do
        [[ -f "$f" ]] && ok "$(realpath --relative-to="$AR0X_SOURCE_ROOT" "$f")" \
                      || fail "Missing required file: $f"
    done

    # syslinux/ must contain at least one *.cfg (archiso 92 validation rule).
    local cfg_count
    cfg_count="$(find "${PROFILE}/syslinux" -maxdepth 1 -type f -name '*.cfg' 2>/dev/null | wc -l)"
    if (( cfg_count < 1 )); then fail "No *.cfg in archiso/syslinux/ (required by bootmodes bios.syslinux)."; fi
    ok "archiso/syslinux/ has ${cfg_count} *.cfg file(s)"

    # profiledef.sh must be valid bash but is SOURCED by mkarchiso, so it must
    # NOT contain strict-mode statements that would leak into mkarchiso.
    bash -n "${PROFILE}/profiledef.sh" || fail "profiledef.sh has a bash syntax error."
    if grep -Eq '^[[:space:]]*set[[:space:]]+-euo' "${PROFILE}/profiledef.sh"; then
        fail "profiledef.sh must NOT set -euo pipefail (it is sourced by mkarchiso)."
    fi
    ok "profiledef.sh parses and contains no strict-mode leak"

    # Read the profile variables in a clean subshell.
    local pv iso_version iso_label install_dir image_type buildmodes bootmodes
    pv="$(bash -c 'set -euo pipefail; declare -A file_permissions=(); source "$1"; printf "%s|%s|%s|%s|%s|%s\n" \
            "$iso_version" "$iso_label" "$install_dir" "$airootfs_image_type" \
            "${buildmodes[*]}" "${bootmodes[*]}"' _ "${PROFILE}/profiledef.sh")"
    IFS='|' read -r iso_version iso_label install_dir image_type buildmodes bootmodes <<<"$pv"

    [[ "$iso_version" == "$AR0X_VERSION" ]] || fail "iso_version '${iso_version}' != AR0X_VERSION '${AR0X_VERSION}'."
    [[ "$iso_label"  == "$AR0X_ISO_LABEL" ]] || fail "iso_label '${iso_label}' != AR0X_ISO_LABEL '${AR0X_ISO_LABEL}'."
    [[ "$image_type" == "$AR0X_ARCHISO_AIROOTFS_TYPE" ]] || fail "airootfs_image_type mismatch."
    [[ "$install_dir" == "$AR0X_INSTALL_DIR" ]] || fail "install_dir '${install_dir}' != AR0X_INSTALL_DIR '${AR0X_INSTALL_DIR}'."
    # archiso 92: install_dir must match ^[a-z0-9]+$ and be <= 30 chars.
    [[ "$install_dir" =~ ^[a-z0-9]+$ ]] || fail "install_dir '${install_dir}' must match ^[a-z0-9]+$ (archiso 92)."
    (( ${#install_dir} <= 30 )) || fail "install_dir exceeds 30 characters."
    [[ " $buildmodes " == *" iso "* ]] || fail "buildmodes must contain 'iso' (needed for the chroot-able airootfs)."
    [[ " $bootmodes " == *" bios.syslinux "* ]] || fail "bootmodes must contain 'bios.syslinux'."
    [[ " $bootmodes " == *" uefi.grub "* ]] || fail "bootmodes must contain 'uefi.grub'."
    [[ " $bootmodes " != *" uefi.systemd-boot "* ]] || fail "uefi.grub and uefi.systemd-boot are mutually exclusive in archiso 92."
    ok "profiledef.sh contract: install_dir=${install_dir}, buildmodes=(${buildmodes}), bootmodes=(${bootmodes})"

    # Mandatory packages (verified against archiso 92 source).
    local p
    for p in base linux-lts mkinitcpio mkinitcpio-archiso syslinux grub; do
        pkg_in_list "${AR0X_CONFIG_DIR}/packages.x86_64" "$p" \
            || fail "Mandatory package '${p}' missing from config/packages.x86_64."
    done
    ok "All 6 mandatory packages present in config/packages.x86_64"
    # A duplicate package line is harmless to pacman but is a real maintenance
    # smell in a phase-by-phase list (Phase 5 initially re-added apparmor).
    local dupes
    dupes="$(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/packages.x86_64" \
             | sort | uniq -d)"
    [[ -z "$dupes" ]] || fail "Duplicate package(s) in config/packages.x86_64: ${dupes}"
    local pkg_count
    pkg_count="$(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/packages.x86_64" | wc -l)"
    ok "Package list: ${pkg_count} unique packages (no duplicates)"
    local bcount
    bcount="$(sed '/^[[:blank:]]*#.*/d;s/#.*//;/^[[:blank:]]*$/d' "${AR0X_CONFIG_DIR}/bootstrap_packages.x86_64" | wc -l)"
    (( bcount > 0 )) || fail "bootstrap_packages.x86_64 is empty (archiso 92 requires >= 1)."
    ok "bootstrap_packages.x86_64 has ${bcount} package(s)"

    # Frozen mirror + ADR-017 repo ordering.
    grep -Fq "archive.archlinux.org/repos/${AR0X_SNAPSHOT_DATE}/\$repo/os/\$arch" "$BUILD_CONF" \
        || fail "config/pacman.conf.build does not pin the frozen snapshot ${AR0X_SNAPSHOT_DATE}."
    grep -Fq "# --- BEGIN AR0X_REPO_BLOCK" "$BUILD_CONF" \
        || fail "config/pacman.conf.build is missing the [ar0x] repo block (ADR-017)."
    local ar0x_line core_line
    ar0x_line="$(grep -n '^\[ar0x\]' "$BUILD_CONF" | head -1 | cut -d: -f1)"
    core_line="$(grep -n '^\[core\]' "$BUILD_CONF" | head -1 | cut -d: -f1)"
    [[ -n "$ar0x_line" && -n "$core_line" && "$ar0x_line" -lt "$core_line" ]] \
        || fail "ADR-017: [ar0x] must be listed BEFORE [core] in pacman.conf.build."
    ok "Frozen mirror ${AR0X_SNAPSHOT_DATE} pinned; [ar0x] listed before [core]"

    # RISK-006: the installed pacman.conf must never contain the frozen mirror.
    if [[ -f "$INSTALL_CONF" ]]; then
        grep -v '^[[:space:]]*#' "$INSTALL_CONF" | grep -Fq "archive.archlinux.org" \
            && fail "RISK-006: config/pacman.conf.installed contains a frozen archive mirror." \
            || ok "Installed pacman.conf has no frozen mirror"
    else
        warn "config/pacman.conf.installed does not exist yet (expected: Phase 5/9)."
    fi

    # Deprecated archiso 92 customization path.
    if [[ -e "${PROFILE}/airootfs/root/customize_airootfs.sh" ]]; then
        fail "archiso 92 deprecates customize_airootfs.sh. Use airootfs/etc/pacman.d/hooks/ instead."
    else
        ok "No deprecated customize_airootfs.sh (pacman hooks used instead)"
    fi

    # Sync state between config/ (canonical) and archiso/ (generated copies).
    local sync_ok=1
    if ! diff -q "${AR0X_CONFIG_DIR}/packages.x86_64" "${PROFILE}/packages.x86_64" >/dev/null 2>&1; then
        fail "archiso/packages.x86_64 is out of sync with config/packages.x86_64 (run --sync)."
        sync_ok=0
    fi
    if ! diff -q <(sed "s|@AR0X_REPO_DIR@|${AR0X_REPO_DIR}|g" "$BUILD_CONF") \
                  "${PROFILE}/pacman.conf" >/dev/null 2>&1; then
        fail "archiso/pacman.conf is out of sync with config/pacman.conf.build (run --sync)."
        sync_ok=0
    fi
    if (( sync_ok )); then
        ok "config/ and archiso/ are in sync"
    fi
}

# --- Section 4: --sync (no root, writes only into the source tree) -----------
sync_profile_files() {
    section "Syncing archiso/ generated files from config/"
    sed "s|@AR0X_REPO_DIR@|${AR0X_REPO_DIR}|g" "$BUILD_CONF" > "${PROFILE}/pacman.conf"
    cp -f -- "${AR0X_CONFIG_DIR}/packages.x86_64" "${PROFILE}/packages.x86_64"
    cp -f -- "${AR0X_CONFIG_DIR}/bootstrap_packages.x86_64" "${PROFILE}/bootstrap_packages.x86_64"
    ok "archiso/pacman.conf, packages.x86_64, bootstrap_packages.x86_64 regenerated"
    log "NOTE: archiso/profiledef.sh is canonical and is NOT regenerated."
}

# --- Section 5: stage a disposable profile ----------------------------------
stage_profile() {
    section "Staging disposable profile at ${STAGE}"
    install -d -m 0755 "$AR0X_BUILD_ROOT" "$AR0X_WORK_DIR" "$AR0X_OUT_DIR" "$AR0X_LOG_DIR"
    rm -rf -- "$STAGE"
    install -d -m 0755 "$STAGE"
    cp -af -- "${PROFILE}/." "$STAGE/"

    # Placeholder .gitkeep files must never end up in the ISO's root filesystem.
    find "$STAGE" -type f -name '.gitkeep' -delete 2>/dev/null || true

    # Render the build pacman.conf with the real [ar0x] repo path.
    sed "s|@AR0X_REPO_DIR@|${AR0X_REPO_DIR}|g" "$BUILD_CONF" > "${STAGE}/pacman.conf"

    # Decide whether the [ar0x] repo db is usable. In Phase 3 it is NOT
    # (Phases 8/9 build those packages); including a non-existent db would
    # make `pacman -Sy` abort with "failed to synchronize all databases".
    local keep_repo="no"
    if [[ "$FORCE_REPO" == "yes" ]]; then
        keep_repo="yes"
    elif [[ "$FORCE_REPO" == "no" ]]; then
        keep_repo="no"
    elif ar0x_repo_db_present; then
        keep_repo="yes"
    fi

    if [[ "$keep_repo" == "no" ]]; then
        sed -i '/# --- BEGIN AR0X_REPO_BLOCK/,/# --- END AR0X_REPO_BLOCK/d' "${STAGE}/pacman.conf"
        warn "[ar0x] repo block DROPPED from the staged pacman.conf: no repo db yet (ADR-017)."
        warn "Phase 11's build-iso.sh re-adds it after Phases 8/9 build the HARD-pinned packages."
    else
        ok "[ar0x] repo block kept (found a repo db in ${AR0X_REPO_DIR})"
    fi

    # 1:1 overlay rule (BUILD_LAYOUT.md §4). These are no-ops in Phase 3 (only
    # .gitkeep exists) and become active in Phases 5/6/7/10 without edits here.
    overlay "${AR0X_CONFIG_DIR}/system" "${STAGE}/airootfs/etc"
    overlay "${AR0X_CONFIG_DIR}/desktop/skel" "${STAGE}/airootfs/etc/skel"
    overlay "${AR0X_ASSETS_DIR}/plymouth/ar0x" "${STAGE}/airootfs/usr/share/plymouth/themes/ar0x"
    # ⚠️ NOT /boot: mkarchiso::_cleanup_pacstrap_dir deletes everything under
    # <airootfs>/boot before squashing. GRUB theme art lives in /usr/share here
    # and Phase 7 stages it into the ISO's boot path explicitly.
    overlay "${AR0X_ASSETS_DIR}/grub-theme/ar0x" "${STAGE}/airootfs/usr/share/grub/themes/ar0x"
    overlay "${AR0X_ASSETS_DIR}/sddm/ar0x" "${STAGE}/airootfs/usr/share/sddm/themes/ar0x"
    overlay "${AR0X_ASSETS_DIR}/wallpapers" "${STAGE}/airootfs/usr/share/backgrounds/ar0x"
    overlay "${AR0X_CONFIG_DIR}/calamares" "${STAGE}/airootfs/etc/calamares"

    # Branding files land directly in /etc (Phase 7). Copy only real files.
    local b
    for b in os-release lsb-release issue motd; do
        if [[ -f "${AR0X_CONFIG_DIR}/branding/$b" ]]; then
            install -m 0644 -- "${AR0X_CONFIG_DIR}/branding/$b" "${STAGE}/airootfs/etc/$b"
        fi
    done

    find "$STAGE/airootfs" -type f -name '.gitkeep' -delete 2>/dev/null || true
    ok "Staged profile ready (work/ and the Git checkout stay clean)"
}

# --- Section 6: run mkarchiso ------------------------------------------------
run_mkarchiso() {
    section "Running mkarchiso (buildmodes: ${MKISO_MODES})"
    require_root
    require_command mkarchiso
    require_command pacstrap
    require_command zstd
    require_free_space "$AR0X_WORK_DIR" "$(( 40 * 1024 * 1024 * 1024 ))"
    check_mount_options "$AR0X_WORK_DIR"

    # Fixed epoch => deterministic ISO timestamps / reproducible builds.
    local snapshot_iso="${AR0X_SNAPSHOT_DATE//\//-}"
    export SOURCE_DATE_EPOCH="$(date -u -d "$snapshot_iso" +%s)"
    ok "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} (${snapshot_iso} 00:00 UTC)"

    log "Command: mkarchiso -v -m \"${MKISO_MODES}\" -w ${AR0X_WORK_DIR} -o ${AR0X_OUT_DIR} ${STAGE}"
    mkarchiso -v -m "${MKISO_MODES}" \
              -w "${AR0X_WORK_DIR}" -o "${AR0X_OUT_DIR}" "${STAGE}" \
        2>&1 | tee -a "$LOG_FILE"
    ok "mkarchiso completed (log: ${LOG_FILE})"
}

# --- Section 7: reproducibility lockfile ------------------------------------
write_lockfile() {
    section "Writing packages.lock"
    if [[ -d "$AIROOTFS" ]]; then
        pacman -Q --sysroot "$AIROOTFS" > "${AR0X_OUT_DIR}/packages.lock" 2>/dev/null \
            || warn "pacman -Q --sysroot failed (mkarchiso's cleanup removes the sync DB); pkglist.x86_64.txt in work/iso/ is the fallback."
        ok "packages.lock: $(wc -l < "${AR0X_OUT_DIR}/packages.lock" 2>/dev/null || printf '0') packages"
    else
        warn "airootfs not present (did you use --base-only?); skipping packages.lock."
    fi
}

# --- Section 8: chroot helper ------------------------------------------------
do_chroot() {
    section "arch-chroot into ${AIROOTFS}"
    require_root
    require_command arch-chroot
    [[ -d "$AIROOTFS" ]] || die "No airootfs at ${AIROOTFS}. Run the iso buildmode first: sudo ./tools/bootstrap.sh --iso-only"

    # mkarchiso's cleanup removes /boot and the pacman sync DB, so note what
    # works and what does not inside the chroot.
    warn "mkarchiso cleaned /boot and /var/lib/pacman/sync in this root."
    warn "Use 'pacman -Q' (local DB) freely; 'pacman -S' needs 'pacman -Sy' first."

    if [[ ! -s "${AIROOTFS}/etc/resolv.conf" ]]; then
        # arch-chroot does NOT copy resolv.conf. This is a temporary test-only
        # mutation of the staged root; it is removed by the next clean build.
        cp -L -- /etc/resolv.conf "${AIROOTFS}/etc/resolv.conf"
        warn "Copied host /etc/resolv.conf into the staged root for DNS (test-only)."
    fi

    if (( ${#CHROOT_CMD[@]} > 0 )); then
        log "arch-chroot ${AIROOTFS} ${CHROOT_CMD[*]}"
        arch-chroot "$AIROOTFS" "${CHROOT_CMD[@]}"
    else
        log "Starting interactive /bin/bash. Type 'exit' to leave."
        arch-chroot "$AIROOTFS" /bin/bash
    fi
}

# --- Section 9: --clean (destructive) ---------------------------------------
do_clean() {
    printf '\n%s⚠️  This DELETES %s (10-25 GiB of mkarchiso scratch data).%s\n' \
        "$_AR0X_C_WARN" "$AR0X_WORK_DIR" "$_AR0X_C_RST"
    read -r -p '    Type DELETE to confirm: ' reply
    [[ "$reply" == "DELETE" ]] || die "Aborted."
    rm -rf -- "${AR0X_WORK_DIR:?}" "$STAGE"
    ok "Work directory and staged profile removed"
}

# --- Section 10: dispatch ----------------------------------------------------
case "$MODE" in
    check)
        validate_static
        assert_clean
        section "CHECK MODE — no root, no writes"
        printf 'Would stage:  %s\n' "$STAGE"
        printf 'Would run:    mkarchiso -v -m "%s" -w %s -o %s %s\n' \
            "$MKISO_MODES" "$AR0X_WORK_DIR" "$AR0X_OUT_DIR" "$STAGE"
        printf 'Would create: %s/x86_64/airootfs  (arch-chroot target)\n' "$AR0X_WORK_DIR"
        printf 'Would create: %s/packages.lock\n' "$AR0X_OUT_DIR"
        printf '\n%s✅ Phase 3 --check PASSED%s\n' "$_AR0X_C_OK" "$_AR0X_C_RST"
        exit 0
        ;;
    sync)
        # Sync FIRST so the consistency check does not report the very drift
        # this mode is meant to fix (and accumulate stale AR0X_FAILURES).
        sync_profile_files
        validate_static
        assert_clean
        ok "Phase 3 --sync complete"
        exit 0
        ;;
    clean)
        do_clean
        exit 0
        ;;
    chroot)
        do_chroot
        exit 0
        ;;
    build)
        validate_static
        assert_clean
        stage_profile
        run_mkarchiso
        write_lockfile
        cat <<EOF

${_AR0X_C_OK}✅ Phase 3 base bootstrap complete.${_AR0X_C_RST}

  Base root (chroot target) : ${AIROOTFS}
  ISO                       : ${AR0X_OUT_DIR}/ar0x-${AR0X_VERSION}-x86_64.iso
  Bootstrap tarball         : ${AR0X_OUT_DIR}/ar0x-bootstrap-${AR0X_VERSION}-x86_64.tar.zst
  Package lockfile          : ${AR0X_OUT_DIR}/packages.lock
  Build log                 : ${LOG_FILE}

Chroot for testing:
  sudo ./tools/bootstrap.sh chroot
  sudo ./tools/bootstrap.sh chroot pacman -Q
  sudo ./tools/bootstrap.sh chroot systemctl list-unit-files

⚠️ MANUAL: this bootstrap smoke test is NOT the release ISO. Phases 4-10 add
   the kernel/boot branding, system configs, desktop, tools, repo and installer;
   Phase 11 rebuilds the ISO from the accumulated package list.
EOF
        exit 0
        ;;
esac
