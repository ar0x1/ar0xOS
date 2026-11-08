# /etc/skel/.bashrc
# bash is the SCRIPT shell on ar0x; zsh is the interactive shell. This file
# exists so `bash -i` / SSH logins still get a usable, branded prompt.
[[ $- != *i* ]] && return
PS1='\[\e[36m\]\u@\h\[\e[0m\] \[\e[35m\]\w\[\e[0m\] \$ '
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'
alias v='nvim'
shopt -s histappend checkwinsize
HISTSIZE=10000
HISTFILESIZE=10000
