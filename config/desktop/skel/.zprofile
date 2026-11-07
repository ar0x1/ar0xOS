# /etc/skel/.zprofile
# zsh LOGIN shell. Session-wide environment is owned by systemd's
# /etc/environment.d/*.conf (Phases 5-6); this file only starts a Wayland
# session on a bare VT login. SDDM does NOT use this path — it launches the
# Hyprland .desktop session directly.
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" \
      && "${XDG_VTNR:-0}" == "1" && -o interactive ]]; then
    printf '%s\n' 'To start the desktop: exec Hyprland   (or log in via SDDM)'
fi
