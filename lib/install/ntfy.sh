# shellcheck shell=bash
# step ntfy (on demand, needs net): self-hosted ntfy behind `tailscale serve` for phone pushes.

step_ntfy() {
  local state dns pw pw2 hash token tmpl conf tmp
  state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // ""' 2>/dev/null || true)
  [[ "$state" == Running ]] || die "Tailscale isn't connected: run ultron install net first."
  dns=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // ""' 2>/dev/null || true)
  dns=${dns%.}
  [[ -n "$dns" ]] || die "Tailscale has no DNS name for this PC: turn on MagicDNS in https://login.tailscale.com/admin/dns"

  if ! have ntfy; then
    have yay || die "yay is missing: run ultron install aur first."
    say "Installing the ntfy server (ntfysh-bin from the AUR)"
    yay -S --needed --noconfirm --answerdiff None --answerclean None ntfysh-bin || die "Installing ntfysh-bin failed (see above); rerun: ultron install ntfy"
  fi

  say "Pick a password for the ntfy phone app (user $ULTRON_USER)"
  while true; do
    IFS= read -rsp "Phone-app password: " pw
    echo
    IFS= read -rsp "Again: " pw2
    echo
    if [[ -z "$pw" ]]; then
      echo "The password can't be empty."
    elif [[ "$pw" != "$pw2" ]]; then
      echo "They don't match, try again."
    else
      break
    fi
  done
  hash=$(printf '%s\n%s\n' "$pw" "$pw" | ntfy user hash 2>/dev/null | tail -n1 || true)
  pw="" pw2=""
  # shellcheck disable=SC2016 # a literal "$2" prefix: bcrypt hashes start with it
  [[ "$hash" == '$2'* ]] || die "ntfy user hash didn't return a bcrypt hash."
  token=$(ntfy token generate 2>/dev/null | tail -n1 || true)
  [[ "$token" == tk_* ]] || die "ntfy token generate didn't return a token."

  say "Writing /etc/ntfy/server.yml"
  tmpl=$(<"$ULTRON_ROOT/system/etc/ntfy/server.yml.tmpl")
  conf=${tmpl//@BASE_URL@/"https://$dns"}
  conf=${conf//@USER@/"$ULTRON_USER"}
  conf=${conf//@HASH@/"$hash"}
  conf=${conf//@TOKEN@/"$token"}
  tmp=$(mktemp)
  printf '%s\n' "$conf" >"$tmp"
  sudo install -D -o root -g ntfy -m 0640 "$tmp" /etc/ntfy/server.yml

  say "Writing $NTFY_ENV"
  printf 'NTFY_URL=http://127.0.0.1:2586\nNTFY_TOKEN=%s\n' "$token" >"$tmp"
  sudo install -d -o root -g root -m 0755 "${NTFY_ENV%/*}"
  sudo install -o root -g "$ULTRON_USER" -m 0640 "$tmp" "$NTFY_ENV"
  rm -f "$tmp"

  say "Starting ntfy"
  sudo install -d -o ntfy -g ntfy /var/cache/ntfy /var/lib/ntfy
  sudo systemctl enable ntfy
  sudo systemctl restart ntfy

  say "Publishing ntfy on https://$dns with tailscale serve"
  local out
  if ! out=$(sudo tailscale serve --bg --https=443 http://127.0.0.1:2586 2>&1); then
    printf '%s\n' "$out" >&2
    if grep -qi https <<<"$out"; then
      die "Turn on HTTPS Certificates in https://login.tailscale.com/admin/dns, then rerun: ultron install ntfy"
    fi
    die "tailscale serve failed (see above)."
  fi

  sleep 1
  "$ULTRON_ROOT/bin/ultron" notify --phone ultron "Phone alerts work"

  cat <<TXT

On your phone:
  1. Install Tailscale and sign in with the same account as this PC.
  2. Install ntfy.
  3. In ntfy, subscribe to topic ultron-alerts on server https://$dns
     (Use another server), with user $ULTRON_USER and the password you just picked.
TXT
}
