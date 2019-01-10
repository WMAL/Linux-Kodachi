# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi












#warith custom code
source /home/kodachi/.kbase/Globalconfig;

alias home='cd ~';
alias root='cd /';
alias dtop='cd ~/Desktop';
alias q='exit';
alias c='clear';
alias h='history';
alias cs='clear;ls';
alias p='cat';
alias pd='pwd';
alias lsa='ls -a';
alias lsl='ls -l';
alias pd='pwd'ext;
alias t='time';
alias k='kill';
alias null='/dev/null';
alias psgrep='ps aux |grep -v grep |grep -i';
 
 
 # CLI colors
export CLICOLOR=true
# a black
# b red
# c green
# d brown
# e blue
# f magenta
# g cyan
# h light grey
# A bold black, usually shows up as dark grey
# B bold red
# C bold green
# D bold brown, usually shows up as yellow
# E bold blue
# F bold magenta
# G bold cyan
# H bold light grey; looks like bright white
# x default foreground or background
# Order: dir - symlink - socket - pipe - exec - block special - char special - exec setuid - exec setgid - public dir sticky bit - public dir no sticky bit
export LSCOLORS='exfxcxdxbxegedabagacad'

#Prompt and prompt colors
# 30m - Black
# 31m - Red
# 32m - Green
# 33m - Yellow
# 34m - Blue
# 35m - Purple
# 36m - Cyan
# 37m - White
# 0 - Normal
# 1 - Bold
function prompt {
  local BLACK="\[\033[0;30m\]"
  local BLACKBOLD="\[\033[1;30m\]"
  local RED="\[\033[0;31m\]"
  local REDBOLD="\[\033[1;31m\]"
  local GREEN="\[\033[0;32m\]"
  local GREENBOLD="\[\033[1;32m\]"
  local YELLOW="\[\033[0;33m\]"
  local YELLOWBOLD="\[\033[1;33m\]"
  local BLUE="\[\033[0;34m\]"
  local BLUEBOLD="\[\033[1;34m\]"
  local PURPLE="\[\033[0;35m\]"
  local PURPLEBOLD="\[\033[1;35m\]"
  local CYAN="\[\033[0;36m\]"
  local CYANBOLD="\[\033[1;36m\]"
  local WHITE="\[\033[0;37m\]"
  local WHITEBOLD="\[\033[1;37m\]"
export PS1="\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}$BLACKBOLD[\t]$CYANBOLD \u@\h\[\033[00m\]:$BLUEBOLD\w\[\033[00m\] \\$ "
}

prompt



 
vpnFish="";
torifySFish="";
ipFish="";
countryFish="";
securityScoreFish="";
bigMan="";


ipext=$(timeout 5 curl -s https://www.digi77.com/software/vpn/ipcheckplain.php|sed 's/ //g'|xargs);
ipext=$(echo $ipext|grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}');
#ipext="";
if [ -n "$ipext" ] 
then   
	ipFish="IP:${cayn}$ipext ";
	theCountry=$(geoiplookup $ipext|cut -d : -f 2|cut -d , -f 2|sed 's/^ *//;s/ *$//');
	if ! (echo $theCountry|grep resolve > /dev/null)
	then	
		#echo "${green}IP:$ipext Country:$theCountry   ᕦ(ò_óˇ)ᕤ     ${reset}";
		if [ -n "$theCountry" ] 
		then   
			countryFish="${reset}CO:${cayn}$theCountry${reset} "; 
		fi
	fi
fi	



	
	
	
torifySystem=$(cat $Mykodachi_path/torifysystemstatus);
if [[ "$torifySystem" == *Yes* ]]
then
	torifySFish="+Torifid";	
	
fi
		
		
SERVICE='openvpn';
if (ps ax | grep -v grep | grep $SERVICE > /dev/null)
then
	vpnFish="+VPN";
fi
				
 			

	
torifySystem=$(cat $Mykodachi_path/torifysystemstatus);
if [[ "$torifySystem" == *Yes* ]]
then
	torifySFish="+Torifid";	
	SERVICE='openvpn';
	if (ps ax | grep -v grep | grep $SERVICE > /dev/null)
	then
		vpnFish="+VPN";
		bigMan="${green}ᕦ(ò_óˇ)ᕤ"
	else
		bigMan="${yellow}ヽ༼ ಠ益ಠ ༽ﾉ${reset}"; 
	fi
	
else
	bigMan="${yellow}ヽ༼ ಠ益ಠ ༽ﾉ${reset}"; 
fi






x=$(cat $Mykodachi_path/securityscore|sed 's/ //g'|xargs)
securityScoreFish="Score:$x/100";


echo "${white}[${reset}${ipFish}${countryFish}Sec:${cayn}${torifySFish} ${vpnFish} ${securityScoreFish} ${reset}${bigMan}${reset}${white}]" ;

 




# Testing cool stuff
#ipext=$(timeout 2 curl -s http://checkip.dyndns.org/ | grep -o '[0-9][0-9]*.[0-9][0-9]*.[0-9][0-9]*.[0-9]*')
#echo $ipext;

