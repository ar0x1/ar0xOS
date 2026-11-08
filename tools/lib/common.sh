#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/tools/lib/common.sh
# -----------------------------------------------------------------------------
# Phase 2 — shared library sourced by EVERY tools/*.sh script.
#
# It provides:
#   * the canonical AR0X_* environment variables (docs/architecture/BUILD_LAYOUT.md §5)
#   * sourcing of config/versions.env (the single source of version pins)
#   * colour logging helpers: log / section / ok / warn / die / fail
#   * preflight helpers: require_root / require_arch_host / require_command /
#     have_command / require_free_space / check_mount_options / human_bytes
#
# This file is SOURCED, never executed directly. It still carries the mandated
# shebang + `set -euo pipefail` (enforced by tools/validate-versions.sh) so that
# every consumer gets identical strict-mode behaviour.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Section 1: canonical paths ----------------------------------------------
# Resolve the SOURCE ROOT from this file's location, not from the caller's cwd.
# tools/lib/common.sh -> two levels up == repository root.
_AR0X_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
export AR0X_SOURCE_ROOT="${AR0X_SOURCE_ROOT:-$(cd -- "${_AR0X_LIB_DIR}/../.." && pwd -P)}"
export AR0X_BUILD_ROOT="${AR0X_BUILD_ROOT:-/opt/ar0x-build}"

export AR0X_PROFILE="${AR0X_PROFILE:-${AR0X_SOURCE_ROOT}/archiso}"
# Disposable staged profile used by tools/bootstrap.sh (Phase 3).
export AR0X_PROFILE_STAGE="${AR0X_PROFILE_STAGE:-${AR0X_BUILD_ROOT}/profile}"
export AR0X_WORK_DIR="${AR0X_WORK_DIR:-${AR0X_BUILD_ROOT}/work}"
export AR0X_OUT_DIR="${AR0X_OUT_DIR:-${AR0X_BUILD_ROOT}/out}"
export AR0X_CHROOT_DIR="${AR0X_CHROOT_DIR:-${AR0X_BUILD_ROOT}/chroot}"
export AR0X_PKG_CACHE="${AR0X_PKG_CACHE:-${AR0X_BUILD_ROOT}/cache/pacman/pkg}"
export AR0X_SRC_DIR="${AR0X_SRC_DIR:-${AR0X_BUILD_ROOT}/src}"
export AR0X_REPO_DIR="${AR0X_REPO_DIR:-${AR0X_BUILD_ROOT}/repo/x86_64}"
export AR0X_KEYS_DIR="${AR0X_KEYS_DIR:-${AR0X_BUILD_ROOT}/keys}"
export AR0X_LOG_DIR="${AR0X_LOG_DIR:-${AR0X_BUILD_ROOT}/logs}"

export AR0X_CONFIG_DIR="${AR0X_SOURCE_ROOT}/config"
export AR0X_ASSETS_DIR="${AR0X_SOURCE_ROOT}/assets"
export AR0X_TOOLS_DIR="${AR0X_SOURCE_ROOT}/tools"
export AR0X_PACKAGES_DIR="${AR0X_SOURCE_ROOT}/packages"
export AR0X_DOCS_DIR="${AR0X_SOURCE_ROOT}/docs"

# --- Section 2: load the version pins ----------------------------------------
# Every script sees the same pinned versions; no script hard-codes a version.
AR0X_VERSIONS_FILE="${AR0X_CONFIG_DIR}/versions.env"
if [[ ! -r "$AR0X_VERSIONS_FILE" ]]; then
    printf '[FAIL] Cannot read %s — run Phase 1 first.\n' "$AR0X_VERSIONS_FILE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$AR0X_VERSIONS_FILE"

# --- Section 3: logging ------------------------------------------------------
# Colours are disabled automatically when stdout is not a TTY (CI / log files).
if [[ -t 1 ]]; then
    _AR0X_C_OK=$'\033[32m'
    _AR0X_C_WARN=$'\033[33m'
    _AR0X_C_ERR=$'\033[31m'
    _AR0X_C_INFO=$'\033[36m'
    _AR0X_C_RST=$'\033[0m'
else
    _AR0X_C_OK=""; _AR0X_C_WARN=""; _AR0X_C_ERR=""; _AR0X_C_INFO=""; _AR0X_C_RST=""
fi

log()     { printf '%s[ .. ]%s %s\n' "$_AR0X_C_INFO" "$_AR0X_C_RST" "$*"; }
section() { printf '\n%s=== %s ===%s\n' "$_AR0X_C_INFO" "$*" "$_AR0X_C_RST"; }
ok()      { printf '%s[ OK ]%s %s\n' "$_AR0X_C_OK"   "$_AR0X_C_RST" "$*"; }
warn()    { printf '%s[WARN]%s %s\n' "$_AR0X_C_WARN" "$_AR0X_C_RST" "$*" >&2; }

# die() aborts immediately. fail() increments a counter for a final verdict.
die()  { printf '%s[FAIL]%s %s\n' "$_AR0X_C_ERR" "$_AR0X_C_RST" "$*" >&2; exit 1; }
AR0X_FAILURES=0
fail() { printf '%s[FAIL]%s %s\n' "$_AR0X_C_ERR" "$_AR0X_C_RST" "$*" >&2; AR0X_FAILURES=$((AR0X_FAILURES + 1)); }
assert_clean() {
    if (( AR0X_FAILURES > 0 )); then
        die "${AR0X_FAILURES} preflight failure(s). Aborting."
    fi
}

