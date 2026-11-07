# /etc/profile.d/ar0x-wayland.sh — POSIX login-shell fallback.
# /etc/environment.d covers the systemd USER manager; this covers zsh/bash
# LOGIN shells (TTY, SSH). Keep POSIX syntax: no arrays, no [[ ]].
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
