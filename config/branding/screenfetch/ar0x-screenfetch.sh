#!/bin/bash
# -----------------------------------------------------------------------------
# /usr/local/bin/ar0x-screenfetch  (CANONICAL: config/branding/screenfetch/)
# -----------------------------------------------------------------------------
# Convenience wrapper: screenFetch has NO per-user config file, so the branded
# art must be passed with `-a PATH` on every invocation. This wrapper makes
# `ar0x-screenfetch` behave like `fastfetch` / `neofetch`.
#
# screenfetch 3.9.9-1 is an official Arch [extra] package and IS on the ISO.
# Upstream man page: `-a 'PATH' ... custom ASCII art by passing the path to a
# Bash script defining startline and fulloutput variables`.
# -----------------------------------------------------------------------------
set -euo pipefail

AR0X_SCREENFETCH_ART="${AR0X_SCREENFETCH_ART:-/usr/share/ar0x/branding/ar0x-screenfetch.sh}"

if ! command -v screenfetch >/dev/null 2>&1; then
    printf '[FAIL] screenfetch is not installed. Install it with: sudo pacman -S screenfetch\n' >&2
    exit 1
fi
if [[ ! -r "${AR0X_SCREENFETCH_ART}" ]]; then
    printf '[FAIL] branded art missing: %s\n' "${AR0X_SCREENFETCH_ART}" >&2
    exit 1
fi

exec screenfetch -a "${AR0X_SCREENFETCH_ART}" "$@"
