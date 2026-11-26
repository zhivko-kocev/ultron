# shellcheck shell=bash
# step net (on demand): Tailscale with Tailscale SSH.

step_net() {
  say "Starting tailscaled"
  sudo systemctl enable --now tailscaled
  say "Joining your tailnet: open the link below and sign in"
  sudo tailscale up --ssh --operator="$ULTRON_USER" --hostname=ultron || die "tailscale up failed (see above); rerun: ultron install net"
  say "In https://login.tailscale.com/admin/dns turn on MagicDNS and HTTPS Certificates"
}
