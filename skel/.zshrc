# Starter zsh config from ultron (copied once because you had no ~/.zshrc; it's yours now).

# History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space extended_history auto_cd interactive_comments

# Emacs-style line editing
bindkey -e

# Completion: case-insensitive, with a menu
autoload -Uz compinit
mkdir -p ~/.cache
compinit -d ~/.cache/zcompdump
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Prompt: user@host ~/path (branch) %
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats ' (%b)'
zstyle ':vcs_info:git:*' actionformats ' (%b|%a)'
precmd() { vcs_info }
setopt prompt_subst
PROMPT='%F{green}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_} %# '

# Tools
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi
if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

# API keys and tokens belong in this untracked file (chmod 600), never in a file you commit.
[[ -r ~/.config/zsh/secrets.zsh ]] && source ~/.config/zsh/secrets.zsh

# Plugins (syntax highlighting must be last)
if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
