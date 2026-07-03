### fetch ###

alias clear='/usr/bin/clear && timeout -sKILL 3s fastfetch -c ~/.config/fastfetch/minimal.jsonc -l small'
clear


### slightly customized cachyos config ###

source /usr/share/cachyos-zsh-config/cachyos-config.zsh
unalias n c
unalias apt apt-get please tb

alias q='exit'
alias :q=q
alias la='ls -A'
alias ll='ls -Al'

alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'
alias ln='ln -i'
alias chown='chown --preserve-root'
alias chmod='chmod --preserve-root'
alias chgrp='chgrp --preserve-root'

alias pacman='sudo pacman'
alias vi='vim'
alias v=vi
alias svim='EDITOR=vim sudoedit'
alias svi=svim
alias sv=svi

alias g='git'
alias gs='g status'
alias ga='g add . && gs'
alias gc='g commit -m"$(head -n1 | tee)"'
alias gp='g push'
alias gpl='g pull'
alias gacp='ga && gc . && gp'

### direnv ###

eval "$(direnv hook zsh)"
