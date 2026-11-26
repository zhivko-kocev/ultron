# shellcheck shell=bash
# ultron pkg install|remove [NAME…]: add or remove apps (official repos and AUR) through yay.
# Without names it opens a searchable list. Your choices are kept in ~/.config/ultron/packages.txt,
# which install and update replay on any machine.

_PKG_LIST="$ULTRON_CONF_DIR/packages.txt"

# _pkg_pick install|remove ARRAY: the packages chosen in fzf into ARRAY (empty when cancelled).
_pkg_pick() {
  local -n _pkg_out=$2
  local header="Type to search · Tab = select several · Enter = go · Esc = cancel"
  [[ -t 0 && -t 1 ]] || die "choosing packages needs a terminal: run 'ultron pkg $1' in one, or use the menu (Super+Alt+Space, then Install or Remove)"
  have fzf || die "fzf is missing: run 'ultron install packages'"
  if [[ $1 == install ]]; then
    say "Loading the package list (official repos and AUR)…"
    mapfile -t _pkg_out < <(yay -Slq 2>/dev/null | awk '!seen[$0]++' |
      fzf --multi --prompt "install ▸ " --header "$header" \
        --preview 'yay -Si {}' --preview-window 'right,60%,wrap' || true)
  else
    mapfile -t _pkg_out < <(yay -Qqe 2>/dev/null |
      fzf --multi --prompt "remove ▸ " --header "$header" \
        --preview 'yay -Qi {}' --preview-window 'right,60%,wrap' || true)
  fi
}

_pkg_list_init() {
  [[ -e "$_PKG_LIST" ]] && return 0
  mkdir -p "$ULTRON_CONF_DIR"
  printf '%s\n' "# Extra packages (official or AUR), one per line. 'ultron install' and 'ultron update' install them." >"$_PKG_LIST"
}

# _pkg_remember NAME…: add names that aren't listed yet.
_pkg_remember() {
  local n added=()
  _pkg_list_init
  local -A have_it=()
  while read -r n; do have_it[$n]=1; done < <(list_packages "$_PKG_LIST")
  for n in "$@"; do
    if [[ -z "${have_it[$n]-}" ]]; then
      printf '%s\n' "$n" >>"$_PKG_LIST"
      have_it[$n]=1
      added+=("$n")
    fi
  done
  if ((${#added[@]})); then
    ok "Added to $_PKG_LIST (a reinstall brings them back): ${added[*]}"
  fi
}

# _pkg_forget NAME…: drop names from the list. Written in place so a symlinked list stays linked.
_pkg_forget() {
  local n tmp
  [[ -e "$_PKG_LIST" ]] || return 0
  for n in "$@"; do
    if list_packages "$_PKG_LIST" | grep -qxF -- "$n"; then
      tmp=$(awk -v n="$n" '{
        line = $0; c = ""; i = index(line, "#")
        if (i) { c = substr(line, i); line = substr(line, 1, i - 1) }
        k = split(line, f, /[[:space:]]+/); out = ""; hit = 0
        for (j = 1; j <= k; j++) {
          if (f[j] == "") continue
          if (f[j] == n) { hit = 1; continue }
          out = out (out == "" ? "" : " ") f[j]
        }
        if (!hit) { print; next }
        if (out != "") print out (c == "" ? "" : " " c)
      }' "$_PKG_LIST")
      printf '%s\n' "$tmp" >"$_PKG_LIST"
      ok "Removed $n from $_PKG_LIST (a reinstall won't bring it back)"
    fi
  done
}

# _pkg_core_warn NAME…: removing a package ultron itself installs only lasts until the next update.
_pkg_core_warn() {
  local n core
  core=$(list_packages "$ULTRON_ROOT"/packages/*.txt 2>/dev/null || true)
  for n in "$@"; do
    if grep -qxF -- "$n" <<<"$core"; then
      warn "$n is part of ultron itself: 'ultron update' installs it again"
    fi
  done
}

cmd_pkg() {
  local sub=${1:-} n rc=0 picked=0 names=()
  case $sub in
  install | remove) shift ;;
  *) die "usage: ultron pkg install|remove [NAME…]   (no names: search and pick in a list)" ;;
  esac
  have yay || die "yay, the package helper, is missing: run 'ultron install aur'"

  if (($#)); then
    names=("$@")
  else
    _pkg_pick "$sub" names
    picked=1
  fi
  if ((${#names[@]} == 0)); then
    say "Nothing selected."
    return 0
  fi
  for n in "${names[@]}"; do
    [[ "$n" =~ ^[A-Za-z0-9@._+][A-Za-z0-9@._+-]*$ ]] || die "'$n' isn't a package name"
  done

  # Without a terminal (an agent, a script) nobody can answer yay's questions; the root step still
  # asks through sudo (an agent's sudo is ultron's popup, which shows the pacman command).
  local quiet=()
  if [[ ! -t 0 ]]; then quiet=(--noconfirm --answerdiff None --answerclean None); fi

  pkg_lock

  if [[ $sub == install ]]; then
    say "Installing: ${names[*]}"
    if yay -S --needed "${quiet[@]}" "${names[@]}"; then
      ok "Installed: ${names[*]}"
      _pkg_remember "${names[@]}"
    else
      rc=$?
      warn "Install failed (yay exit $rc). Nothing was added to $_PKG_LIST. Read the messages above; a typo in the name or a failed AUR build are the usual causes."
    fi
  else
    _pkg_core_warn "${names[@]}"
    say "Removing: ${names[*]} (and dependencies nothing else needs)"
    if yay -Rns "${quiet[@]}" "${names[@]}"; then
      ok "Removed: ${names[*]}"
      _pkg_forget "${names[@]}"
    else
      rc=$?
      warn "Remove failed (yay exit $rc). Read the messages above: usually another package still needs it."
    fi
  fi

  # The picker runs in a window that closes on exit: keep the result readable.
  if ((picked)) && [[ -t 0 ]]; then
    read -rp "Press Enter to close. " _ || true
  fi
  return "$rc"
}