# --- Section 4: preflight helpers --------------------------------------------
have_command() { command -v -- "$1" >/dev/null 2>&1; }

require_command() {
    local cmd="$1"
    have_command "$cmd" || die "Required command not found: ${cmd} (run tools/setup-build-env.sh)."
}

require_root() {
    if (( EUID != 0 )); then
        die "This step requires root. Re-run with: sudo ${AR0X_TOOLS_DIR}/setup-build-env.sh"
    fi
}

# mkarchiso only works on an Arch host: it needs pacman, Arch keyrings and
# arch-install-scripts. --allow-non-arch exists for containerised builds where
# the *container* is Arch even though the outer host is not.
require_arch_host() {
    local allow_non_arch="${1:-0}"
    local id="unknown"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$( . /etc/os-release; printf '%s' "${ID:-unknown}" )"
    fi
    case "$id" in
        arch|archlinux|archlinuxarm|artix|endeavouros|manjaro|garuda) return 0 ;;
        *)
            if (( allow_non_arch == 1 )); then
                warn "Host reports ID=${id}. Proceeding only because --allow-non-arch was given."
                return 0
            fi
            fail "Host is not Arch-based (ID=${id}). mkarchiso requires an Arch host or an Arch container."
            return 0
            ;;
    esac
}

# human_bytes: 1536 -> "1.5 KiB". Used by disk/RAM reporting only.
human_bytes() {
    awk -v b="${1:-0}" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf "%.1f %s", b, u[i]
    }'
}

# _report_preflight <mode> <message>
#   mode="fail" -> hard failure (full build mode)
#   mode="warn" -> warning only (--check mode runs on non-build machines)
_report_preflight() {
    if [[ "${1:-fail}" == "warn" ]]; then warn "$2"; else fail "$2"; fi
}

# require_free_space <path> <min_bytes> [fail|warn]
# Walks up to the nearest existing directory so it works before /opt/ar0x-build
# exists. awk MUST use printf "%d": plain `print` emits scientific notation
# (2.06963e+10) for large byte counts, which bash arithmetic cannot parse.
require_free_space() {
    local path="$1"
    local min="$2"
    local mode="${3:-fail}"
    local parent="$path"
    local avail
    while [[ ! -d "$parent" && "$parent" != "/" ]]; do parent="$(dirname -- "$parent")"; done
    avail="$(df -Pk -- "$parent" | awk 'NR==2 {printf "%d", $4 * 1024}')"
    if (( avail < min )); then
        _report_preflight "$mode" \
            "Not enough free space at ${parent}: $(human_bytes "$avail") < required $(human_bytes "$min")."
    else
        ok "Free space at ${parent}: $(human_bytes "$avail") (need $(human_bytes "$min"))"
    fi
}

# mkarchiso uses chroot, mount --bind and device nodes. A noexec/nodev work
# filesystem silently breaks those operations — detect it early.
# NOTE: separate `local` lines are required; `local parent="$path"` in the same
# declaration as `local path="$1"` would reference an unset var under `set -u`.
check_mount_options() {
    local path="$1"
    local mode="${2:-fail}"
    local parent
    local opts=""
    parent="$path"
    while [[ ! -d "$parent" && "$parent" != "/" ]]; do parent="$(dirname -- "$parent")"; done
    if have_command findmnt; then
        opts="$(findmnt -no OPTIONS --target "$parent" 2>/dev/null || true)"
    fi
    if [[ "$opts" == *noexec* || "$opts" == *nodev* ]]; then
        _report_preflight "$mode" \
            "Work filesystem ${parent} is mounted with noexec/nodev (${opts}). mkarchiso needs exec + device nodes."
    elif [[ -n "$opts" ]]; then
        ok "Mount options for ${parent}: ${opts}"
    else
        warn "Could not read mount options for ${parent}; verify manually that it is not noexec/nodev."
    fi
}

# report_host: writes a reproducibility manifest of the exact host tool versions.
report_host() {
    local manifest="${1:-${AR0X_LOG_DIR}/host-manifest.txt}"
    {
        printf '# ar0x build host manifest\n'
        printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'source_root=%s\n' "$AR0X_SOURCE_ROOT"
        printf 'build_root=%s\n' "$AR0X_BUILD_ROOT"
        printf 'ar0x_version=%s\n' "$AR0X_VERSION"
        printf 'snapshot_date=%s\n' "$AR0X_SNAPSHOT_DATE"
        printf 'kernel=%s\n' "$(uname -r)"
        printf 'arch=%s\n' "$(uname -m)"
        printf 'os_id=%s\n' "$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}" )"
        printf 'cpus=%s\n' "$(nproc 2>/dev/null || printf 'unknown')"
        printf 'ram_kb=%s\n' "$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf 'unknown')"
        if have_command pacman; then
            printf 'archiso=%s\n' "$(pacman -Q archiso 2>/dev/null || printf 'NOT-INSTALLED')"
            printf 'pacman=%s\n' "$(pacman -Q pacman 2>/dev/null || printf 'NOT-INSTALLED')"
        fi
        for cmd in mkarchiso pacstrap xorriso mksquashfs mkfs.vfat mformat \
                   grub-mkstandalone syslinux gpg sbsign qemu-system-x86_64 shellcheck; do
            printf '%s=%s\n' "$cmd" "$(command -v "$cmd" 2>/dev/null || printf 'NOT-INSTALLED')"
        done
    } > "$manifest"
    ok "Host manifest written to ${manifest}"
}
