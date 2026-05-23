#
# ~/.bashrc
#

[[ -f ~/.bash_aliases ]] && . ~/.bash_aliases
[[ -f ~/.bash_paths ]] && . ~/.bash_paths

[[ $- != *i* ]] && return

### prompt ###

function ansi { echo "\[\033[$1m\]"; }
ANSI_USER=$(ansi "1;34")
ANSI_HOST=$(ansi "1;35")
ANSI_PATH=$(ansi "33")
ANSI_STAT_OK=$(ansi "32")
ANSI_STAT_ERR=$(ansi "31")
ANSI_ALL=$(ansi "0")
ANSI_END=$(ansi "0")
unset -f ansi

function __update_ps1 {
	local CODE="$?"
	if [ $CODE -eq 0 ]; then ANSI_STAT=${ANSI_STAT_OK}; else ANSI_STAT=${ANSI_STAT_ERR}; fi
	PS1="${ANSI_USER}\u${ANSI_ALL} at ${ANSI_HOST}\h${ANSI_ALL} in ${ANSI_PATH}\w${ANSI_ALL}\n  ${ANSI_STAT}\$${ANSI_END} "
}
PROMPT_COMMAND=__update_ps1

### fetch ###

alias clear='clear && fastfetch -c ~/.config/fastfetch/minimal.jsonc -l small'
clear

### terminal window title (should go last) ###

SHELL_NAME=$(basename ${SHELL})
trap 'if [[ ${BASH_COMMAND} != __* ]]; then echo -ne "\033]0;" && echo -n "${SHELL_NAME}: ${BASH_COMMAND}"; echo -ne "\007"; fi' DEBUG
