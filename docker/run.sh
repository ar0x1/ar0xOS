#!/bin/bash
# -----------------------------------------------------------------------------
# /home/user/ar0xOS/docker/run.sh
# -----------------------------------------------------------------------------
# Phase 2 — convenience wrapper for the privileged ar0x build container.
#
# Usage:
#   ./docker/run.sh --check                 # read-only preflight
#   ./docker/run.sh bash                   # interactive root shell
#   ./docker/run.sh mkarchiso -h           # any command inside the container
#   ./docker/run.sh --rebuild              # force a fresh image build
#
# ⚠️ RISK-016: this uses `privileged: true` (compose.yaml). Local, trusted code
# only. Never wire this into a CI job that checks out untrusted pull requests.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Section 1: resolve the repository root from this script's location ------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"
IMAGE="ar0x-builder:0.1.0"

# --- Section 2: argument parsing ---------------------------------------------
FORCE_REBUILD=0
if [[ "${1:-}" == "--rebuild" ]]; then
    FORCE_REBUILD=1
    shift
fi
if [[ $# -eq 0 ]]; then
    set -- bash
fi

# --- Section 3: prerequisites -------------------------------------------------
command -v docker >/dev/null 2>&1 || {
    printf '[FAIL] docker not found. Install it with: sudo pacman -S docker docker-compose\n' >&2
    exit 1
}
docker compose version >/dev/null 2>&1 || {
    printf '[FAIL] `docker compose` (v2 plugin) not available. Install docker-compose.\n' >&2
    exit 1
}
[[ -f "$COMPOSE_FILE" ]] || { printf '[FAIL] Missing %s\n' "$COMPOSE_FILE" >&2; exit 1; }

# --- Section 4: build the image once (never on every invocation) -------------
if (( FORCE_REBUILD == 1 )) || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    printf '[ .. ] Building %s (first run, this downloads ~1 GB of packages)...\n' "$IMAGE"
    docker compose -f "$COMPOSE_FILE" build
else
    printf '[ OK ] Using cached image %s (use --rebuild to refresh)\n' "$IMAGE"
fi

# --- Section 5: ensure the host build root exists before bind-mounting -------
# If the directory does not exist Docker would silently create a root-owned
# empty dir; create it explicitly with the right permissions instead.
HOST_BUILD_ROOT="${AR0X_HOST_BUILD_ROOT:-/opt/ar0x-build}"
if [[ ! -d "$HOST_BUILD_ROOT" ]]; then
    printf '[ .. ] Creating host build root %s (needs sudo)...\n' "$HOST_BUILD_ROOT"
    sudo install -d -m 0755 \
        "$HOST_BUILD_ROOT/work" "$HOST_BUILD_ROOT/out" \
        "$HOST_BUILD_ROOT/chroot" "$HOST_BUILD_ROOT/cache/pacman/pkg" \
        "$HOST_BUILD_ROOT/src" "$HOST_BUILD_ROOT/repo/x86_64" "$HOST_BUILD_ROOT/logs"
    sudo install -d -m 0700 "$HOST_BUILD_ROOT/keys" "$HOST_BUILD_ROOT/keys/public"
fi

# --- Section 6: run -----------------------------------------------------------
printf '[ .. ] Running inside %s: %s\n' "$IMAGE" "$*"
exec docker compose -f "$COMPOSE_FILE" run --rm ar0x-builder "$@"
