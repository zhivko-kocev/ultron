# Starter zsh environment from ultron (copied once; it's yours now).
typeset -U path
path=(~/.local/bin $path)

# Over SSH there's no desktop editor to wait for.
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR="nano" VISUAL="nano"
fi
