#!/bin/bash
# -----------------------------------------------------------------------------
# /usr/share/ar0x/branding/ar0x-screenfetch.sh
# -----------------------------------------------------------------------------
# SOURCED by `screenfetch -a <path>` inside screenFetch's asciiText() function
# ("custom" case). It is NOT a standalone script.
#
# ⚠️ DELIBERATE EXCEPTION to the repo-wide strict-mode rule: this file MUST NOT
#    contain `set -euo pipefail`. screenFetch SOURCES it, so strict mode would
#    leak into screenFetch's own process and abort on its many unset variables.
#    tools/validate-versions.sh carries an explicit exemption for this path.
#
# Contract verified against screenFetch 3.9.9 (KittyKatt/screenFetch,
# screenfetch-dev::asciiText):
#   startline  = first line at which the info column begins
#   logowidth  = rendered logo width (used by -w wrapping)
#   fulloutput = array of printf format strings, each with EXACTLY ONE %s,
#                printed as: printf "${fulloutput[i]}$c0\n" "${out_array[0]}"
#   labelcolor / textcolor = colours of the info column
# -----------------------------------------------------------------------------
startline="0"
logowidth="42"
c1=$'\033[38;2;0;229;255m'      # cyan   #00E5FF
c2=$'\033[38;2;255;46;136m'     # magenta #FF2E88
c3=$'\033[38;2;168;255;96m'     # lime    #A8FF60
labelcolor="${c1}"
textcolor=$'\033[38;2;215;224;238m'  # text #D7E0EE
fulloutput=(
    "${c1}        .--------------------------------. %s"
    "${c1}       /    /\\        .--------------.    \\ %s"
    "${c1}      /    /  \\       |  ${c2}>_${c1}  ar0x   |     \\ %s"
    "${c1}     |    / /\\ \\      '--------------' ${c3}[]${c1}  | %s"
    "${c1}     |    \\ \\/ /                          | %s"
    "${c1}     |     \\  /    N E O N   R O O T      | %s"
    "${c1}      \\     \\/     0 . 1 . 0  /  x86_64  / %s"
    "${c1}       '--------------------------------' %s"
)
