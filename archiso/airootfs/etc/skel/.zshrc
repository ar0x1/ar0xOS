# /etc/skel/.zshrc
# ar0x default INTERACTIVE zsh. zsh is the user shell; bash remains the ONLY
# script interpreter (every tools/*.sh starts with #!/bin/bash).
# Starship is installed by config/packages.x86_64; guard the eval so a missing
# binary never leaves the user with a broken prompt on a partial install.

# --- History ----------------------------------------------------------------
HISTFILE="$XDG_DATA_HOME/zsh/history"
HISTSIZE=10000
SAVEHIST=10000
[[ -d "${HISTFILE:h}" ]] || mkdir -p -- "${HISTFILE:h}"
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE INC_APPEND_HISTORY
setopt EXTENDED_HISTORY HIST_VERIFY

# --- Options ----------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS
setopt NO_BEEP PROMPT_SUBST
bindkey -e   # Emacs bindings: predictable for developers coming from bash

# --- Completion -------------------------------------------------------------
autoload -Uz compinit
[[ -d "$XDG_CACHE_HOME/zsh" ]] || mkdir -p -- "$XDG_CACHE_HOME/zsh"
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# --- Prompt -----------------------------------------------------------------
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
else
    PROMPT='%F{cyan}%n@%m%f %F{magenta}%~%f %# '
    RPROMPT='%F{8}%T%f'
fi

# --- Developer aliases ------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias v='nvim'
alias gs='git status --short'
alias gl='git log --oneline --decorate -12'
alias ip='ip -color=auto'
alias ar0x-info='command -v ar0x-info >/dev/null && ar0x-info || echo "ar0x-info arrives in Phase 8"'

# --- First-run hint (Phase 8 replaces with ar0x-welcome) --------------------
if [[ -o interactive && -z "${AR0X_GREETED:-}" ]]; then
    export AR0X_GREETED=1
    print -P '%F{cyan}ar0x 0.1.0 "Neon Root"%f — Wayland / Hyprland / zsh'
fi
