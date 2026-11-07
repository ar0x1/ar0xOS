# /etc/skel/.profile
# POSIX login-shell fallback for bash / ssh / TTY. Kept free of bashisms:
# /bin/sh sources this too. /etc/profile.d/ar0x-wayland.sh already exports the
# Wayland session variables for LOGIN shells.
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
export PATH
