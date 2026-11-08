# /etc/skel/.zshenv
# Read for EVERY zsh invocation (including scripts). Keep it tiny and POSIX-
# safe: no oh-my-zsh, no plugins, no commands that print to stdout.
# ⚠️ DO NOT set ZDOTDIR here. Setting it redirects ALL zsh startup files
#    (.zshrc, .zprofile, .zlogin) to that directory, so the /etc/skel/.zshrc
#    shipped below would be silently ignored and users would get a bare
#    default prompt. ar0x keeps zsh dotfiles directly in $HOME.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
# Phase 5 sets session-wide Wayland vars in /etc/environment.d/10-ar0x-wayland.conf
# and /etc/profile.d/ar0x-wayland.sh; do NOT duplicate them here.
